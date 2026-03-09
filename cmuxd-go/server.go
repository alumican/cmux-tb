package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// Client represents a connected WebSocket client.
type Client struct {
	conn *websocket.Conn
	mu   sync.Mutex
	id   uint32
}

// SendText sends a JSON text message to the client.
func (c *Client) SendText(ctx context.Context, data []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.conn.Write(ctx, websocket.MessageText, data)
}

// SendBinary sends a binary message to the client.
func (c *Client) SendBinary(ctx context.Context, data []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.conn.Write(ctx, websocket.MessageBinary, data)
}

// SendPtyData sends PTY output with a 4-byte LE session ID prefix.
func (c *Client) SendPtyData(ctx context.Context, sessionID uint32, data []byte) {
	buf := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(buf[:4], sessionID)
	copy(buf[4:], data)
	c.SendBinary(ctx, buf)
}

// Server holds all shared state.
type Server struct {
	mu             sync.Mutex
	sessions       *SessionManager
	clients        []*Client
	nextClientID   uint32
	terminalConfig json.RawMessage // pre-serialized JSON
	notifications  *NotificationStore
}

func NewServer() *Server {
	return &Server{
		sessions:      NewSessionManager(),
		clients:       nil,
		nextClientID:  1,
		notifications: NewNotificationStore(),
	}
}

func (s *Server) AddClient(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clients = append(s.clients, c)
}

func (s *Server) RemoveClient(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, cl := range s.clients {
		if cl == c {
			s.clients = append(s.clients[:i], s.clients[i+1:]...)
			return
		}
	}
}

// Broadcast sends a text message to all connected clients.
// Must be called with s.mu held.
func (s *Server) Broadcast(ctx context.Context, msg []byte) {
	for _, c := range s.clients {
		c.SendText(ctx, msg)
	}
}

// BroadcastPtyOutput sends PTY data to all connected clients.
func (s *Server) BroadcastPtyOutput(ctx context.Context, sessionID uint32, data []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, c := range s.clients {
		c.SendPtyData(ctx, sessionID, data)
	}
}

// CreateSession creates a new session and starts its reader goroutine.
func (s *Server) CreateSession(cols, rows uint16) (*Session, error) {
	sess, err := s.sessions.Create(cols, rows)
	if err != nil {
		return nil, err
	}
	// Start PTY reader goroutine with background context so it outlives
	// the initial client's request context.
	go s.ptyReader(sess)
	return sess, nil
}

// DestroySession removes and kills a session.
func (s *Server) DestroySession(sessionID uint32) {
	sess := s.sessions.Remove(sessionID)
	if sess != nil {
		sess.Kill()
	}
}

// gatherSessionInfos collects SessionInfo from all sessions.
// Must be called with s.sessions.mu held.
func (s *Server) gatherSessionInfos() []SessionInfo {
	infos := make([]SessionInfo, 0, len(s.sessions.sessions))
	for _, sess := range s.sessions.sessions {
		info := SessionInfo{
			ID:          sess.ID,
			Title:       sess.Meta.Title,
			Description: sess.Meta.Description,
			CWD:         sess.Meta.CWD,
		}
		if sess.Meta.Git != nil {
			info.Branch = sess.Meta.Git.Branch
			info.IsDirty = sess.Meta.Git.IsDirty
		}
		infos = append(infos, info)
	}
	return infos
}

// BuildWorkspaceJSON builds the workspace JSON from current sessions.
func (s *Server) BuildWorkspaceJSON() string {
	s.sessions.mu.Lock()
	infos := s.gatherSessionInfos()
	s.sessions.mu.Unlock()
	return BuildWorkspaceJSON(infos)
}

// BroadcastWorkspaceUpdate sends a workspace_update to all clients.
func (s *Server) BroadcastWorkspaceUpdate(ctx context.Context) {
	wj := s.BuildWorkspaceJSON()
	msg, _ := json.Marshal(map[string]interface{}{
		"type":      "workspace_update",
		"workspace": json.RawMessage(wj),
	})
	s.mu.Lock()
	s.Broadcast(ctx, msg)
	s.mu.Unlock()
}

