package main

import "encoding/json"

// --- Client → Server messages ---

type CreateSessionMsg struct {
	Type string `json:"type"` // "create_session"
	Cols uint16 `json:"cols"`
	Rows uint16 `json:"rows"`
}

type DestroySessionMsg struct {
	Type      string `json:"type"` // "destroy_session"
	SessionID uint32 `json:"sessionId"`
}

type ResizeMsg struct {
	Type      string `json:"type"` // "resize"
	SessionID uint32 `json:"sessionId"`
	Cols      uint16 `json:"cols"`
	Rows      uint16 `json:"rows"`
}

type AttachSessionMsg struct {
	Type      string `json:"type"` // "attach_session"
	SessionID uint32 `json:"sessionId"`
	Cols      uint16 `json:"cols"`
	Rows      uint16 `json:"rows"`
}

type DetachSessionMsg struct {
	Type      string `json:"type"` // "detach_session"
	SessionID uint32 `json:"sessionId"`
}

type SetSessionModeMsg struct {
	Type      string `json:"type"` // "set_session_mode"
	SessionID uint32 `json:"sessionId"`
	Mode      string `json:"mode"` // "shared" or "single_driver"
}

type RequestDriverMsg struct {
	Type      string `json:"type"` // "request_driver"
	SessionID uint32 `json:"sessionId"`
}

type ReleaseDriverMsg struct {
	Type      string `json:"type"` // "release_driver"
	SessionID uint32 `json:"sessionId"`
}

// --- Server → Client messages ---

type WorkspaceSnapshotMsg struct {
	Type             string           `json:"type"` // "workspace_snapshot"
	Workspace        json.RawMessage  `json:"workspace"`
	InitialSessionID uint32           `json:"initialSessionId"`
	ClientID         uint32           `json:"clientId"`
	TerminalConfig   *json.RawMessage `json:"terminalConfig,omitempty"`
}

type WorkspaceUpdateMsg struct {
	Type      string          `json:"type"` // "workspace_update"
	Workspace json.RawMessage `json:"workspace"`
}

type SessionCreatedMsg struct {
	Type      string `json:"type"` // "session_created"
	SessionID uint32 `json:"sessionId"`
	Cols      uint16 `json:"cols"`
	Rows      uint16 `json:"rows"`
}

type SessionDestroyedMsg struct {
	Type      string `json:"type"` // "session_destroyed"
	SessionID uint32 `json:"sessionId"`
}

type SessionExitedMsg struct {
	Type      string `json:"type"` // "session_exited"
	SessionID uint32 `json:"sessionId"`
}

type SessionAttachedMsg struct {
	Type      string `json:"type"` // "session_attached"
	SessionID uint32 `json:"sessionId"`
}

type SessionResizedMsg struct {
	Type      string `json:"type"` // "session_resized"
	SessionID uint32 `json:"sessionId"`
	Cols      uint16 `json:"cols"`
	Rows      uint16 `json:"rows"`
}

type ClientJoinedMsg struct {
	Type     string `json:"type"` // "client_joined"
	ClientID uint32 `json:"clientId"`
}

type ClientLeftMsg struct {
	Type     string `json:"type"` // "client_left"
	ClientID uint32 `json:"clientId"`
}

type DriverChangedMsg struct {
	Type      string  `json:"type"` // "driver_changed"
	SessionID uint32  `json:"sessionId"`
	DriverID  *uint32 `json:"driverId"` // null = no driver
	Mode      string  `json:"mode,omitempty"`
}

type ErrorMsg struct {
	Type      string `json:"type"` // "error"
	Message   string `json:"message"`
	SessionID uint32 `json:"sessionId,omitempty"`
}

// --- Metadata messages ---

// SessionMetadataMsg is sent server→client with full metadata snapshot.
type SessionMetadataMsg struct {
	Type      string          `json:"type"` // "session_metadata"
	SessionID uint32          `json:"sessionId"`
	Metadata  SessionMetadata `json:"metadata"`
}

// UpdateMetadataMsg is sent client→server by shell integrations.
type UpdateMetadataMsg struct {
	Type          string         `json:"type"` // "update_metadata"
	SessionID     uint32         `json:"sessionId"`
	SetStatus     *StatusEntry   `json:"setStatus,omitempty"`
	RemoveStatus  string         `json:"removeStatus,omitempty"`
	ClearStatus   bool           `json:"clearStatus,omitempty"`
	Log           *LogEntry      `json:"log,omitempty"`
	ClearLog      bool           `json:"clearLog,omitempty"`
	Git           *GitBranchInfo `json:"git,omitempty"`
	ClearGit      bool           `json:"clearGit,omitempty"`
	Ports         []int          `json:"ports,omitempty"`
	Progress      *ProgressInfo  `json:"progress,omitempty"`
	ClearProgress bool           `json:"clearProgress,omitempty"`
	CWD           string         `json:"cwd,omitempty"`
	Description   *string        `json:"description,omitempty"`
}

// --- Notification messages ---

// NotifyMsg is sent client→server to create a notification.
type NotifyMsg struct {
	Type      string `json:"type"` // "notify"
	SessionID uint32 `json:"sessionId"`
	Title     string `json:"title"`
	Subtitle  string `json:"subtitle,omitempty"`
	Body      string `json:"body,omitempty"`
}

// NotificationMsg is sent server→client when a notification is created or updated.
type NotificationMsg struct {
	Type         string        `json:"type"` // "notification"
	Notification *Notification `json:"notification"`
}

// MarkNotificationReadMsg is sent client→server to mark a notification as read.
type MarkNotificationReadMsg struct {
	Type           string  `json:"type"` // "mark_notification_read"
	NotificationID uint64  `json:"notificationId,omitempty"`
	SessionID      *uint32 `json:"sessionId,omitempty"` // mark all for session
}

// NotificationReadMsg is sent server→client when a notification is marked read.
type NotificationReadMsg struct {
	Type           string `json:"type"` // "notification_read"
	NotificationID uint64 `json:"notificationId"`
}

// ClearNotificationsMsg is sent client→server to clear notifications.
type ClearNotificationsMsg struct {
	Type      string  `json:"type"` // "clear_notifications"
	SessionID *uint32 `json:"sessionId,omitempty"` // nil = clear all
}

// NotificationsClearedMsg is sent server→client when notifications are cleared.
type NotificationsClearedMsg struct {
	Type      string  `json:"type"` // "notifications_cleared"
	SessionID *uint32 `json:"sessionId,omitempty"`
	Count     int     `json:"count"`
}

// NotificationsListMsg is sent server→client with all notifications.
type NotificationsListMsg struct {
	Type          string          `json:"type"` // "notifications_list"
	Notifications []*Notification `json:"notifications"`
}

// GenericMsg is used to extract just the type field for dispatch.
type GenericMsg struct {
	Type string `json:"type"`
}

// LegacyResizeMsg is the resize message in legacy mode (no sessionId).
type LegacyResizeMsg struct {
	Type string `json:"type"`
	Cols uint16 `json:"cols"`
	Rows uint16 `json:"rows"`
}
