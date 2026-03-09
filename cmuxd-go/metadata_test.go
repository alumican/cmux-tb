package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// startTestServer starts cmuxd-go HTTP server and returns its URL.
func startTestServer(t *testing.T) (*Server, *httptest.Server) {
	t.Helper()
	srv := NewServer()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.RawQuery, "mode=mux") {
			HandleMux(srv, w, r)
		} else {
			HandleLegacy(w, r)
		}
	}))
	t.Cleanup(ts.Close)
	return srv, ts
}

// connectMux connects a mux WebSocket client and returns the connection.
func connectMux(t *testing.T, ts *httptest.Server) *websocket.Conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(ts.URL, "http") + "/ws?mode=mux&cols=80&rows=24"
	conn, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	return conn
}

// readTextMessage reads a text message with a timeout.
func readTextMessage(t *testing.T, conn *websocket.Conn, timeout time.Duration) map[string]interface{} {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	for {
		msgType, data, err := conn.Read(ctx)
		if err != nil {
			t.Fatalf("read error: %v", err)
		}
		if msgType == websocket.MessageBinary {
			// Skip PTY output
			continue
		}
		var msg map[string]interface{}
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("unmarshal error: %v (data=%s)", err, string(data))
		}
		return msg
	}
}

// readTextMessageOfType reads text messages until it finds one of the given type.
func readTextMessageOfType(t *testing.T, conn *websocket.Conn, msgType string, timeout time.Duration) map[string]interface{} {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	for {
		mt, data, err := conn.Read(ctx)
		if err != nil {
			t.Fatalf("read error waiting for %q: %v", msgType, err)
		}
		if mt == websocket.MessageBinary {
			continue
		}
		var msg map[string]interface{}
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}
		if msg["type"] == msgType {
			return msg
		}
	}
}

// sendJSON sends a JSON message.
func sendJSON(t *testing.T, conn *websocket.Conn, msg interface{}) {
	t.Helper()
	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("marshal error: %v", err)
	}
	if err := conn.Write(context.Background(), websocket.MessageText, data); err != nil {
		t.Fatalf("write error: %v", err)
	}
}

// sendPtyInput sends binary PTY input to a session.
func sendPtyInput(t *testing.T, conn *websocket.Conn, sessionID uint32, data []byte) {
	t.Helper()
	buf := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(buf[:4], sessionID)
	copy(buf[4:], data)
	if err := conn.Write(context.Background(), websocket.MessageBinary, buf); err != nil {
		t.Fatalf("write error: %v", err)
	}
}

func TestWorkspaceSnapshotHasMetadata(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	// First message should be workspace_snapshot
	msg := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)

	ws := msg["workspace"].(map[string]interface{})
	groups := ws["groups"].(map[string]interface{})

	// Find the group and check the tab has a title
	for _, g := range groups {
		group := g.(map[string]interface{})
		tabs := group["tabs"].([]interface{})
		if len(tabs) == 0 {
			t.Fatal("no tabs in group")
		}
		tab := tabs[0].(map[string]interface{})
		title := tab["title"].(string)
		if title == "" {
			t.Error("tab title should not be empty")
		}
		// CWD should be present (set from HOME)
		if _, ok := tab["cwd"]; !ok {
			t.Log("cwd not in workspace tab (may be empty if HOME not set)")
		}
	}
}

func TestInitialSessionMetadata(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	// Read workspace_snapshot first
	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := snapshot["initialSessionId"].(float64)

	// Next should be session_metadata
	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	if meta["sessionId"].(float64) != sessionID {
		t.Errorf("session_metadata sessionId mismatch: got %v, want %v", meta["sessionId"], sessionID)
	}
	metadata := meta["metadata"].(map[string]interface{})
	if metadata["title"].(string) != "Terminal" {
		t.Errorf("expected title 'Terminal', got %q", metadata["title"])
	}
}

