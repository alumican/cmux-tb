const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const session_mod = @import("session.zig");
const Session = session_mod.Session;
const SessionManager = session_mod.SessionManager;
const SessionMode = session_mod.SessionMode;
const ClientSize = session_mod.ClientSize;
const proto = @import("protocol.zig");
const config = @import("config.zig");

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

const default_port: u16 = 3778;

/// Global state shared across all client threads.
const Server = struct {
    mutex: std.Thread.Mutex = .{},
    sessions: SessionManager,
    clients: std.ArrayList(*Client),
    alloc: Allocator,

    // Workspace state
    next_group_id: u32 = 1,
    next_tab_id: u32 = 1,
    next_client_id: u32 = 1,
    // Workspace tree stored as pre-serialized JSON for simplicity.
    // Updated on every mutation and broadcast to all clients.
    workspace_json: ?[]u8 = null,
    // Pre-serialized terminal config JSON from the user's Ghostty config.
    terminal_config_json: ?[]const u8 = null,

    fn init(alloc: Allocator) Server {
        return .{
            .sessions = SessionManager.init(alloc),
            .clients = .{},
            .alloc = alloc,
        };
    }

    fn deinit(self: *Server) void {
        if (self.workspace_json) |wj| self.alloc.free(wj);
        if (self.terminal_config_json) |tcj| self.alloc.free(tcj);
        self.sessions.deinit();
        self.clients.deinit(self.alloc);
    }

    fn addClient(self: *Server, client: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.clients.append(self.alloc, client) catch {};
    }

    fn removeClient(self: *Server, client: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items, 0..) |c_item, i| {
            if (c_item == client) {
                _ = self.clients.swapRemove(i);
                break;
            }
        }
    }

    /// Broadcast a text message to all connected clients.
    fn broadcast(self: *Server, msg: []const u8) void {
        // Must be called with mutex held.
        for (self.clients.items) |client| {
            client.sendText(msg);
        }
    }

    /// Broadcast binary PTY output to all clients.
    fn broadcastPtyOutput(self: *Server, session_id: u32, data: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items) |client| {
            client.sendPtyData(session_id, data);
        }
    }

    /// Create a session and start its reader thread.
    fn createSession(self: *Server, cols: u16, rows: u16) !*Session {
        self.mutex.lock();
        defer self.mutex.unlock();
        const sess = try self.sessions.create(cols, rows);

        // Start PTY reader thread
        sess.reader_thread = std.Thread.spawn(.{}, ptyReaderThread, .{ self, sess }) catch null;
        return sess;
    }

    fn destroySession(self: *Server, session_id: u32) void {
        // Remove from map under lock, then kill outside lock to avoid
        // deadlock with reader thread which needs mutex to broadcast.
        self.mutex.lock();
        const sess = if (self.sessions.sessions.fetchRemove(session_id)) |kv| kv.value else null;
        self.mutex.unlock();
        if (sess) |s| {
            s.kill();
            self.alloc.destroy(s);
        }
    }

    /// Build workspace JSON for the current state.
    fn buildWorkspaceJson(self: *Server) ![]u8 {
        // Build a workspace snapshot matching the TypeScript WindowState type.
        // For now, build it from the sessions map.
        var buf: std.ArrayList(u8) = .{};
        const w = buf.writer(self.alloc);

        try w.writeAll("{\"root\":");
        // Build tree from sessions
        var sess_ids: std.ArrayList(u32) = .{};
        defer sess_ids.deinit(self.alloc);
        {
            var it = self.sessions.sessions.keyIterator();
            while (it.next()) |k| try sess_ids.append(self.alloc, k.*);
        }
        // Sort for deterministic output
        std.mem.sort(u32, sess_ids.items, {}, std.sort.asc(u32));

        if (sess_ids.items.len == 0) {
            // Empty workspace
            try w.writeAll("{\"type\":\"leaf\",\"id\":\"g0\"},");
            try w.writeAll("\"groups\":{\"g0\":{\"id\":\"g0\",\"tabs\":[],\"activeTabId\":\"\"}},");
            try w.writeAll("\"focusedGroupId\":\"g0\"}");
        } else if (sess_ids.items.len == 1) {
            const sid = sess_ids.items[0];
            try w.print("{{\"type\":\"leaf\",\"id\":\"g{d}\"}},", .{sid});
            try w.print("\"groups\":{{\"g{d}\":{{\"id\":\"g{d}\",\"tabs\":[{{\"id\":\"t{d}\",\"title\":\"Terminal\",\"type\":\"terminal\",\"sessionId\":{d}}}],\"activeTabId\":\"t{d}\"}}}},", .{ sid, sid, sid, sid, sid });
            try w.print("\"focusedGroupId\":\"g{d}\"}}", .{sid});
        } else {
            // Build a balanced tree of horizontal splits
            try buildTreeJson(w, sess_ids.items, 0);
            try w.writeAll(",\"groups\":{");
            for (sess_ids.items, 0..) |sid, i| {
                if (i > 0) try w.writeByte(',');
                try w.print("\"g{d}\":{{\"id\":\"g{d}\",\"tabs\":[{{\"id\":\"t{d}\",\"title\":\"Terminal\",\"type\":\"terminal\",\"sessionId\":{d}}}],\"activeTabId\":\"t{d}\"}}", .{ sid, sid, sid, sid, sid });
            }
            try w.print("}},\"focusedGroupId\":\"g{d}\"}}", .{sess_ids.items[0]});
        }
        return buf.toOwnedSlice(self.alloc);
    }
};

