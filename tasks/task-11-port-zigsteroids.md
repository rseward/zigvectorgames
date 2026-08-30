# Task 11: Port zigsteroids to use vgame

Refactor zigsteroids to depend on vgame. Keep only game-specific logic in main.zig.

Changes:
- build.zig.zon: add vgame dependency (path = "../zigvectorgame")
- build.zig: replace raylib_zig dep with vgame dep, link raylib through it
- src/actions.zig: game-specific Action enum + keyboard/gamepad binding arrays
- src/main.zig: remove drawLines, drawNumber, getMyColor, updateScreenSize,
  Sound struct, input.zig import, window setup, camera setup. Use vgame imports.
- Delete src/input.zig (replaced by vgame input manager)

main.zig shrinks from ~1535 to ~600 lines (entities + game logic + game rendering).