func TestUpdateMetadataSetStatus(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	// Read initial messages
	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Send update_metadata with setStatus
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"setStatus": map[string]interface{}{
			"key":   "git",
			"value": "main",
			"icon":  "branch",
			"color": "green",
		},
	})

	// Should receive session_metadata with the status
	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	status := metadata["status"].(map[string]interface{})
	gitStatus := status["git"].(map[string]interface{})
	if gitStatus["value"].(string) != "main" {
		t.Errorf("expected status value 'main', got %q", gitStatus["value"])
	}
}

func TestUpdateMetadataRemoveStatus(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set a status
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"setStatus": map[string]interface{}{
			"key":   "test",
			"value": "running",
		},
	})
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Wait for coalescing to finish
	time.Sleep(100 * time.Millisecond)

	// Remove the status
	sendJSON(t, conn, map[string]interface{}{
		"type":         "update_metadata",
		"sessionId":    sessionID,
		"removeStatus": "test",
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	if statusRaw, ok := metadata["status"]; ok && statusRaw != nil {
		status := statusRaw.(map[string]interface{})
		if _, ok := status["test"]; ok {
			t.Error("status 'test' should have been removed")
		}
	}
	// If status is absent/nil, that's also correct (empty map omitted)
}

func TestUpdateMetadataLog(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Add a log entry
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"log": map[string]interface{}{
			"message": "Build started",
			"level":   "info",
			"source":  "make",
		},
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	log := metadata["log"].([]interface{})
	if len(log) != 1 {
		t.Fatalf("expected 1 log entry, got %d", len(log))
	}
	entry := log[0].(map[string]interface{})
	if entry["message"].(string) != "Build started" {
		t.Errorf("unexpected log message: %q", entry["message"])
	}
}

func TestUpdateMetadataGit(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set git info
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"git": map[string]interface{}{
			"branch":  "feature/sidebar",
			"isDirty": true,
		},
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	git := metadata["git"].(map[string]interface{})
	if git["branch"].(string) != "feature/sidebar" {
		t.Errorf("expected branch 'feature/sidebar', got %q", git["branch"])
	}
	if git["isDirty"].(bool) != true {
		t.Error("expected isDirty=true")
	}
}

func TestUpdateMetadataProgress(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set progress
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"progress": map[string]interface{}{
			"value": 0.75,
			"label": "Building...",
		},
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	progress := metadata["progress"].(map[string]interface{})
	if progress["value"].(float64) != 0.75 {
		t.Errorf("expected progress 0.75, got %v", progress["value"])
	}
	if progress["label"].(string) != "Building..." {
		t.Errorf("expected label 'Building...', got %q", progress["label"])
	}
}

func TestUpdateMetadataClearProgress(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set then clear progress
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"progress": map[string]interface{}{
			"value": 0.5,
			"label": "test",
		},
	})
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	time.Sleep(100 * time.Millisecond)

	sendJSON(t, conn, map[string]interface{}{
		"type":          "update_metadata",
		"sessionId":     sessionID,
		"clearProgress": true,
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	if metadata["progress"] != nil {
		t.Error("progress should be nil after clear")
	}
}

func TestUpdateMetadataCWD(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set CWD via update_metadata
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"cwd":       "/tmp/test-dir",
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	if metadata["cwd"].(string) != "/tmp/test-dir" {
		t.Errorf("expected CWD '/tmp/test-dir', got %q", metadata["cwd"])
	}

	// Should also get a workspace_update with the new CWD
	wsUpdate := readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)
	ws := wsUpdate["workspace"].(map[string]interface{})
	groups := ws["groups"].(map[string]interface{})
	found := false
	for _, g := range groups {
		group := g.(map[string]interface{})
		tabs := group["tabs"].([]interface{})
		for _, tb := range tabs {
			tab := tb.(map[string]interface{})
			if tab["cwd"] == "/tmp/test-dir" {
				found = true
			}
		}
	}
	if !found {
		t.Error("workspace_update should include the updated CWD")
	}
}

