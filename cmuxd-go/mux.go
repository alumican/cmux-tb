package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/coder/websocket"
)

// HandleMux handles a multiplexed mode WebSocket connection.
func HandleMux(srv *Server, w http.ResponseWriter, r *http.Request) {
	cols := parseQueryUint16(r, "cols", 80)
	rows := parseQueryUint16(r, "rows", 24)

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	defer conn.CloseNow()

	// Use background context so writes don't fail when the HTTP request context
	// is cancelled (which happens when the connection closes).
	ctx := context.Background()

	// Assign client ID
	srv.mu.Lock()
	clientID := srv.nextClientID
	srv.nextClientID++
	srv.mu.Unlock()

	client := &Client{conn: conn, id: clientID}

	// Track sessions this client is attached to
	clientSessions := make(map[uint32]bool)

	defer func() {
		// Detach from all sessions; destroy orphaned ones
		for sid := range clientSessions {
			srv.sessions.mu.Lock()
			sess := srv.sessions.sessions[sid]
			if sess == nil {
				srv.sessions.mu.Unlock()
				continue
			}
			sess.DetachClient(clientID)
			wasDriverReleased := sess.DriverID == nil && sess.Mode == ModeSingleDriver
			if sess.ClientCount() == 0 {
				delete(srv.sessions.sessions, sid)
				srv.sessions.mu.Unlock()
				sess.Kill()
			} else {
				if wasDriverReleased {
					srv.mu.Lock()
					dmsg := fmt.Sprintf(`{"type":"driver_changed","sessionId":%d,"driverId":null}`, sid)
					srv.Broadcast(ctx, []byte(dmsg))
					srv.mu.Unlock()
				}
				srv.sessions.mu.Unlock()
			}
		}

		// Broadcast client_left
		leftMsg, _ := json.Marshal(ClientLeftMsg{Type: "client_left", ClientID: clientID})
		srv.mu.Lock()
		srv.Broadcast(ctx, leftMsg)
		srv.mu.Unlock()

		srv.RemoveClient(client)
	}()

	// Create initial session
	initialSess, err := srv.CreateSession(cols, rows)
	if err != nil {
		conn.Close(websocket.StatusInternalError, "failed to spawn PTY")
		return
	}
	initialSess.AttachClient(clientID, ClientSize{Cols: cols, Rows: rows})
	clientSessions[initialSess.ID] = true

	// Send workspace snapshot
	{
		srv.mu.Lock()
		wj := srv.BuildWorkspaceJSON()
		tcj := srv.terminalConfig
		srv.mu.Unlock()

		snapshot := WorkspaceSnapshotMsg{
			Type:             "workspace_snapshot",
			Workspace:        json.RawMessage(wj),
			InitialSessionID: initialSess.ID,
			ClientID:         clientID,
		}
		if len(tcj) > 0 {
			raw := json.RawMessage(tcj)
			snapshot.TerminalConfig = &raw
		}
		msg, _ := json.Marshal(snapshot)
		client.SendText(ctx, msg)
	}

	// Send initial session_metadata for the initial session
	srv.mu.Lock()
	srv.SendSessionMetadata(ctx, client, initialSess)
	srv.mu.Unlock()

	// Read notifications and add client to broadcast list atomically.
	// This ensures no notification is missed: the list includes everything
	// created before the lock, and any notification created after will be
	// broadcast to this client (since it's now in the client list).
	srv.mu.Lock()
	notifications := srv.notifications.List(nil)
	if notifications == nil {
		notifications = []*Notification{}
	}
	srv.clients = append(srv.clients, client)
	srv.mu.Unlock()

	// Send notifications list
	{
		nMsg, _ := json.Marshal(NotificationsListMsg{
			Type:          "notifications_list",
			Notifications: notifications,
		})
		client.SendText(ctx, nMsg)
	}

	// Broadcast client_joined (now that client is in the list)
	{
		joinMsg, _ := json.Marshal(ClientJoinedMsg{Type: "client_joined", ClientID: clientID})
		srv.mu.Lock()
		srv.Broadcast(ctx, joinMsg)
		srv.mu.Unlock()
	}

	// WS read loop
	for {
		msgType, data, err := conn.Read(ctx)
		if err != nil {
			break
		}
		switch msgType {
		case websocket.MessageText:
			handleControlMessage(ctx, srv, client, clientSessions, data, cols, rows)
		case websocket.MessageBinary:
			if len(data) < 4 {
				continue
			}
			sid := binary.LittleEndian.Uint32(data[:4])
			input := data[4:]
			srv.sessions.mu.Lock()
			sess := srv.sessions.sessions[sid]
			if sess != nil {
				allowed := sess.CanInput(client.id)
				srv.sessions.mu.Unlock()
				if allowed {
					sess.WriteInput(input)
				}
			} else {
				srv.sessions.mu.Unlock()
			}
		}
	}
}

