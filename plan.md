# cmuxd: Shared Terminal Backend

## Overview

cmuxd is a Zig daemon that manages PTY sessions, workspace state, and multi-client synchronization. It replaces the standalone `pty-server.mjs` and becomes the single backend for all cmux frontends: web (Next.js), native macOS (GhosttyKit), and future mobile (iOS).

**Core principle**: cmuxd is the source of truth for terminal sessions and workspace layout. Frontends are thin renderers that connect via WebSocket, receive state, and send user intents.

## Architecture

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Web Client  │  │ Native App  │  │ Mobile App  │
│ (ghostty-web)│  │(GhosttyKit) │  │(GhosttyKit) │
└──────┬───────┘  └──────┬──────┘  └──────┬──────┘
       │ ws://           │ ws://           │ ws://
       └────────┬────────┴────────┬───────┘
                │                 │
         ┌──────▼─────────────────▼──────┐
         │           cmuxd (Zig)          │
         │                                │
         │  ┌──────────┐ ┌────────────┐   │
         │  │ Workspace │ │  Session    │   │
         │  │  Manager  │ │  Manager   │   │
         │  │(tabs/splits)│(PTY+VT state)│  │
         │  └──────────┘ └────────────┘   │
         │  ┌──────────┐ ┌────────────┐   │
         │  │  Client   │ │ libghostty │   │
         │  │  Manager  │ │    -vt     │   │
         │  │(auth/sync)│ │(VT parser) │   │
         │  └──────────┘ └────────────┘   │
         └───────────┬────────────────────┘
                     │ PTY
              ┌──────▼──────┐
              │  /bin/zsh   │
              │  (per sess) │
              └─────────────┘
```

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | Zig | Links libghostty-vt directly, shares Ghostty's PTY code, same toolchain |
| Transport | WebSocket (single conn per client) | Browser-native, works from HTTPS pages to ws://localhost |
| Session persistence | Always (tmux-like) | Sessions survive frontend disconnects |
| Workspace state | Server-side (cmuxd) | All clients see same tabs/splits layout |
| Mutation model | CRDT-style | Clients apply optimistically, cmuxd is arbiter, broadcasts authoritative state |
| Multi-client resize | Smallest client wins | Simple, proven (tmux model) |
| Input model | Configurable per-session | Default: all clients can type. Sessions can be locked to single-driver mode |
| VT parsing | Server-side via libghostty-vt | Enables clean snapshots on session attach |
| Attach strategy | VT escape sequence dump | Server reconstructs screen as VT sequences, client processes like normal output |
| Data model | Shared JSON schema | Language-agnostic contract between cmuxd and all frontends |
| Initial sync | Full snapshot + event stream | Client gets workspace snapshot on connect, then delta events to stay in sync |
| Reconnection | Auto-reconnect | Frontend detects disconnect, retries, re-syncs on reconnect |
| State persistence | In-memory only | Workspace dies with process. PTYs die anyway, restoring layout without them is confusing |
| Native app integration | Deferred, designed for | Native app keeps GhosttyKit PTY locally for now. Architecture supports future Kind.remote termio backend |
| TLS | Deferred | Plain WebSocket for v1. Browsers allow ws://localhost from HTTPS pages. Reverse proxy for remote later |
| Distribution | npm postinstall | Downloads platform-specific binary from GitHub releases (like esbuild) |
| Web UI hosting | Next.js serves /terminal | cmuxd is WebSocket-only. The existing Next.js app at cmux.dev/terminal connects to ws://localhost |

## WebSocket Protocol

### Connection

```
Client connects: ws://localhost:3778
Auth: ?token=<random-token> query param (printed by `cmux server` on startup)
```

### Frame Types

WebSocket's native text/binary frame distinction is used for multiplexing:

| WS Frame Type | Purpose | Format |
|---------------|---------|--------|
| Text | Control messages | JSON `{ "type": "...", ... }` |
| Binary | Terminal data | `[4-byte session-id][raw PTY bytes]` |

### Control Messages (Client → Server)

```jsonc
// Session management
{ "type": "create_session", "id": "req-1", "cmd": "/bin/zsh", "cwd": "/home/user", "env": {} }
{ "type": "destroy_session", "id": "req-2", "sessionId": "sess-abc" }
{ "type": "attach_session", "id": "req-3", "sessionId": "sess-abc" }
{ "type": "detach_session", "id": "req-4", "sessionId": "sess-abc" }