fn buildTreeJson(w: anytype, ids: []const u32, split_id: u32) !void {
    if (ids.len == 1) {
        try w.print("{{\"type\":\"leaf\",\"id\":\"g{d}\"}}", .{ids[0]});
    } else {
        const mid = ids.len / 2;
        try w.print("{{\"type\":\"split\",\"id\":\"s{d}\",\"direction\":\"horizontal\",\"ratio\":0.5,\"left\":", .{split_id});
        try buildTreeJson(w, ids[0..mid], split_id * 2 + 1);
        try w.writeAll(",\"right\":");
        try buildTreeJson(w, ids[mid..], split_id * 2 + 2);
        try w.writeByte('}');
    }
}

fn ptyReaderThread(server: *Server, sess: *Session) void {
    var buf: [8192]u8 = undefined;
    while (sess.alive.load(.acquire)) {
        const n = posix.read(@intCast(sess.pty_fd), &buf) catch break;
        if (n == 0) break;
        // Feed through VT parser for server-side state tracking
        sess.feedVt(buf[0..n]);
        server.broadcastPtyOutput(sess.id, buf[0..n]);
    }
    // Session died — notify clients
    var msg_buf: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "{{\"type\":\"session_exited\",\"sessionId\":{d}}}", .{sess.id}) catch return;
    server.mutex.lock();
    defer server.mutex.unlock();
    server.broadcast(msg);
}

/// Per-client state.
const Client = struct {
    stream: std.net.Stream,
    write_lock: std.Thread.Mutex = .{},
    id: u32 = 0,

    fn sendText(self: *Client, msg: []const u8) void {
        self.write_lock.lock();
        defer self.write_lock.unlock();
        proto.writeWsFrame(self.stream, msg, proto.ws_text) catch {};
    }

    fn sendPtyData(self: *Client, session_id: u32, data: []const u8) void {
        self.write_lock.lock();
        defer self.write_lock.unlock();
        proto.writePtyFrame(self.stream, session_id, data) catch {};
    }
};

// ─── Legacy mode ───────────────────────────────────────────────────────────
// Backward-compatible: one PTY per WS (matches pty-server.mjs protocol).
// Used when client connects to /ws with cols/rows query params.
fn handleLegacyClient(alloc: Allocator, stream: std.net.Stream, query: []const u8) void {
    const params = proto.parseQueryParams(query);

    // Spawn PTY directly (not through server state)
    var sess = Session.spawn(alloc, 0, params.cols, params.rows) catch return;
    defer sess.kill();

    // PTY reader thread
    const reader = std.Thread.spawn(.{}, legacyPtyReader, .{ sess.pty_fd, stream }) catch return;

    // WS read loop
    while (true) {
        const frame = proto.readWsFrame(stream) orelse break;
        switch (frame.opcode) {
            proto.ws_text => {
                if (frame.payload.len > 0 and frame.payload[0] == '{') {
                    if (proto.parseMessageType(frame.payload)) |msg_type| {
                        if (std.mem.eql(u8, msg_type, "resize")) {
                            const c_val = proto.parseJsonU16(frame.payload, "\"cols\"") orelse continue;
                            const r_val = proto.parseJsonU16(frame.payload, "\"rows\"") orelse continue;
                            sess.resize(c_val, r_val);
                            continue;
                        }
                    }
                }
                sess.writeInput(frame.payload) catch break;
            },
            proto.ws_binary => {
                sess.writeInput(frame.payload) catch break;
            },
            proto.ws_close => break,
            proto.ws_ping => {
                proto.writeWsFrame(stream, frame.payload, proto.ws_pong) catch break;
            },
            else => {},
        }
    }

    // Cleanup
    sess.alive.store(false, .release);
    const fd: c_int = sess.pty_fd;
    _ = c.close(fd);
    reader.join();
}