func handleControlMessage(ctx context.Context, srv *Server, client *Client, clientSessions map[uint32]bool, data []byte, defaultCols, defaultRows uint16) {
	var generic GenericMsg
	if json.Unmarshal(data, &generic) != nil {
		return
	}

	switch generic.Type {
	case "create_session":
		var msg CreateSessionMsg
		json.Unmarshal(data, &msg)
		cols := msg.Cols
		rows := msg.Rows
		if cols == 0 { cols = defaultCols }
		if rows == 0 { rows = defaultRows }

		sess, err := srv.CreateSession(cols, rows)
		if err != nil {
			return
		}
		sess.AttachClient(client.id, ClientSize{Cols: cols, Rows: rows})
		clientSessions[sess.ID] = true

		reply, _ := json.Marshal(SessionCreatedMsg{
			Type:      "session_created",
			SessionID: sess.ID,
			Cols:      cols,
			Rows:      rows,
		})
		client.SendText(ctx, reply)
		srv.mu.Lock()
		srv.SendSessionMetadata(ctx, client, sess)
		srv.mu.Unlock()
		srv.BroadcastWorkspaceUpdate(ctx)

	case "destroy_session":
		var msg DestroySessionMsg
		json.Unmarshal(data, &msg)
		delete(clientSessions, msg.SessionID)
		srv.DestroySession(msg.SessionID)
		srv.notifications.RemoveForSession(msg.SessionID)

		reply, _ := json.Marshal(SessionDestroyedMsg{
			Type:      "session_destroyed",
			SessionID: msg.SessionID,
		})
		srv.mu.Lock()
		srv.Broadcast(ctx, reply)
		srv.mu.Unlock()
		srv.BroadcastWorkspaceUpdate(ctx)

	case "resize":
		var msg ResizeMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		if sess != nil {
			changed := sess.UpdateClientSize(client.id, ClientSize{Cols: msg.Cols, Rows: msg.Rows})
			if changed {
				reply, _ := json.Marshal(SessionResizedMsg{
					Type:      "session_resized",
					SessionID: msg.SessionID,
					Cols:      sess.Cols,
					Rows:      sess.Rows,
				})
				srv.mu.Lock()
				srv.Broadcast(ctx, reply)
				srv.mu.Unlock()
			}
		}
		srv.sessions.mu.Unlock()

	case "attach_session":
		var msg AttachSessionMsg
		json.Unmarshal(data, &msg)
		cols := msg.Cols
		rows := msg.Rows
		if cols == 0 { cols = defaultCols }
		if rows == 0 { rows = defaultRows }

		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		srv.sessions.mu.Unlock()

		if sess != nil {
			sess.AttachClient(client.id, ClientSize{Cols: cols, Rows: rows})
			clientSessions[msg.SessionID] = true

			// Send attach confirmation
			reply, _ := json.Marshal(SessionAttachedMsg{
				Type:      "session_attached",
				SessionID: msg.SessionID,
			})
			client.SendText(ctx, reply)

			// Send ring buffer snapshot
			snapshot := sess.GenerateSnapshot()
			if len(snapshot) > 0 {
				client.SendPtyData(ctx, msg.SessionID, snapshot)
			}

			// Send current metadata
			srv.mu.Lock()
			srv.SendSessionMetadata(ctx, client, sess)
			srv.mu.Unlock()
		} else {
			reply, _ := json.Marshal(ErrorMsg{
				Type:      "error",
				Message:   "session not found",
				SessionID: msg.SessionID,
			})
			client.SendText(ctx, reply)
		}

	case "detach_session":
		var msg DetachSessionMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		if sess != nil {
			sess.DetachClient(client.id)
			delete(clientSessions, msg.SessionID)
		}
		srv.sessions.mu.Unlock()

	case "set_session_mode":
		var msg SetSessionModeMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		if sess != nil {
			switch msg.Mode {
			case "shared":
				sess.Mode = ModeShared
				sess.DriverID = nil
			case "single_driver":
				sess.Mode = ModeSingleDriver
				sess.DriverID = &client.id
			}
			driverMsg := DriverChangedMsg{
				Type:      "driver_changed",
				SessionID: msg.SessionID,
				DriverID:  sess.DriverID,
				Mode:      msg.Mode,
			}
			reply, _ := json.Marshal(driverMsg)
			srv.mu.Lock()
			srv.Broadcast(ctx, reply)
			srv.mu.Unlock()
		}
		srv.sessions.mu.Unlock()

	case "request_driver":
		var msg RequestDriverMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		if sess != nil && sess.Mode == ModeSingleDriver && sess.DriverID == nil {
			sess.DriverID = &client.id
			reply, _ := json.Marshal(DriverChangedMsg{
				Type:      "driver_changed",
				SessionID: msg.SessionID,
				DriverID:  &client.id,
			})
			srv.mu.Lock()
			srv.Broadcast(ctx, reply)
			srv.mu.Unlock()
		}
		srv.sessions.mu.Unlock()

	case "release_driver":
		var msg ReleaseDriverMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		if sess != nil && sess.DriverID != nil && *sess.DriverID == client.id {
			sess.DriverID = nil
			reply, _ := json.Marshal(DriverChangedMsg{
				Type:      "driver_changed",
				SessionID: msg.SessionID,
				DriverID:  nil,
			})
			srv.mu.Lock()
			srv.Broadcast(ctx, reply)
			srv.mu.Unlock()
		}
		srv.sessions.mu.Unlock()

	case "update_metadata":
		var msg UpdateMetadataMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		srv.sessions.mu.Unlock()
		if sess == nil {
			return
		}

		srv.mu.Lock()
		applyMetadataUpdate(sess, &msg)
		srv.scheduleMetadataBroadcast(sess)
		srv.mu.Unlock()

		// If workspace-visible fields changed, broadcast workspace update
		if msg.CWD != "" || msg.Git != nil || msg.ClearGit || msg.Description != nil {
			srv.BroadcastWorkspaceUpdate(ctx)
		}

	case "notify":
		var msg NotifyMsg
		json.Unmarshal(data, &msg)
		srv.sessions.mu.Lock()
		sess := srv.sessions.sessions[msg.SessionID]
		srv.sessions.mu.Unlock()
		if sess == nil {
			return
		}
		n := srv.notifications.Add(msg.SessionID, msg.Title, msg.Subtitle, msg.Body)
		reply, _ := json.Marshal(NotificationMsg{
			Type:         "notification",
			Notification: n,
		})
		srv.mu.Lock()
		srv.Broadcast(ctx, reply)
		srv.mu.Unlock()

	case "mark_notification_read":
		var msg MarkNotificationReadMsg
		json.Unmarshal(data, &msg)
		if msg.SessionID != nil {
			// Mark all for session
			marked := srv.notifications.MarkAllReadForSession(*msg.SessionID)
			srv.mu.Lock()
			for _, n := range marked {
				reply, _ := json.Marshal(NotificationReadMsg{
					Type:           "notification_read",
					NotificationID: n.ID,
				})
				srv.Broadcast(ctx, reply)
			}
			srv.mu.Unlock()
		} else if msg.NotificationID != 0 {
			n := srv.notifications.MarkRead(msg.NotificationID)
			if n != nil {
				reply, _ := json.Marshal(NotificationReadMsg{
					Type:           "notification_read",
					NotificationID: n.ID,
				})
				srv.mu.Lock()
				srv.Broadcast(ctx, reply)
				srv.mu.Unlock()
			}
		}

	case "clear_notifications":
		var msg ClearNotificationsMsg
		json.Unmarshal(data, &msg)
		count := srv.notifications.Clear(msg.SessionID)
		reply, _ := json.Marshal(NotificationsClearedMsg{
			Type:      "notifications_cleared",
			SessionID: msg.SessionID,
			Count:     count,
		})
		srv.mu.Lock()
		srv.Broadcast(ctx, reply)
		srv.mu.Unlock()
	}
}

