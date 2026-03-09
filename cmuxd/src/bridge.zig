const std = @import("std");
const posix = std.posix;
const proto = @import("protocol.zig");

const c = @cImport({
    @cInclude("signal.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
    @cInclude("termios.h");
});

/// cmux-bridge: connects to cmuxd WebSocket and proxies terminal I/O.
///
/// Usage: cmux-bridge [--port PORT] [--session ID] [--cols N] [--rows N]
///
/// Creates or attaches to a cmuxd session and proxies stdin/stdout.
/// This enables GhosttyKit surfaces to use cmuxd for session persistence
/// and multiplayer without modifying GhosttyKit itself.

var g_stream: ?std.net.Stream = null;
var g_session_id: u32 = 0;
var g_winch: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn main() !void {
    // Parse args
    var port: u16 = 3778;
    var attach_session: ?u32 = null;
    var cols: u16 = 0;
    var rows: u16 = 0;

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    {
        var args = try std.process.argsWithAllocator(gpa.allocator());
        defer args.deinit();
        _ = args.skip(); // skip binary name
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--port")) {
                if (args.next()) |v| port = std.fmt.parseInt(u16, v, 10) catch 3778;
            } else if (std.mem.eql(u8, arg, "--session")) {
                if (args.next()) |v| attach_session = std.fmt.parseInt(u32, v, 10) catch null;
            } else if (std.mem.eql(u8, arg, "--cols")) {
                if (args.next()) |v| cols = std.fmt.parseInt(u16, v, 10) catch 0;
            } else if (std.mem.eql(u8, arg, "--rows")) {
                if (args.next()) |v| rows = std.fmt.parseInt(u16, v, 10) catch 0;
            }
        }
    }

    // Get terminal size if not specified
    if (cols == 0 or rows == 0) {
        var ws: c.winsize = undefined;
        if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws) == 0) {
            if (cols == 0) cols = ws.ws_col;
            if (rows == 0) rows = ws.ws_row;
        }
        if (cols == 0) cols = 80;
        if (rows == 0) rows = 24;
    }

    // Connect to cmuxd
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    const stream = std.net.tcpConnectToAddress(addr) catch |err| {
        std.debug.print("cmux-bridge: cannot connect to cmuxd on port {d}: {}\n", .{ port, err });
        std.process.exit(1);
    };
    defer stream.close();
    g_stream = stream;

    // WebSocket handshake
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/ws?mode=mux&cols={d}&rows={d}", .{ cols, rows }) catch "/ws?mode=mux&cols=80&rows=24";
    if (!proto.wsClientHandshake(stream, path)) {
        std.debug.print("cmux-bridge: WebSocket handshake failed\n", .{});
        std.process.exit(1);
    }

    // Wait for workspace_snapshot to get initial session ID.
    // cmuxd may send binary PTY frames (from shell startup) and other
    // text messages before the workspace_snapshot, so keep reading.
    var session_id: u32 = 0;
    {
        var attempts: u32 = 0;
        while (attempts < 100) : (attempts += 1) {
            const frame = proto.readWsFrame(stream) orelse {
                std.debug.print("cmux-bridge: no response from cmuxd\n", .{});
                std.process.exit(1);
            };
            if (frame.opcode == proto.ws_text) {
                if (proto.parseJsonU32(frame.payload, "\"initialSessionId\"")) |sid| {
                    session_id = sid;
                    break;
                }
            }
            // Skip binary frames (PTY output) and other text messages
        }
    }

    // If --session was specified, attach to that session instead
    if (attach_session) |sid| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{{\"type\":\"attach_session\",\"sessionId\":{d},\"cols\":{d},\"rows\":{d}}}", .{ sid, cols, rows }) catch "";
        if (msg.len > 0) {
            proto.writeMaskedWsFrame(stream, msg, proto.ws_text) catch {};
            session_id = sid;
        }
    }

    if (session_id == 0) {
        std.debug.print("cmux-bridge: no session available\n", .{});
        std.process.exit(1);
    }
    g_session_id = session_id;

    // Print session info for the parent process to discover
    std.debug.print("cmux-bridge: connected to session {d}\n", .{session_id});

    // Set up SIGWINCH handler for terminal resize
    var sa: posix.Sigaction = .{
        .handler = .{ .handler = sigwinchHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);

    // Set terminal to raw mode
    var orig_termios: c.termios = undefined;
    const stdin_fd = c.STDIN_FILENO;
    const has_termios = c.tcgetattr(stdin_fd, &orig_termios) == 0;
    if (has_termios) {
        var raw = orig_termios;
        raw.c_lflag &= ~@as(c_ulong, @intCast(c.ECHO | c.ICANON | c.ISIG | c.IEXTEN));
        raw.c_iflag &= ~@as(c_ulong, @intCast(c.IXON | c.ICRNL | c.BRKINT | c.INPCK | c.ISTRIP));
        raw.c_oflag &= ~@as(c_ulong, @intCast(c.OPOST));
        raw.c_cc[c.VMIN] = 1;
        raw.c_cc[c.VTIME] = 0;
        _ = c.tcsetattr(stdin_fd, c.TCSAFLUSH, &raw);
    }
    defer {
        if (has_termios) _ = c.tcsetattr(stdin_fd, c.TCSAFLUSH, &orig_termios);
    }

    // Spawn WS reader thread (cmuxd → stdout)
    const reader = std.Thread.spawn(.{}, wsReaderThread, .{ stream, session_id }) catch {
        std.debug.print("cmux-bridge: failed to spawn reader thread\n", .{});
        std.process.exit(1);
    };
    _ = reader; // detached below

    // Main loop: stdin → cmuxd
    var buf: [4096]u8 = undefined;
    while (true) {
        // Check for SIGWINCH
        if (g_winch.swap(false, .acq_rel)) {
            var ws: c.winsize = undefined;
            if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws) == 0) {
                var msg_buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&msg_buf, "{{\"type\":\"resize\",\"sessionId\":{d},\"cols\":{d},\"rows\":{d}}}", .{ session_id, ws.ws_col, ws.ws_row }) catch continue;
                proto.writeMaskedWsFrame(stream, msg, proto.ws_text) catch break;
            }
        }

        const n = posix.read(stdin_fd, &buf) catch break;
        if (n == 0) break;
        proto.writeMaskedPtyFrame(stream, session_id, buf[0..n]) catch break;
    }
}

fn wsReaderThread(stream: std.net.Stream, session_id: u32) void {
    while (true) {
        const frame = proto.readWsFrame(stream) orelse break;
        switch (frame.opcode) {
            proto.ws_binary => {
                // Binary: [4-byte session-id LE][data]
                if (frame.payload.len < 4) continue;
                const sid = std.mem.readInt(u32, frame.payload[0..4], .little);
                if (sid != session_id) continue;
                const data = frame.payload[4..];
                if (data.len > 0) {
                    _ = posix.write(c.STDOUT_FILENO, data) catch break;
                }
            },
            proto.ws_text => {
                // Text messages (session_exited, etc.)
                if (proto.parseMessageType(frame.payload)) |msg_type| {
                    if (std.mem.eql(u8, msg_type, "session_exited")) {
                        if (proto.parseJsonU32(frame.payload, "\"sessionId\"")) |sid| {
                            if (sid == session_id) break;
                        }
                    }
                }
            },
            proto.ws_close => break,
            proto.ws_ping => {
                proto.writeMaskedWsFrame(stream, frame.payload, proto.ws_pong) catch break;
            },
            else => {},
        }
    }
}

fn sigwinchHandler(_: c_int) callconv(.c) void {
    g_winch.store(true, .release);
}