// Session I/O
{ "type": "resize", "sessionId": "sess-abc", "cols": 120, "rows": 40 }
// Input: sent as binary frame [session-id][raw-bytes] for efficiency

// Workspace mutations (CRDT intents)
{ "type": "workspace_intent", "id": "req-5", "action": "add_tab" }
{ "type": "workspace_intent", "id": "req-6", "action": "close_tab", "groupId": "g1", "tabId": "t1" }
{ "type": "workspace_intent", "id": "req-7", "action": "split_pane", "groupId": "g1", "direction": "right" }
{ "type": "workspace_intent", "id": "req-8", "action": "select_tab", "groupId": "g1", "tabId": "t2" }
{ "type": "workspace_intent", "id": "req-9", "action": "focus_group", "groupId": "g2" }
{ "type": "workspace_intent", "id": "req-10", "action": "resize_split", "splitId": "s1", "ratio": 0.6 }

// Multiplayer
{ "type": "set_session_mode", "sessionId": "sess-abc", "mode": "shared" | "single_driver" }
{ "type": "request_driver", "sessionId": "sess-abc" }
{ "type": "release_driver", "sessionId": "sess-abc" }
```

### Control Messages (Server → Client)

```jsonc
// Initial sync (sent immediately after auth)
{ "type": "workspace_snapshot", "workspace": { /* full workspace JSON */ }, "sessions": [...] }

// Workspace deltas (broadcast to all clients)
{ "type": "workspace_update", "workspace": { /* full workspace JSON */ } }

// Session lifecycle
{ "type": "session_created", "sessionId": "sess-abc", "cols": 80, "rows": 24 }
{ "type": "session_destroyed", "sessionId": "sess-abc" }
{ "type": "session_attached", "sessionId": "sess-abc" }
// VT snapshot follows as binary frame immediately after attach

// Resize notifications
{ "type": "session_resized", "sessionId": "sess-abc", "cols": 80, "rows": 24 }

// Multiplayer
{ "type": "client_joined", "clientId": "c-2", "name": "..." }
{ "type": "client_left", "clientId": "c-2" }
{ "type": "driver_changed", "sessionId": "sess-abc", "driverId": "c-1" | null }

// Errors
{ "type": "error", "id": "req-1", "message": "session not found" }
```

### Binary Frames

```
Client → Server (input):  [4-byte session-id LE][raw keyboard bytes]
Server → Client (output): [4-byte session-id LE][raw PTY output bytes]
```

Session IDs are 32-bit integers assigned by cmuxd (not UUIDs) for compact binary framing.

## Shared Workspace Schema

```jsonc
{
  "root": {
    "type": "leaf",           // or "split"
    "id": "g1"
  },
  // Split node example:
  // { "type": "split", "id": "s1", "direction": "horizontal", "ratio": 0.5,
  //   "left": { "type": "leaf", "id": "g1" },
  //   "right": { "type": "leaf", "id": "g2" }
  // }
  "groups": {
    "g1": {
      "id": "g1",
      "tabs": [
        { "id": "t1", "title": "Terminal 1", "type": "terminal", "sessionId": "sess-abc" }
      ],
      "activeTabId": "t1"
    }
  },
  "focusedGroupId": "g1"
}
```

This matches the existing web frontend's `WindowState` / `TreeNode` / `PaneGroup` / `GroupTab` types, with the addition of `sessionId` on tabs to link to cmuxd sessions.

## cmuxd Internals

### Session Manager

Each session contains:
- **PTY**: Forked shell process (via Ghostty's `pty.zig`)
- **VT State**: `libghostty-vt` Terminal instance tracking full screen state
- **Attached clients**: Set of client IDs receiving output
- **Mode**: `shared` (all can type) or `single_driver` (one driver, rest observe)
- **Driver**: Current driver client ID (if single_driver mode)
- **Numeric ID**: 32-bit integer for binary frame headers

### PTY I/O Loop

```
PTY read thread:
  loop:
    bytes = read(pty_master_fd)
    vt_state.process(bytes)       // Update server-side terminal state
    for client in attached_clients:
      client.send_binary([session_id][bytes])
