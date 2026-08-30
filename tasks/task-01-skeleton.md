# Task 01: Create vgame package skeleton

Create the vgame library directory with build files that compile against raylib-zig.

Files:
- build.zig, build.zig.zon, src/vgame.zig (stub), README.md

The build exposes vgame as a module that re-exports raylib-zig. Games link
against vgame and get raylib through it. Uses the same raylib-zig commit
as zigsteroids: a4d18b2d1cf8fdddec68b5b084535fca0475f466.

Build options: linux_display_backend, opengl_version, sysroot (same as zigsteroids).