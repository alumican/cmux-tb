const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");
// Derive the ReadonlyStream type from Terminal.vtStream's return type
const VtStream = @typeInfo(@TypeOf(ghostty_vt.Terminal.vtStream)).@"fn".return_type.?;

const c = @cImport({
    @cInclude("util.h");
    @cInclude("sys/ioctl.h");
    @cInclude("signal.h");
    @cInclude("sys/wait.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

pub const SessionMode = enum { shared, single_driver };
pub const ClientSize = struct { cols: u16, rows: u16 };

pub const Session = struct {
    id: u32,
    pty_fd: c_int,
    pid: c_int,
    cols: u16,
    rows: u16,
    alive: std.atomic.Value(bool),
    reader_thread: ?std.Thread = null,
    alloc: Allocator,

    // Server-side VT state — tracks terminal screen for snapshots on attach
    vt: ghostty_vt.Terminal = undefined,
    vt_stream: VtStream = undefined,
    vt_mutex: std.Thread.Mutex = .{},
    vt_initialized: bool = false,

    // Multiplayer state
    mode: SessionMode = .shared,
    driver_id: ?u32 = null,
    client_sizes: std.AutoHashMap(u32, ClientSize) = undefined,
    mp_initialized: bool = false,

    pub fn spawn(alloc: Allocator, id: u32, cols_val: u16, rows_val: u16) !Session {
        var master_fd: c_int = undefined;
        var ws: c.winsize = .{
            .ws_col = cols_val,
            .ws_row = rows_val,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        const pid = c.forkpty(&master_fd, null, null, &ws);
        if (pid < 0) return error.ForkFailed;

        if (pid == 0) {
            // Child: exec shell
            _ = c.setenv("TERM", "xterm-256color", 1);
            const cwd = c.getenv("PTY_CWD") orelse c.getenv("HOME");
            if (cwd) |d| _ = c.chdir(d);
            const shell: [*c]const u8 = if (c.getenv("SHELL")) |s| s else "/bin/zsh";
            var argv_arr = [_:null]?[*:0]const u8{shell};
            _ = c.execvp(shell, @ptrCast(&argv_arr));
            c._exit(1);
        }

        return Session{
            .id = id,
            .pty_fd = master_fd,
            .pid = pid,
            .cols = cols_val,
            .rows = rows_val,
            .alive = std.atomic.Value(bool).init(true),
            .alloc = alloc,
        };
    }

    /// Initialize VT state. Must be called AFTER the Session is at its final
    /// heap location (ghostty-vt Terminal has internal pointers that would be
    /// invalidated by a struct copy).
    /// Initialize VT state. Must be called AFTER the Session is at its final
    /// heap location (ghostty-vt Terminal has internal pointers that would be
    /// invalidated by a struct copy).
    pub fn initVt(self: *Session) !void {
        self.vt = try ghostty_vt.Terminal.init(self.alloc, .{
            .cols = self.cols,
            .rows = self.rows,
        });
        self.vt_stream = self.vt.vtStream();
        self.vt_initialized = true;
    }

    /// Feed raw PTY output through the VT parser to update terminal state.
    pub fn feedVt(self: *Session, data: []const u8) void {
        if (!self.vt_initialized) return;
        self.vt_mutex.lock();
        defer self.vt_mutex.unlock();
        self.vt_stream.nextSlice(data) catch {};
    }

    /// Generate a VT escape sequence snapshot of the current terminal state.
    /// Returns a dynamically allocated buffer that the caller must free.
    pub fn generateSnapshot(self: *Session) ![]u8 {
        if (!self.vt_initialized) return &.{};
        self.vt_mutex.lock();
        defer self.vt_mutex.unlock();

        var buf: std.ArrayList(u8) = .{};
        var writer = buf.writer(self.alloc);
        const formatter: ghostty_vt.formatter.TerminalFormatter = .{
            .terminal = &self.vt,
            .opts = .{ .emit = .vt },
            .content = .{ .selection = null },
            .extra = .all,
            .pin_map = null,
        };
        try writer.print("{f}", .{formatter});
        return buf.toOwnedSlice(self.alloc);
    }

    /// Initialize multiplayer state. Called after heap allocation.
    pub fn initMultiplayer(self: *Session) void {
        self.client_sizes = std.AutoHashMap(u32, ClientSize).init(self.alloc);
        self.mp_initialized = true;
    }

    /// Register a client as attached to this session.
    pub fn attachClient(self: *Session, client_id: u32, size: ClientSize) void {
        if (!self.mp_initialized) return;
        self.client_sizes.put(client_id, size) catch {};
    }

    /// Remove a client from this session.
    pub fn detachClient(self: *Session, client_id: u32) void {
        if (!self.mp_initialized) return;
        _ = self.client_sizes.remove(client_id);
        if (self.driver_id) |did| {
            if (did == client_id) self.driver_id = null;
        }
    }

    /// Number of attached clients.
    pub fn clientCount(self: *Session) usize {
        if (!self.mp_initialized) return 0;
        return self.client_sizes.count();
    }

    /// Update a client's size and apply smallest-wins. Returns true if effective size changed.
    pub fn updateClientSize(self: *Session, client_id: u32, new_size: ClientSize) bool {
        if (!self.mp_initialized) return false;
        self.client_sizes.put(client_id, new_size) catch return false;
        return self.applySmallestWins();
    }

    /// Check if a client can send input to this session.
    pub fn canInput(self: *Session, client_id: u32) bool {
        return switch (self.mode) {
            .shared => true,
            .single_driver => if (self.driver_id) |did| did == client_id else false,
        };
    }

    /// Apply smallest-wins resize logic. Returns true if session size changed.
    fn applySmallestWins(self: *Session) bool {
        var min_cols: u16 = std.math.maxInt(u16);
        var min_rows: u16 = std.math.maxInt(u16);
        var it = self.client_sizes.valueIterator();
        var count: usize = 0;
        while (it.next()) |size| {
            if (size.cols < min_cols) min_cols = size.cols;
            if (size.rows < min_rows) min_rows = size.rows;
            count += 1;
        }
        if (count == 0) return false;
        if (min_cols != self.cols or min_rows != self.rows) {
            self.resize(min_cols, min_rows);
            return true;
        }
        return false;
    }

    pub fn resize(self: *Session, cols_val: u16, rows_val: u16) void {
        self.cols = cols_val;
        self.rows = rows_val;
        var ws: c.winsize = .{
            .ws_col = cols_val,
            .ws_row = rows_val,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        _ = c.ioctl(self.pty_fd, c.TIOCSWINSZ, &ws);
        if (self.vt_initialized) {
            self.vt_mutex.lock();
            defer self.vt_mutex.unlock();
            self.vt.resize(self.alloc, cols_val, rows_val) catch {};
        }
    }

    pub fn writeInput(self: *Session, data: []const u8) !void {
        _ = try posix.write(@intCast(self.pty_fd), data);
    }

    pub fn kill(self: *Session) void {
        self.alive.store(false, .release);
        _ = c.kill(self.pid, c.SIGTERM);
        _ = c.close(self.pty_fd);
        if (self.reader_thread) |t| t.join();
        _ = c.waitpid(self.pid, null, 0);
        if (self.vt_initialized) {
            self.vt_stream.deinit();
            self.vt.deinit(self.alloc);
        }
        if (self.mp_initialized) {
            self.client_sizes.deinit();
        }
    }
};

/// Manages all active PTY sessions.
pub const SessionManager = struct {
    sessions: std.AutoHashMap(u32, *Session),
    alloc: Allocator,
    next_id: u32 = 1,

    pub fn init(alloc: Allocator) SessionManager {
        return .{
            .sessions = std.AutoHashMap(u32, *Session).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        var it = self.sessions.valueIterator();
        while (it.next()) |sp| {
            sp.*.kill();
            self.alloc.destroy(sp.*);
        }
        self.sessions.deinit();
    }

    pub fn create(self: *SessionManager, cols: u16, rows: u16) !*Session {
        const id = self.next_id;
        self.next_id += 1;

        const sess = try self.alloc.create(Session);
        sess.* = try Session.spawn(self.alloc, id, cols, rows);
        // Initialize VT state after heap allocation to avoid pointer invalidation
        try sess.initVt();
        sess.initMultiplayer();
        try self.sessions.put(id, sess);
        return sess;
    }

    pub fn get(self: *SessionManager, id: u32) ?*Session {
        return self.sessions.get(id);
    }

    pub fn destroy(self: *SessionManager, id: u32) void {
        if (self.sessions.fetchRemove(id)) |kv| {
            kv.value.kill();
            self.alloc.destroy(kv.value);
        }
    }
};
