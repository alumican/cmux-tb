package main

import (
	"testing"
	"time"
)

func TestNotificationStoreAdd(t *testing.T) {
	store := NewNotificationStore()
	n := store.Add(1, "Build Failed", "Error in main.go", "line 42: syntax error")
	if n.ID == 0 {
		t.Error("notification should have a non-zero ID")
	}
	if n.SessionID != 1 {
		t.Errorf("expected sessionId 1, got %d", n.SessionID)
	}
	if n.Title != "Build Failed" {
		t.Errorf("expected title 'Build Failed', got %q", n.Title)
	}
	if n.IsRead {
		t.Error("new notification should not be read")
	}
	if n.CreatedAt == 0 {
		t.Error("createdAt should be set")
	}
}

func TestNotificationStoreMarkRead(t *testing.T) {
	store := NewNotificationStore()
	n := store.Add(1, "Test", "", "")
	result := store.MarkRead(n.ID)
	if result == nil {
		t.Fatal("MarkRead should return the notification")
	}
	if !result.IsRead {
		t.Error("notification should be marked as read")
	}

	// Mark non-existent
	result = store.MarkRead(9999)
	if result != nil {
		t.Error("MarkRead of non-existent should return nil")
	}
}

func TestNotificationStoreMarkAllReadForSession(t *testing.T) {
	store := NewNotificationStore()
	store.Add(1, "A", "", "")
	store.Add(1, "B", "", "")
	store.Add(2, "C", "", "")

	marked := store.MarkAllReadForSession(1)
	if len(marked) != 2 {
		t.Fatalf("expected 2 marked, got %d", len(marked))
	}

	// Session 2's notification should still be unread
	if store.UnreadCount(nil) != 1 {
		t.Errorf("expected 1 unread total, got %d", store.UnreadCount(nil))
	}
}

func TestNotificationStoreClear(t *testing.T) {
	store := NewNotificationStore()
	store.Add(1, "A", "", "")
	store.Add(2, "B", "", "")

	// Clear for session 1 only
	sid := uint32(1)
	count := store.Clear(&sid)
	if count != 1 {
		t.Errorf("expected 1 cleared, got %d", count)
	}

	all := store.List(nil)
	if len(all) != 1 {
		t.Fatalf("expected 1 remaining, got %d", len(all))
	}
	if all[0].Title != "B" {
		t.Errorf("expected remaining notification 'B', got %q", all[0].Title)
	}

	// Clear all
	count = store.Clear(nil)
	if count != 1 {
		t.Errorf("expected 1 cleared, got %d", count)
	}
	if len(store.List(nil)) != 0 {
		t.Error("store should be empty after clear all")
	}
}

func TestNotificationStoreMaxCap(t *testing.T) {
	store := NewNotificationStore()
	for i := 0; i < maxNotifications+10; i++ {
		store.Add(1, "n", "", "")
	}
	all := store.List(nil)
	if len(all) > maxNotifications {
		t.Errorf("expected at most %d notifications, got %d", maxNotifications, len(all))
	}
}

func TestNotificationStoreUnreadCount(t *testing.T) {
	store := NewNotificationStore()
	store.Add(1, "A", "", "")
	store.Add(1, "B", "", "")
	store.Add(2, "C", "", "")

	if store.UnreadCount(nil) != 3 {
		t.Errorf("expected 3 unread, got %d", store.UnreadCount(nil))
	}

	sid := uint32(1)
	if store.UnreadCount(&sid) != 2 {
		t.Errorf("expected 2 unread for session 1, got %d", store.UnreadCount(&sid))
	}
}

// --- E2E WebSocket tests ---

func TestNotifyCreatesNotification(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Send notify
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "Build Complete",
		"subtitle":  "project-x",
		"body":      "All tests passed",
	})

	// Should receive notification broadcast
	msg := readTextMessageOfType(t, conn, "notification", 5*time.Second)
	n := msg["notification"].(map[string]interface{})
	if n["title"].(string) != "Build Complete" {
		t.Errorf("expected title 'Build Complete', got %q", n["title"])
	}
	if n["subtitle"].(string) != "project-x" {
		t.Errorf("expected subtitle 'project-x', got %q", n["subtitle"])
	}
	if n["body"].(string) != "All tests passed" {
		t.Errorf("expected body 'All tests passed', got %q", n["body"])
	}
	if n["isRead"].(bool) != false {
		t.Error("new notification should not be read")
	}
	if n["sessionId"].(float64) != float64(sessionID) {
		t.Errorf("expected sessionId %d, got %v", sessionID, n["sessionId"])
	}
}

func TestMarkNotificationRead(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Create a notification
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "Alert",
	})
	nMsg := readTextMessageOfType(t, conn, "notification", 5*time.Second)
	notifID := nMsg["notification"].(map[string]interface{})["id"].(float64)

	// Mark it as read
	sendJSON(t, conn, map[string]interface{}{
		"type":           "mark_notification_read",
		"notificationId": uint64(notifID),
	})

	readMsg := readTextMessageOfType(t, conn, "notification_read", 5*time.Second)
	if readMsg["notificationId"].(float64) != notifID {
		t.Errorf("expected notificationId %v, got %v", notifID, readMsg["notificationId"])
	}
}

