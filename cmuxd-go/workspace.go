package main

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
)

// SessionInfo holds the metadata needed to build workspace JSON.
type SessionInfo struct {
	ID          uint32
	Title       string
	Description string
	CWD         string
	Branch      string
	IsDirty     bool
}

// Dir returns the basename of CWD.
func (s SessionInfo) Dir() string {
	if s.CWD == "" {
		return ""
	}
	return filepath.Base(s.CWD)
}

// escapeJSONString escapes a string for embedding in JSON.
func escapeJSONString(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r < 0x20 {
				b.WriteString(fmt.Sprintf(`\u%04x`, r))
			} else {
				b.WriteRune(r)
			}
		}
	}
	return b.String()
}

// writeTabJSON writes a single tab JSON object to the builder.
func writeTabJSON(b *strings.Builder, s SessionInfo) {
	title := escapeJSONString(s.Title)
	b.WriteString(fmt.Sprintf(`{"id":"t%d","title":"%s","type":"terminal","sessionId":%d`, s.ID, title, s.ID))
	if s.Description != "" {
		b.WriteString(fmt.Sprintf(`,"description":"%s"`, escapeJSONString(s.Description)))
	}
	if s.CWD != "" {
		b.WriteString(fmt.Sprintf(`,"cwd":"%s"`, escapeJSONString(s.CWD)))
	}
	if dir := s.Dir(); dir != "" {
		b.WriteString(fmt.Sprintf(`,"dir":"%s"`, escapeJSONString(dir)))
	}
	if s.Branch != "" {
		b.WriteString(fmt.Sprintf(`,"branch":"%s"`, escapeJSONString(s.Branch)))
		if s.IsDirty {
			b.WriteString(`,"isDirty":true`)
		}
	}
	b.WriteByte('}')
}

// BuildWorkspaceJSON builds the workspace JSON tree from session info.
// Matches the Zig implementation's balanced binary tree format.
func BuildWorkspaceJSON(sessions []SessionInfo) string {
	sort.Slice(sessions, func(i, j int) bool { return sessions[i].ID < sessions[j].ID })

	var b strings.Builder

	if len(sessions) == 0 {
		b.WriteString(`{"root":{"type":"leaf","id":"g0"},`)
		b.WriteString(`"groups":{"g0":{"id":"g0","tabs":[],"activeTabId":""}},`)
		b.WriteString(`"focusedGroupId":"g0"}`)
		return b.String()
	}

	if len(sessions) == 1 {
		s := sessions[0]
		b.WriteString(fmt.Sprintf(`{"root":{"type":"leaf","id":"g%d"},`, s.ID))
		b.WriteString(fmt.Sprintf(`"groups":{"g%d":{"id":"g%d","tabs":[`, s.ID, s.ID))
		writeTabJSON(&b, s)
		b.WriteString(fmt.Sprintf(`],"activeTabId":"t%d"}},`, s.ID))
		b.WriteString(fmt.Sprintf(`"focusedGroupId":"g%d"}`, s.ID))
		return b.String()
	}

	// Multiple sessions: balanced binary tree of horizontal splits
	ids := make([]uint32, len(sessions))
	for i, s := range sessions {
		ids[i] = s.ID
	}

	b.WriteString(`{"root":`)
	buildTreeJSON(&b, ids, 0)
	b.WriteString(`,"groups":{`)
	for i, s := range sessions {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(fmt.Sprintf(`"g%d":{"id":"g%d","tabs":[`, s.ID, s.ID))
		writeTabJSON(&b, s)
		b.WriteString(fmt.Sprintf(`],"activeTabId":"t%d"}`, s.ID))
	}
	b.WriteString(fmt.Sprintf(`},"focusedGroupId":"g%d"}`, sessions[0].ID))
	return b.String()
}

func buildTreeJSON(b *strings.Builder, ids []uint32, splitID uint32) {
	if len(ids) == 1 {
		b.WriteString(fmt.Sprintf(`{"type":"leaf","id":"g%d"}`, ids[0]))
		return
	}
	mid := len(ids) / 2
	b.WriteString(fmt.Sprintf(`{"type":"split","id":"s%d","direction":"horizontal","ratio":0.5,"left":`, splitID))
	buildTreeJSON(b, ids[:mid], splitID*2+1)
	b.WriteString(`,"right":`)
	buildTreeJSON(b, ids[mid:], splitID*2+2)
	b.WriteByte('}')
}
