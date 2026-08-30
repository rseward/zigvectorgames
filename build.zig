const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sysroot = b.option([]const u8, "sysroot", "Sysroot directory for cross-compilation") orelse "";

    const DisplayBackend = enum { x11, wayland, both };
    const display_backend = b.option(DisplayBackend, "linux_display_backend", "Linux display backend: x11, wayland, or both") orelse .x11;
    const rl_display_backend: []const u8 = switch (display_backend) {
        .x11 => "X11",
        .wayland => "Wayland",
        .both => "Both",
    };

    const OpenglVersion = enum { auto, gl_1_1, gl_2_1, gl_3_3, gl_4_3, gles_2, gles_3 };
    const opengl_version = b.option(OpenglVersion, "opengl_version", "OpenGL API version (auto = desktop GL)") orelse .auto;
    const rl_opengl_version: []const u8 = switch (opengl_version) {
        .auto => "auto",
        .gl_1_1 => "gl_1_1",
        .gl_2_1 => "gl_2_1",
        .gl_3_3 => "gl_3_3",
        .gl_4_3 => "gl_4_3",
        .gles_2 => "gles_2",
        .gles_3 => "gles_3",
    };

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = rl_display_backend,
        .opengl_version = rl_opengl_version,
    });
    const raylib_mod = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    if (opengl_version == .gles_2 or opengl_version == .gles_3) {
        raylib_artifact.root_module.linkSystemLibrary("GLESv2", .{});
    }

    // vgame module — imports raylib internally, re-exports it to dependents
    const vgame_mod = b.addModule("vgame", .{
        .root_source_file = b.path("src/vgame.zig"),
        .target = target,
        .optimize = optimize,
    });
    vgame_mod.addImport("raylib", raylib_mod);

    // Install the raylib artifact so dependents can access it via
    // `vgame_dep.artifact("raylib")`.
    b.installArtifact(raylib_artifact);

    // Sysroot handling (same as zigsteroids)
    if (sysroot.len > 0) {
        const multiarch = std.fmt.allocPrint(b.allocator, "{s}-{s}-{s}", .{
            @tagName(target.result.cpu.arch),
            @tagName(target.result.os.tag),
            @tagName(target.result.abi),
        }) catch unreachable;

        const lib_dirs = [_][]const u8{
            b.pathJoin(&.{ "usr/lib", multiarch }),
            "usr/lib",
            b.pathJoin(&.{ "lib", multiarch }),
            "lib",
            "usr/lib64",
            "lib64",
        };
        const inc_dirs = [_][]const u8{
            "usr/include",
            b.pathJoin(&.{ "usr/include", multiarch }),
        };

        for (lib_dirs) |d| {
            const p = b.pathJoin(&.{ sysroot, d });
            raylib_artifact.root_module.addLibraryPath(.{ .cwd_relative = p });
            vgame_mod.addLibraryPath(.{ .cwd_relative = p });
        }
        for (inc_dirs) |d| {
            const p = b.pathJoin(&.{ sysroot, d });
            raylib_artifact.root_module.addSystemIncludePath(.{ .cwd_relative = p });
            vgame_mod.addSystemIncludePath(.{ .cwd_relative = p });
        }
    }
}