func TestMarkAllNotificationsReadForSession(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Create two notifications
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "N1",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "N2",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	// Mark all for session
	sendJSON(t, conn, map[string]interface{}{
		"type":      "mark_notification_read",
		"sessionId": sessionID,
	})

	// Should receive two notification_read messages
	readTextMessageOfType(t, conn, "notification_read", 5*time.Second)
	readTextMessageOfType(t, conn, "notification_read", 5*time.Second)
}

func TestClearNotifications(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Create notifications
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "N1",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "N2",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	// Clear all
	sendJSON(t, conn, map[string]interface{}{
		"type": "clear_notifications",
	})

	cleared := readTextMessageOfType(t, conn, "notifications_cleared", 5*time.Second)
	if cleared["count"].(float64) != 2 {
		t.Errorf("expected count 2, got %v", cleared["count"])
	}
}

func TestClearNotificationsForSession(t *testing.T) {
	srv, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Create a second session
	sendJSON(t, conn, map[string]interface{}{
		"type": "create_session",
		"cols": 80,
		"rows": 24,
	})
	created := readTextMessageOfType(t, conn, "session_created", 5*time.Second)
	session2ID := uint32(created["sessionId"].(float64))
	// Drain session_metadata and workspace_update
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)

	// Add notifications for both sessions
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "Session1 notif",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": session2ID,
		"title":     "Session2 notif",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	// Clear only session 1
	sendJSON(t, conn, map[string]interface{}{
		"type":      "clear_notifications",
		"sessionId": sessionID,
	})

	cleared := readTextMessageOfType(t, conn, "notifications_cleared", 5*time.Second)
	if cleared["count"].(float64) != 1 {
		t.Errorf("expected count 1, got %v", cleared["count"])
	}

	// Session 2's notification should still exist
	remaining := srv.notifications.List(nil)
	if len(remaining) != 1 {
		t.Fatalf("expected 1 remaining notification, got %d", len(remaining))
	}
	if remaining[0].Title != "Session2 notif" {
		t.Errorf("expected remaining 'Session2 notif', got %q", remaining[0].Title)
	}
}

func TestNotificationsListOnConnect(t *testing.T) {
	_, ts := startTestServer(t)

	// Connect first client and create a notification
	conn1 := connectMux(t, ts)
	snapshot := readTextMessageOfType(t, conn1, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn1, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn1, "notifications_list", 5*time.Second)

	sendJSON(t, conn1, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "Existing Notification",
	})
	readTextMessageOfType(t, conn1, "notification", 5*time.Second)

	// Connect second client - should receive notifications_list with existing notification
	conn2 := connectMux(t, ts)
	readTextMessageOfType(t, conn2, "workspace_snapshot", 5*time.Second)
	readTextMessageOfType(t, conn2, "session_metadata", 5*time.Second)
	nList := readTextMessageOfType(t, conn2, "notifications_list", 5*time.Second)

	notifications := nList["notifications"].([]interface{})
	if len(notifications) < 1 {
		t.Fatal("second client should receive existing notifications")
	}
	found := false
	for _, n := range notifications {
		notif := n.(map[string]interface{})
		if notif["title"].(string) == "Existing Notification" {
			found = true
			break
		}
	}
	if !found {
		t.Error("should find 'Existing Notification' in notifications list")
	}
}

func TestNotifyInvalidSession(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Notify for non-existent session - should not crash
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": 9999,
		"title":     "Bad",
	})

	// Server should still respond to other messages
	sendJSON(t, conn, map[string]interface{}{
		"type": "create_session",
		"cols": 80,
		"rows": 24,
	})
	msg := readTextMessageOfType(t, conn, "session_created", 5*time.Second)
	if msg["type"] != "session_created" {
		t.Error("server should still be responsive")
	}
}

func TestDestroySessionClearsNotifications(t *testing.T) {
	srv, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "notifications_list", 5*time.Second)

	// Create a second session (so destroying session 1 doesn't close connection)
	sendJSON(t, conn, map[string]interface{}{
		"type": "create_session",
		"cols": 80,
		"rows": 24,
	})
	readTextMessageOfType(t, conn, "session_created", 5*time.Second)
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)

	// Add notification for session 1
	sendJSON(t, conn, map[string]interface{}{
		"type":      "notify",
		"sessionId": sessionID,
		"title":     "Will be cleaned",
	})
	readTextMessageOfType(t, conn, "notification", 5*time.Second)

	// Destroy session 1
	sendJSON(t, conn, map[string]interface{}{
		"type":      "destroy_session",
		"sessionId": sessionID,
	})
	readTextMessageOfType(t, conn, "session_destroyed", 5*time.Second)

	// Notifications for session 1 should be cleaned up
	remaining := srv.notifications.List(nil)
	for _, n := range remaining {
		if n.SessionID == sessionID {
			t.Error("notifications for destroyed session should be cleaned up")
		}
	}
}
