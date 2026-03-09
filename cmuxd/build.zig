const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Link ghostty-vt for server-side terminal state tracking
    if (b.lazyDependency("ghostty", .{})) |dep| {
        exe_mod.addImport("ghostty-vt", dep.module("ghostty-vt"));
    }

    const exe = b.addExecutable(.{
        .name = "cmuxd",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run cmuxd");
    run_step.dependOn(&run_cmd.step);

    // cmux-bridge: proxies terminal I/O through cmuxd WebSocket
    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("src/bridge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const bridge = b.addExecutable(.{
        .name = "cmux-bridge",
        .root_module = bridge_mod,
    });
    b.installArtifact(bridge);
}
