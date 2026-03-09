const std = @import("std");
const Allocator = std.mem.Allocator;

/// WebSocket frame opcodes.
pub const ws_text: u8 = 0x1;
pub const ws_binary: u8 = 0x2;
pub const ws_close: u8 = 0x8;
pub const ws_ping: u8 = 0x9;
pub const ws_pong: u8 = 0xA;

/// A decoded WebSocket frame.
pub const WsFrame = struct {
    opcode: u8,
    payload: []u8,
    buf: [65536]u8 = undefined,
};

/// Read one WS frame (blocking). Returns null on EOF/error.
pub fn readWsFrame(stream: std.net.Stream) ?WsFrame {
    var frame: WsFrame = .{ .opcode = 0, .payload = &.{} };

    var hdr: [2]u8 = undefined;
    readExact(stream, &hdr) orelse return null;

    frame.opcode = hdr[0] & 0x0F;
    const masked = (hdr[1] & 0x80) != 0;
    var payload_len: u64 = hdr[1] & 0x7F;

    if (payload_len == 126) {
        var ext: [2]u8 = undefined;
        readExact(stream, &ext) orelse return null;
        payload_len = @as(u64, ext[0]) << 8 | ext[1];
    } else if (payload_len == 127) {
        var ext: [8]u8 = undefined;
        readExact(stream, &ext) orelse return null;
        payload_len = 0;
        for (ext) |b| payload_len = (payload_len << 8) | b;
    }

    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) {
        readExact(stream, &mask) orelse return null;
    }

    if (payload_len > frame.buf.len) return null;
    const len: usize = @intCast(payload_len);
    if (len > 0) {
        readExact(stream, frame.buf[0..len]) orelse return null;
        if (masked) {
            for (frame.buf[0..len], 0..) |*b, i| {
                b.* ^= mask[i % 4];
            }
        }
    }
    frame.payload = frame.buf[0..len];
    return frame;
}

/// Write a WS frame. Thread-safe if the caller holds a lock on the stream.
pub fn writeWsFrame(stream: std.net.Stream, payload: []const u8, opcode: u8) !void {
    var header: [10]u8 = undefined;
    var hlen: usize = 2;

    header[0] = 0x80 | opcode;
    if (payload.len <= 125) {
        header[1] = @intCast(payload.len);
    } else if (payload.len <= 65535) {
        header[1] = 126;
        header[2] = @intCast(payload.len >> 8);
        header[3] = @intCast(payload.len & 0xFF);
        hlen = 4;
    } else {
        header[1] = 127;
        const len: u64 = payload.len;
        for (0..8) |i| {
            header[2 + i] = @intCast((len >> @as(u6, @intCast(56 - i * 8))) & 0xFF);
        }
        hlen = 10;
    }

    _ = try stream.write(header[0..hlen]);
    if (payload.len > 0) {
        _ = try stream.write(payload);
    }
}

/// Send a binary PTY data frame: [4-byte session-id LE][data].
pub fn writePtyFrame(stream: std.net.Stream, session_id: u32, data: []const u8) !void {
    const total_len = 4 + data.len;
    var header: [10]u8 = undefined;
    var hlen: usize = 2;
    header[0] = 0x80 | ws_binary;
    if (total_len <= 125) {
        header[1] = @intCast(total_len);
    } else if (total_len <= 65535) {
        header[1] = 126;
        header[2] = @intCast(total_len >> 8);
        header[3] = @intCast(total_len & 0xFF);
        hlen = 4;
    } else {
        header[1] = 127;
        const len: u64 = total_len;
        for (0..8) |i| {
            header[2 + i] = @intCast((len >> @as(u6, @intCast(56 - i * 8))) & 0xFF);
        }
        hlen = 10;
    }

    // Session ID as 4 bytes LE
    const sid_bytes: [4]u8 = @bitCast(std.mem.nativeToLittle(u32, session_id));

    _ = try stream.write(header[0..hlen]);
    _ = try stream.write(&sid_bytes);
    if (data.len > 0) {
        _ = try stream.write(data);
    }
}

/// Parse a JSON control message type field.
pub fn parseMessageType(data: []const u8) ?[]const u8 {
    return findJsonString(data, "\"type\"");
}

