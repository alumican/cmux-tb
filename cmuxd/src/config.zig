const std = @import("std");
const Allocator = std.mem.Allocator;

/// Terminal configuration parsed from the user's Ghostty config file.
/// Fields are optional — null means "use client-side default".
pub const TerminalConfig = struct {
    font_family: ?[]const u8 = null,
    font_size: ?u16 = null,
    cursor_style: ?[]const u8 = null, // "bar", "block", "underline"
    cursor_blink: ?bool = null,
    scrollback_limit: ?u32 = null,
    web_renderer: ?[]const u8 = null, // "xterm" or "ghostty"
    // Colors (hex strings like "#272822")
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    cursor_color: ?[]const u8 = null,
    cursor_text: ?[]const u8 = null,
    selection_bg: ?[]const u8 = null,
    selection_fg: ?[]const u8 = null,
    palette: [16]?[]const u8 = .{null} ** 16,
};

const palette_names = [16][]const u8{
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "brightBlack",
    "brightRed",
    "brightGreen",
    "brightYellow",
    "brightBlue",
    "brightMagenta",
    "brightCyan",
    "brightWhite",
};

/// Load the user's Ghostty config. Returns default (all-null) on any error.
pub fn load(alloc: Allocator) !TerminalConfig {
    var config = TerminalConfig{};
    var theme_name: ?[]const u8 = null;
    defer if (theme_name) |t| alloc.free(t);

    // Try macOS config path first, then XDG fallback
    const home = std.posix.getenv("HOME") orelse return config;

    var found = false;

    // Try macOS path
    {
        const path = try std.fmt.allocPrint(alloc, "{s}/Library/Application Support/com.mitchellh.ghostty/config", .{home});
        defer alloc.free(path);
        if (parseFile(alloc, path, &config, &theme_name)) {
            found = true;
        } else |_| {}
    }

    // Try ~/.config/ghostty/config
    if (!found) {
        const path = try std.fmt.allocPrint(alloc, "{s}/.config/ghostty/config", .{home});
        defer alloc.free(path);
        if (parseFile(alloc, path, &config, &theme_name)) {
            found = true;
        } else |_| {}
    }

    // Also check XDG_CONFIG_HOME
    if (!found) {
        if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
            const path = try std.fmt.allocPrint(alloc, "{s}/ghostty/config", .{xdg});
            defer alloc.free(path);
            parseFile(alloc, path, &config, &theme_name) catch {};
        }
    }

    // Resolve theme if specified
    if (theme_name) |name| {
        resolveTheme(alloc, home, name, &config) catch |err| {
            std.debug.print("cmuxd: failed to resolve theme '{s}': {}\n", .{ name, err });
        };
    }

    return config;
}

fn parseFile(alloc: Allocator, path: []const u8, cfg: *TerminalConfig, theme_name: *?[]const u8) !void {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    // Config files are small — read the whole thing
    const contents = file.readToEndAlloc(alloc, 1024 * 1024) catch return error.ReadFailed;
    defer alloc.free(contents);

    parseContents(alloc, contents, cfg, theme_name);
}