// applyMetadataUpdate applies mutations from an UpdateMetadataMsg to session metadata.
// Must be called with srv.mu held.
func applyMetadataUpdate(sess *Session, msg *UpdateMetadataMsg) {
	meta := &sess.Meta

	if msg.CWD != "" {
		meta.CWD = msg.CWD
	}

	if msg.SetStatus != nil {
		if meta.Status == nil {
			meta.Status = make(map[string]*StatusEntry)
		}
		msg.SetStatus.Timestamp = time.Now().UnixMilli()
		meta.Status[msg.SetStatus.Key] = msg.SetStatus
	}
	if msg.RemoveStatus != "" {
		delete(meta.Status, msg.RemoveStatus)
	}
	if msg.ClearStatus {
		meta.Status = make(map[string]*StatusEntry)
	}

	if msg.Log != nil {
		msg.Log.Timestamp = time.Now().UnixMilli()
		meta.Log = append(meta.Log, msg.Log)
		if len(meta.Log) > maxLogEntries {
			meta.Log = meta.Log[len(meta.Log)-maxLogEntries:]
		}
	}
	if msg.ClearLog {
		meta.Log = nil
	}

	if msg.Git != nil {
		meta.Git = msg.Git
	}
	if msg.ClearGit {
		meta.Git = nil
	}

	if msg.Ports != nil {
		meta.Ports = msg.Ports
	}

	if msg.Progress != nil {
		meta.Progress = msg.Progress
	}
	if msg.ClearProgress {
		meta.Progress = nil
	}

	if msg.Description != nil {
		meta.Description = *msg.Description
	}
}