/// Parse a u32 value from JSON by key.
pub fn parseJsonU32(data: []const u8, key: []const u8) ?u32 {
    const val = findJsonNumber(data, key) orelse return null;
    return std.fmt.parseInt(u32, val, 10) catch null;
}

/// Parse a u16 value from JSON by key.
pub fn parseJsonU16(data: []const u8, key: []const u8) ?u16 {
    const val = findJsonNumber(data, key) orelse return null;
    return std.fmt.parseInt(u16, val, 10) catch null;
}

/// Parse a string value from JSON by key.
pub fn findJsonString(data: []const u8, key: []const u8) ?[]const u8 {
    const ki = std.mem.indexOf(u8, data, key) orelse return null;
    var i = ki + key.len;
    // Skip :\s*"
    while (i < data.len and (data[i] == ' ' or data[i] == ':' or data[i] == '\t')) i += 1;
    if (i >= data.len or data[i] != '"') return null;
    i += 1;
    const start = i;
    while (i < data.len and data[i] != '"') i += 1;
    if (i >= data.len) return null;
    return data[start..i];
}

fn findJsonNumber(data: []const u8, key: []const u8) ?[]const u8 {
    const ki = std.mem.indexOf(u8, data, key) orelse return null;
    var i = ki + key.len;
    while (i < data.len and (data[i] == ' ' or data[i] == ':' or data[i] == '\t')) i += 1;
    const start = i;
    while (i < data.len and data[i] >= '0' and data[i] <= '9') i += 1;
    if (i == start) return null;
    return data[start..i];
}

fn readExact(stream: std.net.Stream, buf: []u8) ?void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return null;
        if (n == 0) return null;
        total += n;
    }
}

/// Parse the HTTP request and perform WebSocket handshake.
/// Returns the URI query string or null on failure.
pub fn wsHandshake(stream: std.net.Stream) ?[]const u8 {
    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return null;
        if (n == 0) return null;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
    }
    const request = buf[0..total];

    const line_end = std.mem.indexOf(u8, request, "\r\n") orelse return null;
    const request_line = request[0..line_end];
    const uri_start = (std.mem.indexOf(u8, request_line, " ") orelse return null) + 1;
    const uri_end = std.mem.indexOfPos(u8, request_line, uri_start, " ") orelse return null;
    const uri = request_line[uri_start..uri_end];

    if (!std.mem.startsWith(u8, uri, "/ws")) {
        _ = stream.write("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found") catch {};
        return null;
    }

    const ws_key = findHeader(request, "Sec-WebSocket-Key") orelse {
        _ = stream.write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n") catch {};
        return null;
    };

    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(ws_key);
    hasher.update(magic);
    const digest = hasher.finalResult();
    var accept_buf: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&accept_buf, &digest);

    var resp_buf: [256]u8 = undefined;
    const resp = std.fmt.bufPrint(&resp_buf, "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept: {s}\r\n\r\n", .{accept_buf}) catch return null;
    _ = stream.write(resp) catch return null;

    // Return query string portion
    if (std.mem.indexOf(u8, uri, "?")) |qi| {
        return uri[qi + 1 ..];
    }
    return "";
}

fn findHeader(request: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, request, "\r\n");
    while (lines.next()) |line| {
        if (line.len <= name.len + 1) continue;
        if (!std.ascii.eqlIgnoreCase(line[0..name.len], name)) continue;
        if (line[name.len] != ':') continue;
        var value = line[name.len + 1 ..];
        while (value.len > 0 and value[0] == ' ') value = value[1..];
        return value;
    }
    return null;
}

// ─── WebSocket Client Support ─────────────────────────────────────────────

