package main

import (
	"sync"
	"sync/atomic"
	"time"
)

// Notification represents a terminal notification.
type Notification struct {
	ID        uint64 `json:"id"`
	SessionID uint32 `json:"sessionId"`
	Title     string `json:"title"`
	Subtitle  string `json:"subtitle,omitempty"`
	Body      string `json:"body,omitempty"`
	CreatedAt int64  `json:"createdAt"`
	IsRead    bool   `json:"isRead"`
}

// NotificationStore manages notifications for all sessions.
type NotificationStore struct {
	mu            sync.Mutex
	notifications []*Notification
	nextID        atomic.Uint64
}

const maxNotifications = 200

func NewNotificationStore() *NotificationStore {
	s := &NotificationStore{}
	s.nextID.Store(1)
	return s
}

// Add creates a new notification and returns it.
func (s *NotificationStore) Add(sessionID uint32, title, subtitle, body string) *Notification {
	n := &Notification{
		ID:        s.nextID.Add(1) - 1,
		SessionID: sessionID,
		Title:     title,
		Subtitle:  subtitle,
		Body:      body,
		CreatedAt: time.Now().UnixMilli(),
		IsRead:    false,
	}
	s.mu.Lock()
	s.notifications = append(s.notifications, n)
	if len(s.notifications) > maxNotifications {
		s.notifications = s.notifications[len(s.notifications)-maxNotifications:]
	}
	s.mu.Unlock()
	return n
}

// MarkRead marks a notification as read. Returns the notification if found.
func (s *NotificationStore) MarkRead(id uint64) *Notification {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, n := range s.notifications {
		if n.ID == id {
			n.IsRead = true
			return n
		}
	}
	return nil
}

// MarkAllReadForSession marks all notifications for a session as read.
func (s *NotificationStore) MarkAllReadForSession(sessionID uint32) []*Notification {
	s.mu.Lock()
	defer s.mu.Unlock()
	var marked []*Notification
	for _, n := range s.notifications {
		if n.SessionID == sessionID && !n.IsRead {
			n.IsRead = true
			marked = append(marked, n)
		}
	}
	return marked
}

// Clear removes all notifications, or only for a specific session.
// Returns the count of removed notifications.
func (s *NotificationStore) Clear(sessionID *uint32) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sessionID == nil {
		count := len(s.notifications)
		s.notifications = nil
		return count
	}
	count := 0
	filtered := s.notifications[:0]
	for _, n := range s.notifications {
		if n.SessionID == *sessionID {
			count++
		} else {
			filtered = append(filtered, n)
		}
	}
	s.notifications = filtered
	return count
}

// List returns all notifications, optionally filtered by session.
func (s *NotificationStore) List(sessionID *uint32) []*Notification {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sessionID == nil {
		result := make([]*Notification, len(s.notifications))
		copy(result, s.notifications)
		return result
	}
	var result []*Notification
	for _, n := range s.notifications {
		if n.SessionID == *sessionID {
			result = append(result, n)
		}
	}
	return result
}

// UnreadCount returns the count of unread notifications.
func (s *NotificationStore) UnreadCount(sessionID *uint32) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	count := 0
	for _, n := range s.notifications {
		if !n.IsRead && (sessionID == nil || n.SessionID == *sessionID) {
			count++
		}
	}
	return count
}

// RemoveForSession removes all notifications for a session (cleanup on destroy).
func (s *NotificationStore) RemoveForSession(sessionID uint32) {
	s.Clear(&sessionID)
}
