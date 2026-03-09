package main

import (
	"net/url"
	"strings"
)

// OscEvent represents a parsed OSC escape sequence.
type OscEvent struct {
	Code int    // OSC code (0, 2, 7, etc.)
	Data string // payload string
}

// OscParser is a streaming state-machine parser for OSC sequences.
// It extracts OSC 0/2 (title) and OSC 7 (CWD) from PTY output.
// Handles sequences split across read boundaries.
type OscParser struct {
	state    oscState
	paramBuf [16]byte
	paramLen int
	dataBuf  [4096]byte
	dataLen  int
}

type oscState int

const (
	oscNormal oscState = iota
	oscEsc             // saw ESC (0x1B)
	oscParam           // reading OSC code digits
	oscData            // reading OSC string data
	oscST              // saw ESC inside data, expecting '\'
)

// Feed processes raw PTY output and returns any completed OSC events.
// Does not modify the input data.
func (p *OscParser) Feed(data []byte) []OscEvent {
	var events []OscEvent
	for _, b := range data {
		switch p.state {
		case oscNormal:
			if b == 0x1B {
				p.state = oscEsc
			}
		case oscEsc:
			if b == ']' {
				p.state = oscParam
				p.paramLen = 0
				p.dataLen = 0
			} else {
				p.state = oscNormal
			}
		case oscParam:
			if b == ';' {
				p.state = oscData
			} else if b >= '0' && b <= '9' {
				if p.paramLen < len(p.paramBuf) {
					p.paramBuf[p.paramLen] = b
					p.paramLen++
				}
			} else {
				// Malformed, reset
				p.state = oscNormal
			}
		case oscData:
			if b == 0x07 { // BEL terminator
				if ev, ok := p.emit(); ok {
					events = append(events, ev)
				}
				p.state = oscNormal
			} else if b == 0x1B {
				p.state = oscST // possible ST (ESC \)
			} else {
				if p.dataLen < len(p.dataBuf) {
					p.dataBuf[p.dataLen] = b
					p.dataLen++
				}
			}
		case oscST:
			if b == '\\' {
				// ST terminator
				if ev, ok := p.emit(); ok {
					events = append(events, ev)
				}
				p.state = oscNormal
			} else {
				// Not ST, store the ESC we skipped and continue in data
				if p.dataLen < len(p.dataBuf) {
					p.dataBuf[p.dataLen] = 0x1B
					p.dataLen++
				}
				if b == 0x07 {
					if ev, ok := p.emit(); ok {
						events = append(events, ev)
					}
					p.state = oscNormal
				} else {
					if p.dataLen < len(p.dataBuf) {
						p.dataBuf[p.dataLen] = b
						p.dataLen++
					}
					p.state = oscData
				}
			}
		}
	}
	return events
}

func (p *OscParser) emit() (OscEvent, bool) {
	code := parseOscCode(p.paramBuf[:p.paramLen])
	// Only emit for codes we care about
	switch code {
	case 0, 2, 7:
		return OscEvent{
			Code: code,
			Data: string(p.dataBuf[:p.dataLen]),
		}, true
	}
	return OscEvent{}, false
}

func parseOscCode(buf []byte) int {
	if len(buf) == 0 {
		return -1
	}
	code := 0
	for _, b := range buf {
		code = code*10 + int(b-'0')
	}
	return code
}

// ParseOsc7Path extracts the path from an OSC 7 URI (file://hostname/path).
func ParseOsc7Path(data string) string {
	if !strings.HasPrefix(data, "file://") {
		return ""
	}
	u, err := url.Parse(data)
	if err != nil {
		// Fallback: extract path from file://hostname/path
		rest := data[len("file://"):]
		if slashIdx := strings.Index(rest, "/"); slashIdx >= 0 {
			return rest[slashIdx:]
		}
		return ""
	}
	if u.Path != "" {
		decoded, err := url.PathUnescape(u.Path)
		if err != nil {
			return u.Path
		}
		return decoded
	}
	return ""
}