```

### VT Snapshot Generation

On `attach_session`, cmuxd generates a VT escape sequence dump from the libghostty-vt terminal state:

```
1. Send: ESC[2J ESC[H           (clear screen, home cursor)
2. Send: ESC[?1049h/l           (set normal/alt screen mode)
3. For each row r, col c:
     Send: ESC[r;cH              (position cursor)
     Send: SGR sequence           (set attributes: fg, bg, bold, etc.)
     Send: cell character
4. Send: ESC[final_r;final_cH   (restore cursor position)
5. Send: mode restoration sequences (bracketed paste, mouse tracking, etc.)
```

Client's Ghostty instance processes this like normal PTY output and renders the screen.

### Multi-Client Resize (Smallest Wins)

```
on client_resize(client_id, session_id, cols, rows):
  session = sessions[session_id]
  session.client_sizes[client_id] = (cols, rows)
  min_cols = min(s.cols for s in session.client_sizes.values())
  min_rows = min(s.rows for s in session.client_sizes.values())
  if (min_cols, min_rows) != session.current_size:
    session.pty.resize(min_cols, min_rows)
    session.current_size = (min_cols, min_rows)
    broadcast: { type: "session_resized", sessionId, cols: min_cols, rows: min_rows }
```

### CRDT-Style Workspace Mutations

Clients optimistically apply workspace intents locally for responsive UI. cmuxd processes the intent, updates authoritative state, and broadcasts `workspace_update` to all clients. If a client's optimistic state diverges (e.g., conflicting splits), the `workspace_update` replaces it.

The `workspace_update` message contains the **full workspace tree** (not a delta). This is simple and avoids ordering issues. The workspace tree is small (< 10KB even with many tabs/splits), so full-state broadcast is fine.

## Current Status

The web frontend is functional with a **temporary Node.js PTY shim** (`pty-server.mjs`) that provides one PTY per WebSocket connection. This shim has no session persistence, no VT snapshots, no workspace sync, and no multiplayer. It exists so the web UI could be built and tested without blocking on cmuxd.

### What's done (web frontend)
- [x] ghostty-web terminal rendering via WASM
- [x] Split pane layout (horizontal/vertical) with drag-to-resize dividers
- [x] Tab management per pane group (add, close, select, reorder)
- [x] Tab drag-and-drop between groups and onto surfaces
- [x] Keyboard shortcuts: Cmd+D split right, Cmd+Shift+D split down, Ctrl+D close, Cmd+T new tab, Cmd+W close, Cmd+]/[ next/prev tab, Cmd+Ctrl+HJKL spatial focus
- [x] Mouse tracking (SGR mode 1006) — clicks/scroll forwarded to TUI apps
- [x] Fake in-browser shell fallback when no PTY server
- [x] 74 e2e tests (Playwright) covering windowing, PTY I/O, mouse input, mux mode, multiplayer

### What's next
- [x] **Phase 1**: cmuxd skeleton (Zig) — drop-in replacement for pty-server.mjs, 64/64 e2e tests pass
- [x] **Phase 2**: Workspace management in cmuxd — multiplexed WS protocol, session CRUD, workspace tree
- [x] **Phase 3**: VT snapshots for session attach — ghostty-vt linked via lazyDependency, server-side VT state per session, feedVt()/generateSnapshot(), deadlock-safe session cleanup
- [x] **Phase 4**: Multiplayer — client IDs, session attach/detach, shared/single_driver modes, driver handoff, smallest-wins resize, lifecycle events, 74/74 tests pass
- [x] **Phase 5**: Web frontend integration with cmuxd — CmuxdConnection class, mux mode via ?mode=mux, 69/69 tests pass
- [x] **Phase 6**: npm distribution — `cmuxd` npm package, postinstall binary download, GitHub Actions CI for cross-platform builds
- [x] **Phase 7**: Native app integration — `cmux-bridge` Zig binary proxies stdin/stdout through cmuxd WebSocket, Swift `CmuxdBridge` helper detects cmuxd + generates bridge commands, `TerminalSurface` accepts `bridgeCommand` to set `surfaceConfig.command`, binary bundled in app Resources/bin/

## Implementation Plan

### Phase 1: cmuxd Skeleton (Zig) ✅

**New directory**: `/cmuxd/`

```
cmuxd/
  build.zig              # Build config, links libghostty-vt, imports ghostty/src/pty.zig
  build.zig.zon          # Dependencies
  src/
    main.zig             # Entry point, arg parsing, starts server
    server.zig           # WebSocket server (HTTP upgrade + WS framing)
    session.zig          # Session struct (PTY + VT state + clients)
    session_manager.zig  # CRUD for sessions
    workspace.zig        # Workspace tree (shared schema)
    client.zig           # Connected client state
    protocol.zig         # JSON message parsing/serialization
    snapshot.zig         # VT snapshot generation from libghostty-vt state
```

Build: `cd cmuxd && zig build -Doptimize=ReleaseFast`

This phase produces a binary that:
- Listens on `ws://0.0.0.0:3778` (configurable via `--port`)
- Prints auth token on startup
- Accepts WebSocket connections with token auth
- Creates/destroys PTY sessions
- Streams PTY output to attached clients
- Accepts input from clients
- Handles resize (smallest-client-wins)

### Phase 2: Workspace Management ✅

- Implement workspace tree in Zig (matching shared JSON schema)
- Handle `workspace_intent` messages
- Broadcast `workspace_update` on every mutation
- Send `workspace_snapshot` on client connect
- Auto-create a session for each new tab

### Phase 3: Session Attach + VT Snapshots ✅

- Linked ghostty-vt via `lazyDependency` in build.zig, added ghostty dep to build.zig.zon
- Session struct tracks VT state: `ghostty_vt.Terminal`, `VtStream`, `vt_mutex`, `vt_initialized`
- `initVt()` called AFTER heap allocation (ghostty-vt Terminal has internal pointers, invalidated by struct copy)
- `feedVt()`: PTY reader thread feeds all output through VT parser before broadcasting
- `generateSnapshot()`: Uses `TerminalFormatter` with `.emit = .vt`, `.extra = .all` to dump full terminal state
- `attach_session` handler: generates VT snapshot and sends as binary frame to attaching client
- Session cleanup on client disconnect: tracks per-client sessions, destroys orphaned sessions
- Deadlock fix: `destroySession` removes from map under lock, then kills outside lock (reader thread needs mutex for broadcast)
- All 69 e2e tests pass

### Phase 4: Multiplayer ✅

- Client IDs: auto-incrementing u32, assigned on mux client connect, included in workspace_snapshot
- Per-session attached clients: `client_sizes` HashMap tracks (client_id → cols/rows)
- Session modes: `SessionMode.shared` (all can type) vs `.single_driver` (only driver can input)
- Driver protocol: `set_session_mode`, `request_driver`, `release_driver` control messages
- Input filtering: binary frame handler checks `session.canInput(client_id)` before writing to PTY
- Smallest-client-wins resize: `updateClientSize` recalculates min(cols)/min(rows), calls `session.resize` if changed
- Lifecycle events: `client_joined`/`client_left` broadcast on connect/disconnect, `driver_changed` on mode changes
- Session cleanup: on disconnect, detach from all sessions; destroy orphaned sessions (0 attached clients)
- Frontend: `CmuxdConnection` gains `attachSession`, `setSessionMode`, `requestDriver`, `releaseDriver`, event handlers
- 5 new e2e tests: client_joined, client_left, session attach + live output, single_driver blocking, driver handoff
- All 74 e2e tests pass

### Phase 5: Web Frontend Integration ✅

- `CmuxdConnection` class in `surface-registry.ts`: single multiplexed WS, session creation/destroy, input routing, resize
- `?mode=mux` URL param enables mux mode (shared WS, session-per-tab)
- Legacy per-tab WS mode remains default for backward compatibility
- `connectMux()` method: lazily connects shared WS, creates session per tab, wires terminal I/O
- `destroy()` cleans up mux sessions (calls `destroySession()`)
- 5 new e2e tests: single WS connection, typing, split panes share WS, new tab reuses WS, close pane keeps WS alive
- All 69 e2e tests pass (16 legacy PTY + 5 mux mode + 48 windowing)

### Phase 6: npm Distribution ✅

- npm package `cmuxd` at `cmuxd/npm/`: `package.json`, `cli.mjs`, `postinstall.mjs`
- `cli.mjs`: finds binary in `bin/cmuxd-{platform}-{arch}` (downloaded) or `../zig-out/bin/cmuxd` (local build)
- `postinstall.mjs`: downloads pre-built binary from GitHub releases; skips if local build exists; non-fatal on network errors
- GitHub Actions `cmuxd-release.yml`: builds for macOS (arm64/x64) + Linux (x64/arm64), uploads to releases, publishes to npm
- Tag pattern: `cmuxd-v{version}` triggers the release pipeline

### Phase 7: Native App Integration ✅

Bridge-based approach: `cmux-bridge` runs as the PTY command inside GhosttyKit, proxying stdin/stdout through cmuxd's WebSocket. No GhosttyKit fork changes needed.

- `cmuxd/src/bridge.zig`: Zig binary that connects to cmuxd via WebSocket client handshake, creates or attaches to a session, sets terminal to raw mode, spawns reader thread (cmuxd → stdout), main loop reads stdin → cmuxd. Handles SIGWINCH for resize.
- `cmuxd/src/protocol.zig`: Added `writeMaskedWsFrame`, `writeMaskedPtyFrame`, `wsClientHandshake` for RFC 6455 client-side WebSocket support (client frames must be masked).
- `cmuxd/build.zig`: Added `cmux-bridge` as second build target.
- `Sources/CmuxdBridge.swift`: Helper enum with `isAvailable` (TCP connect check to cmuxd), `bridgeBinaryPath` (finds binary in app bundle or dev build), `command()` (generates bridge command string).
- `Sources/GhosttyTerminalView.swift`: `TerminalSurface` accepts optional `bridgeCommand`, sets `surfaceConfig.command` in `createSurface()` when bridge mode active.
- `Sources/TabManager.swift`: All 3 `TerminalSurface` creation sites pass `CmuxdBridge.command()` as `bridgeCommand` — falls back to `nil` (normal local PTY) when cmuxd is not available.
- Build script copies `cmux-bridge` binary to app's `Resources/bin/` (already in PATH).
- All 74 e2e tests pass.

## Feasibility Assessment

### What exists and is reusable
- **Ghostty's `pty.zig`**: Production-quality PTY management. cmuxd imports directly from the Ghostty submodule.
- **libghostty-vt**: Complete VT parser + terminal state machine. Already builds as a library. cmuxd links it.
- **Web frontend split-tree**: The `WindowState`/`TreeNode` model is already implemented and tested. Shared schema matches it.
- **ghostty-web npm package**: Web rendering is solved. Just need to swap fake bash for cmuxd WebSocket.

### What needs to be built
- **WebSocket server in Zig**: Zig has `std.http.Server` but no built-in WebSocket. Options: (a) use `websocket.zig` from the Zig package ecosystem, (b) implement WS framing manually (it's simple: RFC 6455 is ~20 pages), (c) use `libwebsockets` via C interop.
- **Session manager**: ~500 lines. PTY lifecycle, client tracking, resize logic.
- **Workspace tree in Zig**: Port the TypeScript split-tree to Zig. ~300 lines.
- **VT snapshot generation**: Read libghostty-vt terminal state, emit escape sequences. ~200 lines.
- **JSON protocol handling**: Zig's `std.json` handles parsing/serialization. ~400 lines for all message types.
- **CRDT conflict resolution**: For workspace, this is simple since operations are serializable (server total-orders them). ~100 lines.

### Risks
1. **Zig WebSocket ecosystem**: Less mature than Node.js. May need to write WS framing from scratch. Mitigated: WS protocol is simple.
2. **libghostty-vt linking**: The library is designed for WASM export, not as a general-purpose Zig library. May need build system work to link it into a native Zig binary. Mitigated: it's all Zig source, worst case we `@import` the source files directly.
3. **VT snapshot fidelity**: Reconstructing a perfect terminal screen from VT state requires handling all modes (alternate screen, scrolling regions, tab stops, etc.). May need iterative refinement. Mitigated: escape sequence dump is the most forgiving approach.
4. **CRDT complexity creep**: Workspace mutations are simple (add/remove/reorder), but edge cases (concurrent split + close on same pane) need careful handling. Mitigated: full-state broadcast means conflicts are resolved by last-write-wins, which is acceptable for workspace layout.

### Verdict: Feasible

The core infrastructure (PTY, VT parsing, workspace model) already exists in Ghostty and the web frontend. cmuxd is primarily integration work: wiring these pieces together with a WebSocket server and a JSON protocol. The most novel piece (VT snapshots) is ~200 lines of Zig. Estimated total: **~2,000-3,000 lines of Zig** for the full v1.
