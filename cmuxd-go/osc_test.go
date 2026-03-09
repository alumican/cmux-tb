package main

import (
	"fmt"
	"testing"
)

func TestOscParserTitle(t *testing.T) {
	p := &OscParser{}
	// OSC 0 ; title BEL
	data := []byte("\x1b]0;my-title\x07")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Code != 0 {
		t.Errorf("expected code 0, got %d", events[0].Code)
	}
	if events[0].Data != "my-title" {
		t.Errorf("expected 'my-title', got %q", events[0].Data)
	}
}

func TestOscParserTitleOsc2(t *testing.T) {
	p := &OscParser{}
	// OSC 2 ; title BEL
	data := []byte("\x1b]2;window title\x07")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Code != 2 {
		t.Errorf("expected code 2, got %d", events[0].Code)
	}
	if events[0].Data != "window title" {
		t.Errorf("expected 'window title', got %q", events[0].Data)
	}
}

func TestOscParserCWD(t *testing.T) {
	p := &OscParser{}
	// OSC 7 ; file://hostname/path/to/dir BEL
	data := []byte("\x1b]7;file://myhost/Users/test/project\x07")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Code != 7 {
		t.Errorf("expected code 7, got %d", events[0].Code)
	}
	if events[0].Data != "file://myhost/Users/test/project" {
		t.Errorf("unexpected data: %q", events[0].Data)
	}
}

func TestOscParserSTTerminator(t *testing.T) {
	p := &OscParser{}
	// OSC 0 ; title ST (ESC \)
	data := []byte("\x1b]0;st-title\x1b\\")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Data != "st-title" {
		t.Errorf("expected 'st-title', got %q", events[0].Data)
	}
}

func TestOscParserSplitAcrossReads(t *testing.T) {
	p := &OscParser{}

	// Split the sequence across multiple reads
	events := p.Feed([]byte("\x1b]"))
	if len(events) != 0 {
		t.Fatalf("expected 0 events after first chunk, got %d", len(events))
	}

	events = p.Feed([]byte("0;hel"))
	if len(events) != 0 {
		t.Fatalf("expected 0 events after second chunk, got %d", len(events))
	}

	events = p.Feed([]byte("lo\x07"))
	if len(events) != 1 {
		t.Fatalf("expected 1 event after third chunk, got %d", len(events))
	}
	if events[0].Data != "hello" {
		t.Errorf("expected 'hello', got %q", events[0].Data)
	}
}

func TestOscParserSplitSTAcrossReads(t *testing.T) {
	p := &OscParser{}

	// Split the ST terminator across reads
	events := p.Feed([]byte("\x1b]0;data\x1b"))
	if len(events) != 0 {
		t.Fatalf("expected 0 events, got %d", len(events))
	}

	events = p.Feed([]byte("\\"))
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Data != "data" {
		t.Errorf("expected 'data', got %q", events[0].Data)
	}
}

func TestOscParserMultipleEvents(t *testing.T) {
	p := &OscParser{}
	data := []byte("\x1b]0;title1\x07some text\x1b]7;file://host/tmp\x07more text")
	events := p.Feed(data)
	if len(events) != 2 {
		t.Fatalf("expected 2 events, got %d", len(events))
	}
	if events[0].Code != 0 || events[0].Data != "title1" {
		t.Errorf("event 0: code=%d data=%q", events[0].Code, events[0].Data)
	}
	if events[1].Code != 7 || events[1].Data != "file://host/tmp" {
		t.Errorf("event 1: code=%d data=%q", events[1].Code, events[1].Data)
	}
}

func TestOscParserIgnoresUnknownCodes(t *testing.T) {
	p := &OscParser{}
	// OSC 133 is shell integration, should be ignored
	data := []byte("\x1b]133;A\x07\x1b]0;keep\x07")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event (ignoring OSC 133), got %d", len(events))
	}
	if events[0].Code != 0 || events[0].Data != "keep" {
		t.Errorf("unexpected event: code=%d data=%q", events[0].Code, events[0].Data)
	}
}

func TestOscParserInterleaved(t *testing.T) {
	p := &OscParser{}
	// Normal text interleaved with OSC sequences
	data := []byte("Hello\x1b]0;title\x07World\x1b]7;file://h/dir\x07End")
	events := p.Feed(data)
	if len(events) != 2 {
		t.Fatalf("expected 2 events, got %d", len(events))
	}
}

func TestOscParserEmptyData(t *testing.T) {
	p := &OscParser{}
	events := p.Feed([]byte{})
	if len(events) != 0 {
		t.Fatalf("expected 0 events, got %d", len(events))
	}
}

func TestOscParserMalformedReset(t *testing.T) {
	p := &OscParser{}
	// ESC followed by non-] should reset
	data := []byte("\x1b[H\x1b]0;good\x07")
	events := p.Feed(data)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Data != "good" {
		t.Errorf("expected 'good', got %q", events[0].Data)
	}
}

func TestParseOsc7Path(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"file://hostname/Users/test/project", "/Users/test/project"},
		{"file://localhost/tmp", "/tmp"},
		{"file:///home/user", "/home/user"},
		{"file://host/path%20with%20spaces", "/path with spaces"},
		{"", ""},
		{"garbage", ""},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("%q", tt.input), func(t *testing.T) {
			got := ParseOsc7Path(tt.input)
			if got != tt.expected {
				t.Errorf("ParseOsc7Path(%q) = %q, want %q", tt.input, got, tt.expected)
			}
		})
	}
}