func TestUpdateMetadataPorts(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"ports":     []int{3000, 8080},
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	ports := metadata["ports"].([]interface{})
	if len(ports) != 2 {
		t.Fatalf("expected 2 ports, got %d", len(ports))
	}
}

func TestSessionMetadataAfterAttach(t *testing.T) {
	_, ts := startTestServer(t)
	conn1 := connectMux(t, ts)

	// Get initial session ID from first client
	snapshot := readTextMessageOfType(t, conn1, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn1, "session_metadata", 5*time.Second)

	// Set some metadata on the session
	sendJSON(t, conn1, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"git": map[string]interface{}{
			"branch": "main",
		},
	})
	readTextMessageOfType(t, conn1, "session_metadata", 5*time.Second)

	// Connect second client
	conn2 := connectMux(t, ts)
	readTextMessageOfType(t, conn2, "workspace_snapshot", 5*time.Second)
	readTextMessageOfType(t, conn2, "session_metadata", 5*time.Second)

	// Wait for coalescing
	time.Sleep(100 * time.Millisecond)

	// Attach second client to first client's session
	sendJSON(t, conn2, map[string]interface{}{
		"type":      "attach_session",
		"sessionId": sessionID,
		"cols":      80,
		"rows":      24,
	})

	// Should receive session_attached then session_metadata
	readTextMessageOfType(t, conn2, "session_attached", 5*time.Second)
	meta := readTextMessageOfType(t, conn2, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	git := metadata["git"].(map[string]interface{})
	if git["branch"].(string) != "main" {
		t.Errorf("expected branch 'main' after attach, got %q", git["branch"])
	}
}

func TestWorkspaceJSONWithRealTitles(t *testing.T) {
	sessions := []SessionInfo{
		{ID: 1, Title: "vim", CWD: "/home/user"},
		{ID: 2, Title: "Terminal", CWD: "/tmp"},
	}
	result := BuildWorkspaceJSON(sessions)

	var ws map[string]interface{}
	if err := json.Unmarshal([]byte(result), &ws); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	groups := ws["groups"].(map[string]interface{})
	g1 := groups["g1"].(map[string]interface{})
	tabs1 := g1["tabs"].([]interface{})
	tab1 := tabs1[0].(map[string]interface{})
	if tab1["title"].(string) != "vim" {
		t.Errorf("expected title 'vim', got %q", tab1["title"])
	}
	if tab1["cwd"].(string) != "/home/user" {
		t.Errorf("expected cwd '/home/user', got %q", tab1["cwd"])
	}

	g2 := groups["g2"].(map[string]interface{})
	tabs2 := g2["tabs"].([]interface{})
	tab2 := tabs2[0].(map[string]interface{})
	if tab2["title"].(string) != "Terminal" {
		t.Errorf("expected title 'Terminal', got %q", tab2["title"])
	}
}

func TestWorkspaceJSONEscapesSpecialChars(t *testing.T) {
	sessions := []SessionInfo{
		{ID: 1, Title: `title "with" quotes`, CWD: `/path/with\backslash`},
	}
	result := BuildWorkspaceJSON(sessions)

	var ws map[string]interface{}
	if err := json.Unmarshal([]byte(result), &ws); err != nil {
		t.Fatalf("invalid JSON after escaping: %v\nraw: %s", err, result)
	}

	groups := ws["groups"].(map[string]interface{})
	g1 := groups["g1"].(map[string]interface{})
	tabs := g1["tabs"].([]interface{})
	tab := tabs[0].(map[string]interface{})
	if tab["title"].(string) != `title "with" quotes` {
		t.Errorf("title not properly escaped: %q", tab["title"])
	}
}