fn legacyPtyReader(master_fd: c_int, stream: std.net.Stream) void {
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = posix.read(@intCast(master_fd), &buf) catch break;
        if (n == 0) break;
        proto.writeWsFrame(stream, buf[0..n], proto.ws_binary) catch break;
    }
    proto.writeWsFrame(stream, &.{}, proto.ws_close) catch {};
}

// ─── Multiplexed mode ──────────────────────────────────────────────────────
// Single WS per client, session data multiplexed via binary frames with
// 4-byte session ID prefix.
fn handleMultiplexedClient(server: *Server, stream: std.net.Stream, query: []const u8) void {
    const alloc = server.alloc;
    const params = proto.parseQueryParams(query);

    // Assign client ID
    server.mutex.lock();
    const client_id = server.next_client_id;
    server.next_client_id += 1;
    server.mutex.unlock();

    // Create client
    const client = alloc.create(Client) catch return;
    client.* = .{ .stream = stream, .id = client_id };
    server.addClient(client);

    // Broadcast client_joined to existing clients
    {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"client_joined\",\"clientId\":{d}}}", .{client_id}) catch "";
        if (msg.len > 0) {
            server.mutex.lock();
            server.broadcast(msg);
            server.mutex.unlock();
        }
    }

    // Track sessions this client is attached to for cleanup on disconnect
    var client_sessions: std.ArrayList(u32) = .{};
    defer {
        // Detach from all sessions; destroy orphaned ones
        for (client_sessions.items) |sid| {
            server.mutex.lock();
            if (server.sessions.get(sid)) |sess| {
                sess.detachClient(client_id);
                const was_driver = sess.driver_id == null and sess.mode == .single_driver;
                if (sess.clientCount() == 0) {
                    const removed = if (server.sessions.sessions.fetchRemove(sid)) |kv| kv.value else null;
                    server.mutex.unlock();
                    if (removed) |s| {
                        s.kill();
                        alloc.destroy(s);
                    }
                } else {
                    if (was_driver) {
                        var dbuf: [128]u8 = undefined;
                        const dmsg = std.fmt.bufPrint(&dbuf, "{{\"type\":\"driver_changed\",\"sessionId\":{d},\"driverId\":null}}", .{sid}) catch "";
                        if (dmsg.len > 0) server.broadcast(dmsg);
                    }
                    server.mutex.unlock();
                }
            } else {
                server.mutex.unlock();
            }
        }
        client_sessions.deinit(alloc);

        // Broadcast client_left
        {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"client_left\",\"clientId\":{d}}}", .{client_id}) catch "";
            if (msg.len > 0) {
                server.mutex.lock();
                server.broadcast(msg);
                server.mutex.unlock();
            }
        }

        server.removeClient(client);
        alloc.destroy(client);
    }

    // Create initial session and attach this client
    const initial_sess = server.createSession(params.cols, params.rows) catch return;
    initial_sess.attachClient(client_id, .{ .cols = params.cols, .rows = params.rows });
    client_sessions.append(alloc, initial_sess.id) catch {};

    // Send workspace snapshot
    {
        server.mutex.lock();
        const wj = server.buildWorkspaceJson() catch {
            server.mutex.unlock();
            return;
        };
        defer alloc.free(wj);
        const tcj = server.terminal_config_json;
        server.mutex.unlock();

        var msg_buf: [65536]u8 = undefined;
        const msg = if (tcj) |tc|
            std.fmt.bufPrint(&msg_buf, "{{\"type\":\"workspace_snapshot\",\"workspace\":{s},\"initialSessionId\":{d},\"clientId\":{d},\"terminalConfig\":{s}}}", .{ wj, initial_sess.id, client_id, tc })
        else
            std.fmt.bufPrint(&msg_buf, "{{\"type\":\"workspace_snapshot\",\"workspace\":{s},\"initialSessionId\":{d},\"clientId\":{d}}}", .{ wj, initial_sess.id, client_id });
        const final_msg = msg catch return;
        client.sendText(final_msg);
    }

    // WS read loop
    while (true) {
        const frame = proto.readWsFrame(stream) orelse break;
        switch (frame.opcode) {
            proto.ws_text => {
                handleControlMessage(server, client, &client_sessions, frame.payload, params.cols, params.rows);
            },
            proto.ws_binary => {
                // Binary: [4-byte session-id LE][input data]
                if (frame.payload.len < 4) continue;
                const sid = std.mem.readInt(u32, frame.payload[0..4], .little);
                const data = frame.payload[4..];
                server.mutex.lock();
                if (server.sessions.get(sid)) |sess| {
                    const allowed = sess.canInput(client.id);
                    server.mutex.unlock();
                    if (allowed) sess.writeInput(data) catch {};
                } else {
                    server.mutex.unlock();
                }
            },
            proto.ws_close => break,
            proto.ws_ping => {
                client.write_lock.lock();
                proto.writeWsFrame(stream, frame.payload, proto.ws_pong) catch {};
                client.write_lock.unlock();
            },
            else => {},
        }
    }
}