fn parseContents(alloc: Allocator, contents: []const u8, cfg: *TerminalConfig, theme_name: ?*?[]const u8) void {
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Split on '=' (first occurrence)
        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
        const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

        if (value.len == 0) continue;

        // Strip quotes from value
        const clean_val = stripQuotes(value);

        if (std.mem.eql(u8, key, "font-family")) {
            if (cfg.font_family) |old| alloc.free(old);
            cfg.font_family = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "font-size")) {
            cfg.font_size = std.fmt.parseInt(u16, clean_val, 10) catch null;
        } else if (std.mem.eql(u8, key, "cursor-style")) {
            if (cfg.cursor_style) |old| alloc.free(old);
            cfg.cursor_style = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "cursor-style-blink")) {
            cfg.cursor_blink = std.mem.eql(u8, clean_val, "true");
        } else if (std.mem.eql(u8, key, "scrollback-limit")) {
            cfg.scrollback_limit = std.fmt.parseInt(u32, clean_val, 10) catch null;
        } else if (std.mem.eql(u8, key, "web-renderer")) {
            if (cfg.web_renderer) |old| alloc.free(old);
            cfg.web_renderer = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "foreground")) {
            if (cfg.foreground) |old| alloc.free(old);
            cfg.foreground = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "background")) {
            if (cfg.background) |old| alloc.free(old);
            cfg.background = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "cursor-color")) {
            if (cfg.cursor_color) |old| alloc.free(old);
            cfg.cursor_color = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "cursor-text")) {
            if (cfg.cursor_text) |old| alloc.free(old);
            cfg.cursor_text = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "selection-background")) {
            if (cfg.selection_bg) |old| alloc.free(old);
            cfg.selection_bg = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "selection-foreground")) {
            if (cfg.selection_fg) |old| alloc.free(old);
            cfg.selection_fg = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "theme")) {
            if (theme_name) |tn| {
                if (tn.*) |old| alloc.free(old);
                tn.* = alloc.dupe(u8, clean_val) catch null;
            }
        } else if (std.mem.eql(u8, key, "palette")) {
            // Format: "N=#rrggbb" or "N=rrggbb"
            const sep = std.mem.indexOf(u8, clean_val, "=") orelse continue;
            const idx_str = std.mem.trim(u8, clean_val[0..sep], " \t");
            const color = std.mem.trim(u8, clean_val[sep + 1 ..], " \t");
            const idx = std.fmt.parseInt(u8, idx_str, 10) catch continue;
            if (idx < 16) {
                if (cfg.palette[idx]) |old| alloc.free(old);
                cfg.palette[idx] = alloc.dupe(u8, color) catch null;
            }
        }
    }
}

fn resolveTheme(alloc: Allocator, home: []const u8, name: []const u8, cfg: *TerminalConfig) !void {
    // Theme files use the same key=value format as config files.
    // "User wins" semantics: only set fields that are still null.

    var theme_file: ?std.fs.File = null;

    // Try user config dir
    {
        const path = try std.fmt.allocPrint(alloc, "{s}/.config/ghostty/themes/{s}", .{ home, name });
        defer alloc.free(path);
        theme_file = std.fs.openFileAbsolute(path, .{}) catch null;
    }

    // Try macOS Application Support
    if (theme_file == null) {
        const path = try std.fmt.allocPrint(alloc, "{s}/Library/Application Support/com.mitchellh.ghostty/themes/{s}", .{ home, name });
        defer alloc.free(path);
        theme_file = std.fs.openFileAbsolute(path, .{}) catch null;
    }

    // Try XDG_CONFIG_HOME
    if (theme_file == null) {
        if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
            const path = try std.fmt.allocPrint(alloc, "{s}/ghostty/themes/{s}", .{ xdg, name });
            defer alloc.free(path);
            theme_file = std.fs.openFileAbsolute(path, .{}) catch null;
        }
    }

    // Try bundled themes relative to the binary
    if (theme_file == null) {
        var exe_buf: [4096]u8 = undefined;
        if (std.fs.selfExePath(&exe_buf)) |exe_path| {
            const exe_dir = std.fs.path.dirname(exe_path) orelse "";
            const path = try std.fmt.allocPrint(alloc, "{s}/../share/ghostty/themes/{s}", .{ exe_dir, name });
            defer alloc.free(path);
            theme_file = std.fs.openFileAbsolute(path, .{}) catch null;
        } else |_| {}
    }

    // Try ghostty submodule zig-out path relative to cwd
    if (theme_file == null) {
        const cwd = std.fs.cwd();
        // Try a few relative paths
        const rel_paths = [_][]const u8{
            "ghostty/zig-out/share/ghostty/themes",
            "../ghostty/zig-out/share/ghostty/themes",
        };
        for (rel_paths) |rel| {
            var dir = cwd.openDir(rel, .{}) catch continue;
            defer dir.close();
            theme_file = dir.openFile(name, .{}) catch null;
            if (theme_file != null) break;
        }
    }

    const file = theme_file orelse return error.ThemeNotFound;
    defer file.close();

    const contents = file.readToEndAlloc(alloc, 1024 * 1024) catch return error.ReadFailed;
    defer alloc.free(contents);

    // Parse theme contents, applying "user wins" semantics:
    // only set fields that are still null.
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
        const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
        if (value.len == 0) continue;
        const clean_val = stripQuotes(value);

        // Only set if not already set by user config ("user wins")
        if (std.mem.eql(u8, key, "foreground")) {
            if (cfg.foreground == null) cfg.foreground = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "background")) {
            if (cfg.background == null) cfg.background = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "cursor-color")) {
            if (cfg.cursor_color == null) cfg.cursor_color = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "cursor-text")) {
            if (cfg.cursor_text == null) cfg.cursor_text = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "selection-background")) {
            if (cfg.selection_bg == null) cfg.selection_bg = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "selection-foreground")) {
            if (cfg.selection_fg == null) cfg.selection_fg = alloc.dupe(u8, clean_val) catch null;
        } else if (std.mem.eql(u8, key, "palette")) {
            const sep = std.mem.indexOf(u8, clean_val, "=") orelse continue;
            const idx_str = std.mem.trim(u8, clean_val[0..sep], " \t");
            const color = std.mem.trim(u8, clean_val[sep + 1 ..], " \t");
            const idx = std.fmt.parseInt(u8, idx_str, 10) catch continue;
            if (idx < 16) {
                if (cfg.palette[idx] == null) cfg.palette[idx] = alloc.dupe(u8, color) catch null;
            }
        }
    }
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    if (s.len >= 2 and s[0] == '\'' and s[s.len - 1] == '\'') return s[1 .. s.len - 1];
    return s;
}