func TestLogEntryCapping(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Send 55 log entries (cap is 50)
	for i := 0; i < 55; i++ {
		sendJSON(t, conn, map[string]interface{}{
			"type":      "update_metadata",
			"sessionId": sessionID,
			"log": map[string]interface{}{
				"message": fmt.Sprintf("log-%d", i),
				"level":   "info",
			},
		})
	}

	// Wait for all to be processed + coalescing
	time.Sleep(200 * time.Millisecond)

	// Read the last session_metadata
	var lastMeta map[string]interface{}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for {
		mt, data, err := conn.Read(ctx)
		if err != nil {
			break
		}
		if mt == websocket.MessageBinary {
			continue
		}
		var msg map[string]interface{}
		json.Unmarshal(data, &msg)
		if msg["type"] == "session_metadata" {
			lastMeta = msg
		}
	}

	if lastMeta == nil {
		t.Fatal("never received session_metadata")
	}
	metadata := lastMeta["metadata"].(map[string]interface{})
	log := metadata["log"].([]interface{})
	if len(log) > maxLogEntries {
		t.Errorf("log should be capped at %d, got %d", maxLogEntries, len(log))
	}
	// The oldest entries should have been trimmed
	firstEntry := log[0].(map[string]interface{})
	if firstEntry["message"].(string) == "log-0" {
		t.Error("oldest log entry should have been trimmed")
	}
}

func TestUpdateMetadataInvalidSession(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Send update for non-existent session - should not crash
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": 9999,
		"cwd":       "/invalid",
	})

	// If we can still communicate, the server didn't crash
	sendJSON(t, conn, map[string]interface{}{
		"type": "create_session",
		"cols": 80,
		"rows": 24,
	})
	msg := readTextMessageOfType(t, conn, "session_created", 5*time.Second)
	if msg["type"] != "session_created" {
		t.Error("server should still be responsive after invalid session update")
	}
}

func TestUpdateMetadataDescription(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set description
	sendJSON(t, conn, map[string]interface{}{
		"type":        "update_metadata",
		"sessionId":   sessionID,
		"description": "Running build for project-x",
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	if metadata["description"].(string) != "Running build for project-x" {
		t.Errorf("expected description 'Running build for project-x', got %q", metadata["description"])
	}

	// Should appear in workspace_update
	wsUpdate := readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)
	ws := wsUpdate["workspace"].(map[string]interface{})
	groups := ws["groups"].(map[string]interface{})
	found := false
	for _, g := range groups {
		group := g.(map[string]interface{})
		tabs := group["tabs"].([]interface{})
		for _, tb := range tabs {
			tab := tb.(map[string]interface{})
			if desc, ok := tab["description"]; ok && desc == "Running build for project-x" {
				found = true
			}
		}
	}
	if !found {
		t.Error("workspace_update should include the description")
	}
}

func TestClearDescription(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set then clear description
	sendJSON(t, conn, map[string]interface{}{
		"type":        "update_metadata",
		"sessionId":   sessionID,
		"description": "something",
	})
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	// Drain workspace_update
	readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)

	time.Sleep(100 * time.Millisecond)

	// Clear by setting to empty string
	sendJSON(t, conn, map[string]interface{}{
		"type":        "update_metadata",
		"sessionId":   sessionID,
		"description": "",
	})

	meta := readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	metadata := meta["metadata"].(map[string]interface{})
	if desc, ok := metadata["description"]; ok && desc != nil && desc != "" {
		t.Errorf("description should be empty after clear, got %q", desc)
	}
}

