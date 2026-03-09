package main

import (
	"fmt"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"github.com/creack/pty"
)

// SessionMetadata holds per-session sidebar metadata.
type SessionMetadata struct {
	Title       string                  `json:"title"`
	Description string                  `json:"description,omitempty"`
	CWD         string                  `json:"cwd,omitempty"`
	Git         *GitBranchInfo          `json:"git,omitempty"`
	Ports       []int                   `json:"ports,omitempty"`
	Status      map[string]*StatusEntry `json:"status,omitempty"`
	Log         []*LogEntry             `json:"log,omitempty"`
	Progress    *ProgressInfo           `json:"progress,omitempty"`
}

// GitBranchInfo holds git branch metadata.
type GitBranchInfo struct {
	Branch  string `json:"branch"`
	IsDirty bool   `json:"isDirty,omitempty"`
}

// StatusEntry holds a key-value status pill.
type StatusEntry struct {
	Key       string `json:"key"`
	Value     string `json:"value"`
	Icon      string `json:"icon,omitempty"`
	Color     string `json:"color,omitempty"`
	Timestamp int64  `json:"timestamp"`
}

// LogEntry holds a sidebar log message.
type LogEntry struct {
	Message   string `json:"message"`
	Level     string `json:"level,omitempty"`
	Source    string `json:"source,omitempty"`
	Timestamp int64  `json:"timestamp"`
}

// ProgressInfo holds a progress bar state.
type ProgressInfo struct {
	Value float64 `json:"value"`
	Label string  `json:"label,omitempty"`
}

const maxLogEntries = 50

// SessionMode controls input access.
type SessionMode int

const (
	ModeShared       SessionMode = iota
	ModeSingleDriver             // only the driver can send input
)

// ClientSize tracks a client's terminal dimensions.
type ClientSize struct {
	Cols uint16
	Rows uint16
}

// Session represents a single PTY session.
type Session struct {
	ID    uint32
	ptmx  *os.File
	cmd   *exec.Cmd
	Cols  uint16
	Rows  uint16
	alive atomic.Bool
	ring  *RingBuffer

	// Multiplayer state (protected by Server.mu)
	Mode        SessionMode
	DriverID    *uint32 // nil = no driver
	ClientSizes map[uint32]ClientSize

	// Metadata (protected by Server.mu)
	Meta      SessionMetadata
	oscParser OscParser

	// Coalescing timer for metadata broadcasts (protected by Server.mu)
	metaTimer    *time.Timer
	metaPending  bool
}

// SpawnSession creates a new PTY session.
func SpawnSession(id uint32, cols, rows uint16) (*Session, error) {
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/zsh"
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	// Set working directory
	if cwd := os.Getenv("PTY_CWD"); cwd != "" {
		cmd.Dir = cwd
	} else if home := os.Getenv("HOME"); home != "" {
		cmd.Dir = home
	}

	winSize := &pty.Winsize{
		Cols: cols,
		Rows: rows,
	}

	ptmx, err := pty.StartWithSize(cmd, winSize)
	if err != nil {
		return nil, fmt.Errorf("pty start: %w", err)
	}

	s := &Session{
		ID:          id,
		ptmx:        ptmx,
		cmd:         cmd,
		Cols:        cols,
		Rows:        rows,
		ring:        NewRingBuffer(defaultRingSize),
		ClientSizes: make(map[uint32]ClientSize),
		Meta: SessionMetadata{
			Title:  "Terminal",
			CWD:    cmd.Dir,
			Status: make(map[string]*StatusEntry),
		},
	}
	s.alive.Store(true)
	return s, nil
}

// Resize changes the PTY window size.
func (s *Session) Resize(cols, rows uint16) {
	s.Cols = cols
	s.Rows = rows
	ws := struct {
		Row    uint16
		Col    uint16
		Xpixel uint16
		Ypixel uint16
	}{rows, cols, 0, 0}
	syscall.Syscall(syscall.SYS_IOCTL,
		s.ptmx.Fd(),
		uintptr(syscall.TIOCSWINSZ),
		uintptr(unsafe.Pointer(&ws)),
	)
}

// WriteInput sends data to the PTY.
func (s *Session) WriteInput(data []byte) error {
	_, err := s.ptmx.Write(data)
	return err
}

// Kill terminates the session.
func (s *Session) Kill() {
	if !s.alive.CompareAndSwap(true, false) {
		return
	}
	s.ptmx.Close()
	if s.cmd.Process != nil {
		s.cmd.Process.Signal(syscall.SIGTERM)
		s.cmd.Process.Wait()
	}
}

// CanInput checks if a client can send input.
func (s *Session) CanInput(clientID uint32) bool {
	if s.Mode == ModeShared {
		return true
	}
	return s.DriverID != nil && *s.DriverID == clientID
}

// AttachClient registers a client.
func (s *Session) AttachClient(clientID uint32, size ClientSize) {
	s.ClientSizes[clientID] = size
}

// DetachClient removes a client.
func (s *Session) DetachClient(clientID uint32) {
	delete(s.ClientSizes, clientID)
	if s.DriverID != nil && *s.DriverID == clientID {
		s.DriverID = nil
	}
}

// ClientCount returns number of attached clients.
func (s *Session) ClientCount() int {
	return len(s.ClientSizes)
}

// UpdateClientSize updates a client's size and applies smallest-wins.
// Returns true if the effective session size changed.
func (s *Session) UpdateClientSize(clientID uint32, size ClientSize) bool {
	s.ClientSizes[clientID] = size
	return s.applySmallestWins()
}

func (s *Session) applySmallestWins() bool {
	if len(s.ClientSizes) == 0 {
		return false
	}
	var minCols, minRows uint16 = 0xFFFF, 0xFFFF
	for _, sz := range s.ClientSizes {
		if sz.Cols < minCols {
			minCols = sz.Cols
		}
		if sz.Rows < minRows {
			minRows = sz.Rows
		}
	}
	if minCols != s.Cols || minRows != s.Rows {
		s.Resize(minCols, minRows)
		return true
	}
	return false
}

// GenerateSnapshot returns the ring buffer contents for attach.
func (s *Session) GenerateSnapshot() []byte {
	return s.ring.Snapshot()
}

// SessionManager manages all active sessions.
type SessionManager struct {
	mu       sync.Mutex
	sessions map[uint32]*Session
	nextID   uint32
}

func NewSessionManager() *SessionManager {
	return &SessionManager{
		sessions: make(map[uint32]*Session),
		nextID:   1,
	}
}

func (m *SessionManager) Create(cols, rows uint16) (*Session, error) {
	m.mu.Lock()
	id := m.nextID
	m.nextID++
	m.mu.Unlock()

	sess, err := SpawnSession(id, cols, rows)
	if err != nil {
		return nil, err
	}

	m.mu.Lock()
	m.sessions[id] = sess
	m.mu.Unlock()
	return sess, nil
}

func (m *SessionManager) Get(id uint32) *Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sessions[id]
}

func (m *SessionManager) Remove(id uint32) *Session {
	m.mu.Lock()
	defer m.mu.Unlock()
	s := m.sessions[id]
	delete(m.sessions, id)
	return s
}

func (m *SessionManager) IDs() []uint32 {
	m.mu.Lock()
	defer m.mu.Unlock()
	ids := make([]uint32, 0, len(m.sessions))
	for id := range m.sessions {
		ids = append(ids, id)
	}
	return ids
}

func (m *SessionManager) DestroyAll() {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, s := range m.sessions {
		s.Kill()
	}
	m.sessions = nil
}