/// Write a masked WS frame (client → server, per RFC 6455).
pub fn writeMaskedWsFrame(stream: std.net.Stream, payload: []const u8, opcode: u8) !void {
    var header: [14]u8 = undefined;
    var hlen: usize = 2;

    header[0] = 0x80 | opcode;
    // Set mask bit
    if (payload.len <= 125) {
        header[1] = 0x80 | @as(u8, @intCast(payload.len));
    } else if (payload.len <= 65535) {
        header[1] = 0x80 | 126;
        header[2] = @intCast(payload.len >> 8);
        header[3] = @intCast(payload.len & 0xFF);
        hlen = 4;
    } else {
        header[1] = 0x80 | 127;
        const len: u64 = payload.len;
        for (0..8) |i| {
            header[2 + i] = @intCast((len >> @as(u6, @intCast(56 - i * 8))) & 0xFF);
        }
        hlen = 10;
    }

    // Mask key (simple incrementing bytes)
    const mask = [4]u8{ 0x37, 0xfa, 0x21, 0x3d };
    header[hlen] = mask[0];
    header[hlen + 1] = mask[1];
    header[hlen + 2] = mask[2];
    header[hlen + 3] = mask[3];
    hlen += 4;

    _ = try stream.write(header[0..hlen]);
    if (payload.len > 0) {
        var masked: [65536]u8 = undefined;
        const n = @min(payload.len, masked.len);
        for (payload[0..n], 0..) |b, i| {
            masked[i] = b ^ mask[i % 4];
        }
        _ = try stream.write(masked[0..n]);
    }
}

/// Send a masked binary PTY data frame from client: [4-byte session-id LE][data].
pub fn writeMaskedPtyFrame(stream: std.net.Stream, session_id: u32, data: []const u8) !void {
    const total_len = 4 + data.len;
    var header: [14]u8 = undefined;
    var hlen: usize = 2;
    header[0] = 0x80 | ws_binary;
    if (total_len <= 125) {
        header[1] = 0x80 | @as(u8, @intCast(total_len));
    } else if (total_len <= 65535) {
        header[1] = 0x80 | 126;
        header[2] = @intCast(total_len >> 8);
        header[3] = @intCast(total_len & 0xFF);
        hlen = 4;
    } else {
        header[1] = 0x80 | 127;
        const len: u64 = total_len;
        for (0..8) |i| {
            header[2 + i] = @intCast((len >> @as(u6, @intCast(56 - i * 8))) & 0xFF);
        }
        hlen = 10;
    }
    const mask = [4]u8{ 0x37, 0xfa, 0x21, 0x3d };
    header[hlen] = mask[0];
    header[hlen + 1] = mask[1];
    header[hlen + 2] = mask[2];
    header[hlen + 3] = mask[3];
    hlen += 4;

    _ = try stream.write(header[0..hlen]);

    // Mask the session ID + data
    const sid_bytes: [4]u8 = @bitCast(std.mem.nativeToLittle(u32, session_id));
    var masked_sid: [4]u8 = undefined;
    for (0..4) |i| masked_sid[i] = sid_bytes[i] ^ mask[i];
    _ = try stream.write(&masked_sid);

    if (data.len > 0) {
        var masked: [65536]u8 = undefined;
        const n = @min(data.len, masked.len);
        for (data[0..n], 0..) |b, i| {
            masked[i] = b ^ mask[(i + 4) % 4];
        }
        _ = try stream.write(masked[0..n]);
    }
}

/// Perform WebSocket client handshake. Returns true on success.
pub fn wsClientHandshake(stream: std.net.Stream, path: []const u8) bool {
    // Send upgrade request
    var req_buf: [512]u8 = undefined;
    const req = std.fmt.bufPrint(&req_buf,
        "GET {s} HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n\r\n", .{path}) catch return false;
    _ = stream.write(req) catch return false;

    // Read response
    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return false;
        if (n == 0) return false;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
    }
    return std.mem.startsWith(u8, buf[0..total], "HTTP/1.1 101");
}

/// Parse query string params for cols/rows.
pub fn parseQueryParams(query: []const u8) struct { cols: u16, rows: u16 } {
    var cols: u16 = 80;
    var rows: u16 = 24;
    var q = query;
    while (q.len > 0) {
        const sep = std.mem.indexOf(u8, q, "&") orelse q.len;
        const param = q[0..sep];
        if (std.mem.startsWith(u8, param, "cols=")) {
            cols = std.fmt.parseInt(u16, param[5..], 10) catch 80;
        } else if (std.mem.startsWith(u8, param, "rows=")) {
            rows = std.fmt.parseInt(u16, param[5..], 10) catch 24;
        }
        q = if (sep < q.len) q[sep + 1 ..] else "";
    }
    return .{ .cols = cols, .rows = rows };
}