// BroadcastSessionMetadata sends a session_metadata message to all clients.
// Must be called with s.mu held.
func (s *Server) BroadcastSessionMetadata(ctx context.Context, sess *Session) {
	msg, _ := json.Marshal(SessionMetadataMsg{
		Type:      "session_metadata",
		SessionID: sess.ID,
		Metadata:  sess.Meta,
	})
	s.Broadcast(ctx, msg)
}

// SendSessionMetadata sends a session_metadata message to a single client.
func (s *Server) SendSessionMetadata(ctx context.Context, client *Client, sess *Session) {
	msg, _ := json.Marshal(SessionMetadataMsg{
		Type:      "session_metadata",
		SessionID: sess.ID,
		Metadata:  sess.Meta,
	})
	client.SendText(ctx, msg)
}

const metaCoalesceInterval = 50 * time.Millisecond

// scheduleMetadataBroadcast coalesces rapid metadata changes.
// Must be called with s.mu held. The first change in a window broadcasts
// immediately; subsequent changes within 50ms are batched and sent when
// the timer fires.
func (s *Server) scheduleMetadataBroadcast(sess *Session) {
	ctx := context.Background()
	if sess.metaTimer != nil {
		// Already in coalescing window — mark dirty so timer sends latest
		sess.metaPending = true
		return
	}
	// First change — broadcast immediately, start coalescing window
	s.BroadcastSessionMetadata(ctx, sess)
	sess.metaPending = false
	sess.metaTimer = time.AfterFunc(metaCoalesceInterval, func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		sess.metaTimer = nil
		if sess.metaPending {
			sess.metaPending = false
			s.BroadcastSessionMetadata(ctx, sess)
		}
	})
}

// processOscEvents updates session metadata from parsed OSC events.
// Must be called with s.mu held.
func (s *Server) processOscEvents(sess *Session, events []OscEvent) {
	changed := false
	for _, ev := range events {
		switch ev.Code {
		case 0, 2: // Set title
			if sess.Meta.Title != ev.Data {
				sess.Meta.Title = ev.Data
				changed = true
			}
		case 7: // Set CWD
			path := ParseOsc7Path(ev.Data)
			if path != "" && sess.Meta.CWD != path {
				sess.Meta.CWD = path
				changed = true
			}
		}
	}
	if changed {
		s.scheduleMetadataBroadcast(sess)
		// Also broadcast workspace_update since title may have changed
		infos := func() []SessionInfo {
			s.sessions.mu.Lock()
			defer s.sessions.mu.Unlock()
			return s.gatherSessionInfos()
		}()
		wj := BuildWorkspaceJSON(infos)
		msg, _ := json.Marshal(map[string]interface{}{
			"type":      "workspace_update",
			"workspace": json.RawMessage(wj),
		})
		s.Broadcast(context.Background(), msg)
	}
}

// ptyReader reads from a PTY and broadcasts output to all mux clients.
func (s *Server) ptyReader(sess *Session) {
	ctx := context.Background()
	buf := make([]byte, 8192)
	for sess.alive.Load() {
		n, err := sess.ptmx.Read(buf)
		if err != nil || n == 0 {
			break
		}
		data := buf[:n]
		// Store in ring buffer for attach snapshots
		sess.ring.Write(data)

		// Parse OSC sequences for metadata
		events := sess.oscParser.Feed(data)
		if len(events) > 0 {
			s.mu.Lock()
			s.processOscEvents(sess, events)
			s.mu.Unlock()
		}

		// Broadcast to all clients
		s.BroadcastPtyOutput(ctx, sess.ID, data)
	}
	// Session died — notify clients
	msg := fmt.Sprintf(`{"type":"session_exited","sessionId":%d}`, sess.ID)
	s.mu.Lock()
	s.Broadcast(ctx, []byte(msg))
	s.mu.Unlock()
}