fn handleControlMessage(server: *Server, client: *Client, client_sessions: *std.ArrayList(u32), data: []const u8, default_cols: u16, default_rows: u16) void {
    const msg_type = proto.parseMessageType(data) orelse return;

    if (std.mem.eql(u8, msg_type, "create_session")) {
        const cols = proto.parseJsonU16(data, "\"cols\"") orelse default_cols;
        const rows = proto.parseJsonU16(data, "\"rows\"") orelse default_rows;
        const sess = server.createSession(cols, rows) catch return;
        sess.attachClient(client.id, .{ .cols = cols, .rows = rows });
        client_sessions.append(server.alloc, sess.id) catch {};
        // Send session_created
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"session_created\",\"sessionId\":{d},\"cols\":{d},\"rows\":{d}}}", .{ sess.id, cols, rows }) catch return;
        client.sendText(msg);
        broadcastWorkspaceUpdate(server);
    } else if (std.mem.eql(u8, msg_type, "destroy_session")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        for (client_sessions.items, 0..) |cs, i| {
            if (cs == sid) { _ = client_sessions.swapRemove(i); break; }
        }
        server.destroySession(sid);
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"session_destroyed\",\"sessionId\":{d}}}", .{sid}) catch return;
        server.mutex.lock();
        server.broadcast(msg);
        server.mutex.unlock();
        broadcastWorkspaceUpdate(server);
    } else if (std.mem.eql(u8, msg_type, "resize")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        const cols = proto.parseJsonU16(data, "\"cols\"") orelse return;
        const rows = proto.parseJsonU16(data, "\"rows\"") orelse return;
        server.mutex.lock();
        if (server.sessions.get(sid)) |sess| {
            const changed = sess.updateClientSize(client.id, .{ .cols = cols, .rows = rows });
            if (changed) {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"session_resized\",\"sessionId\":{d},\"cols\":{d},\"rows\":{d}}}", .{ sid, sess.cols, sess.rows }) catch "";
                if (msg.len > 0) server.broadcast(msg);
            }
            server.mutex.unlock();
        } else {
            server.mutex.unlock();
        }
    } else if (std.mem.eql(u8, msg_type, "attach_session")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        const cols = proto.parseJsonU16(data, "\"cols\"") orelse default_cols;
        const rows = proto.parseJsonU16(data, "\"rows\"") orelse default_rows;
        server.mutex.lock();
        const sess = server.sessions.get(sid);
        server.mutex.unlock();
        if (sess) |s| {
            // Register this client as attached
            s.attachClient(client.id, .{ .cols = cols, .rows = rows });
            var found = false;
            for (client_sessions.items) |cs| {
                if (cs == sid) { found = true; break; }
            }
            if (!found) client_sessions.append(server.alloc, sid) catch {};

            // Generate VT snapshot and send to client
            const snapshot = s.generateSnapshot() catch return;
            defer server.alloc.free(snapshot);
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"session_attached\",\"sessionId\":{d}}}", .{sid}) catch return;
            client.sendText(msg);
            client.sendPtyData(sid, snapshot);
        } else {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"error\",\"message\":\"session not found\",\"sessionId\":{d}}}", .{sid}) catch return;
            client.sendText(msg);
        }
    } else if (std.mem.eql(u8, msg_type, "detach_session")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        server.mutex.lock();
        if (server.sessions.get(sid)) |sess| {
            sess.detachClient(client.id);
            for (client_sessions.items, 0..) |cs, i| {
                if (cs == sid) { _ = client_sessions.swapRemove(i); break; }
            }
            server.mutex.unlock();
        } else {
            server.mutex.unlock();
        }
    } else if (std.mem.eql(u8, msg_type, "set_session_mode")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        const mode_str = proto.findJsonString(data, "\"mode\"") orelse return;
        server.mutex.lock();
        if (server.sessions.get(sid)) |sess| {
            if (std.mem.eql(u8, mode_str, "shared")) {
                sess.mode = .shared;
                sess.driver_id = null;
            } else if (std.mem.eql(u8, mode_str, "single_driver")) {
                sess.mode = .single_driver;
                sess.driver_id = client.id;
            }
            var buf: [256]u8 = undefined;
            const msg = if (sess.driver_id) |did|
                std.fmt.bufPrint(&buf, "{{\"type\":\"driver_changed\",\"sessionId\":{d},\"driverId\":{d},\"mode\":\"{s}\"}}", .{ sid, did, mode_str })
            else
                std.fmt.bufPrint(&buf, "{{\"type\":\"driver_changed\",\"sessionId\":{d},\"driverId\":null,\"mode\":\"{s}\"}}", .{ sid, mode_str });
            if (msg) |m| server.broadcast(m) else |_| {}
            server.mutex.unlock();
        } else {
            server.mutex.unlock();
        }
    } else if (std.mem.eql(u8, msg_type, "request_driver")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        server.mutex.lock();
        if (server.sessions.get(sid)) |sess| {
            if (sess.mode == .single_driver and sess.driver_id == null) {
                sess.driver_id = client.id;
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"driver_changed\",\"sessionId\":{d},\"driverId\":{d}}}", .{ sid, client.id }) catch "";
                if (msg.len > 0) server.broadcast(msg);
            }
            server.mutex.unlock();
        } else {
            server.mutex.unlock();
        }
    } else if (std.mem.eql(u8, msg_type, "release_driver")) {
        const sid = proto.parseJsonU32(data, "\"sessionId\"") orelse return;
        server.mutex.lock();
        if (server.sessions.get(sid)) |sess| {
            if (sess.driver_id) |did| {
                if (did == client.id) {
                    sess.driver_id = null;
                    var buf: [256]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"driver_changed\",\"sessionId\":{d},\"driverId\":null}}", .{sid}) catch "";
                    if (msg.len > 0) server.broadcast(msg);
                }
            }
            server.mutex.unlock();
        } else {
            server.mutex.unlock();
        }
    }
}