/// Serialize the config to JSON in the provided buffer.
/// Returns the slice of `buf` that was written.
pub fn toJson(cfg: *const TerminalConfig, buf: []u8) ![]const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const w = stream.writer();

    try w.writeByte('{');
    var first = true;

    if (cfg.font_family) |v| {
        try writeJsonField(w, &first, "fontFamily", v);
    }
    if (cfg.font_size) |v| {
        if (!first) try w.writeAll(",");
        first = false;
        try w.print("\"fontSize\":{d}", .{v});
    }
    if (cfg.cursor_style) |v| {
        try writeJsonField(w, &first, "cursorStyle", v);
    }
    if (cfg.cursor_blink) |v| {
        if (!first) try w.writeAll(",");
        first = false;
        try w.print("\"cursorBlink\":{s}", .{if (v) "true" else "false"});
    }
    if (cfg.scrollback_limit) |v| {
        if (!first) try w.writeAll(",");
        first = false;
        try w.print("\"scrollback\":{d}", .{v});
    }
    if (cfg.web_renderer) |v| {
        try writeJsonField(w, &first, "renderer", v);
    }

    // Theme object with colors
    const has_theme = cfg.foreground != null or cfg.background != null or
        cfg.cursor_color != null or cfg.cursor_text != null or
        cfg.selection_bg != null or cfg.selection_fg != null or
        hasAnyPalette(&cfg.palette);

    if (has_theme) {
        if (!first) try w.writeAll(",");
        first = false;
        try w.writeAll("\"theme\":{");
        var tfirst = true;

        if (cfg.foreground) |v| try writeJsonField(w, &tfirst, "foreground", v);
        if (cfg.background) |v| try writeJsonField(w, &tfirst, "background", v);
        if (cfg.cursor_color) |v| try writeJsonField(w, &tfirst, "cursor", v);
        if (cfg.cursor_text) |v| try writeJsonField(w, &tfirst, "cursorAccent", v);
        if (cfg.selection_bg) |v| try writeJsonField(w, &tfirst, "selectionBackground", v);
        if (cfg.selection_fg) |v| try writeJsonField(w, &tfirst, "selectionForeground", v);

        for (cfg.palette, 0..) |color, i| {
            if (color) |v| {
                try writeJsonField(w, &tfirst, palette_names[i], v);
            }
        }

        try w.writeByte('}');
    }

    try w.writeByte('}');
    return stream.getWritten();
}

fn writeJsonField(w: anytype, first: *bool, key: []const u8, value: []const u8) !void {
    if (!first.*) try w.writeAll(",");
    first.* = false;
    try w.print("\"{s}\":\"{s}\"", .{ key, value });
}

fn hasAnyPalette(palette: *const [16]?[]const u8) bool {
    for (palette) |c| {
        if (c != null) return true;
    }
    return false;
}