func TestWorkspaceJSONBranchAndDir(t *testing.T) {
	sessions := []SessionInfo{
		{ID: 1, Title: "vim", CWD: "/home/user/project", Branch: "main", IsDirty: false},
		{ID: 2, Title: "Terminal", CWD: "/tmp/build", Branch: "feature/x", IsDirty: true},
	}
	result := BuildWorkspaceJSON(sessions)

	var ws map[string]interface{}
	if err := json.Unmarshal([]byte(result), &ws); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	groups := ws["groups"].(map[string]interface{})

	// Check session 1
	g1 := groups["g1"].(map[string]interface{})
	tab1 := g1["tabs"].([]interface{})[0].(map[string]interface{})
	if tab1["branch"].(string) != "main" {
		t.Errorf("expected branch 'main', got %q", tab1["branch"])
	}
	if _, ok := tab1["isDirty"]; ok {
		t.Error("isDirty should not be present when false")
	}
	if tab1["dir"].(string) != "project" {
		t.Errorf("expected dir 'project', got %q", tab1["dir"])
	}
	if tab1["cwd"].(string) != "/home/user/project" {
		t.Errorf("expected cwd '/home/user/project', got %q", tab1["cwd"])
	}

	// Check session 2
	g2 := groups["g2"].(map[string]interface{})
	tab2 := g2["tabs"].([]interface{})[0].(map[string]interface{})
	if tab2["branch"].(string) != "feature/x" {
		t.Errorf("expected branch 'feature/x', got %q", tab2["branch"])
	}
	if tab2["isDirty"].(bool) != true {
		t.Error("expected isDirty=true")
	}
	if tab2["dir"].(string) != "build" {
		t.Errorf("expected dir 'build', got %q", tab2["dir"])
	}
}

func TestWorkspaceJSONDescription(t *testing.T) {
	sessions := []SessionInfo{
		{ID: 1, Title: "vim", Description: "editing config", CWD: "/home/user"},
	}
	result := BuildWorkspaceJSON(sessions)

	var ws map[string]interface{}
	if err := json.Unmarshal([]byte(result), &ws); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	groups := ws["groups"].(map[string]interface{})
	g1 := groups["g1"].(map[string]interface{})
	tab := g1["tabs"].([]interface{})[0].(map[string]interface{})
	if tab["description"].(string) != "editing config" {
		t.Errorf("expected description 'editing config', got %q", tab["description"])
	}
}

func TestGitBranchInWorkspaceUpdateE2E(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set git branch
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"git": map[string]interface{}{
			"branch":  "develop",
			"isDirty": true,
		},
	})

	// Should get session_metadata AND workspace_update
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	wsUpdate := readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)
	ws := wsUpdate["workspace"].(map[string]interface{})
	groups := ws["groups"].(map[string]interface{})

	found := false
	for _, g := range groups {
		group := g.(map[string]interface{})
		tabs := group["tabs"].([]interface{})
		for _, tb := range tabs {
			tab := tb.(map[string]interface{})
			if branch, ok := tab["branch"]; ok && branch == "develop" {
				found = true
				if tab["isDirty"].(bool) != true {
					t.Error("expected isDirty=true in workspace tab")
				}
			}
		}
	}
	if !found {
		t.Error("workspace_update should include branch 'develop'")
	}
}

func TestDirInWorkspaceUpdateE2E(t *testing.T) {
	_, ts := startTestServer(t)
	conn := connectMux(t, ts)

	snapshot := readTextMessageOfType(t, conn, "workspace_snapshot", 5*time.Second)
	sessionID := uint32(snapshot["initialSessionId"].(float64))
	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)

	// Set CWD
	sendJSON(t, conn, map[string]interface{}{
		"type":      "update_metadata",
		"sessionId": sessionID,
		"cwd":       "/Users/test/my-project",
	})

	readTextMessageOfType(t, conn, "session_metadata", 5*time.Second)
	wsUpdate := readTextMessageOfType(t, conn, "workspace_update", 5*time.Second)
	ws := wsUpdate["workspace"].(map[string]interface{})
	groups := ws["groups"].(map[string]interface{})

	found := false
	for _, g := range groups {
		group := g.(map[string]interface{})
		tabs := group["tabs"].([]interface{})
		for _, tb := range tabs {
			tab := tb.(map[string]interface{})
			if dir, ok := tab["dir"]; ok && dir == "my-project" {
				found = true
			}
		}
	}
	if !found {
		t.Error("workspace_update should include dir 'my-project' (basename of CWD)")
	}
}