fn broadcastWorkspaceUpdate(server: *Server) void {
    server.mutex.lock();
    const wj = server.buildWorkspaceJson() catch {
        server.mutex.unlock();
        return;
    };
    defer server.alloc.free(wj);

    var buf: [65536]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"workspace_update\",\"workspace\":{s}}}", .{wj}) catch {
        server.mutex.unlock();
        return;
    };
    server.broadcast(msg);
    server.mutex.unlock();
}

// ─── Entry point ───────────────────────────────────────────────────────────

var global_server: Server = undefined;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var port: u16 = default_port;
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--port")) {
                if (args.next()) |p| {
                    port = std.fmt.parseInt(u16, p, 10) catch default_port;
                }
            }
        }
    }

    global_server = Server.init(alloc);
    defer global_server.deinit();

    // Load user's Ghostty config and pre-serialize to JSON
    {
        const terminal_config = config.load(alloc) catch |err| blk: {
            std.debug.print("cmuxd: failed to load ghostty config: {}\n", .{err});
            break :blk config.TerminalConfig{};
        };
        var json_buf: [8192]u8 = undefined;
        if (config.toJson(&terminal_config, &json_buf)) |json| {
            if (json.len > 2) { // "{}" means empty config, skip
                global_server.terminal_config_json = alloc.dupe(u8, json) catch null;
                std.debug.print("cmuxd: loaded ghostty config ({d} bytes)\n", .{json.len});
            }
        } else |_| {
            std.debug.print("cmuxd: failed to serialize terminal config\n", .{});
        }
    }

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("cmuxd listening on :{d}\n", .{port});

    while (true) {
        const conn = server.accept() catch continue;
        const thread = std.Thread.spawn(.{}, clientThread, .{ alloc, conn.stream }) catch {
            conn.stream.close();
            continue;
        };
        thread.detach();
    }
}

fn clientThread(alloc: Allocator, stream: std.net.Stream) void {
    defer stream.close();

    // Perform WS handshake
    const query = proto.wsHandshake(stream) orelse return;

    // Detect mode: if "mode=mux" param present, use multiplexed mode.
    // Otherwise use legacy mode (one PTY per WS, backward compatible).
    if (std.mem.indexOf(u8, query, "mode=mux") != null) {
        handleMultiplexedClient(&global_server, stream, query);
    } else {
        handleLegacyClient(alloc, stream, query);
    }
}
