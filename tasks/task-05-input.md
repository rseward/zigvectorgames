# Task 05: Implement input.zig

Generalize zigsteroids input.zig (488 lines) to work with game-defined Action enums.

Key changes from zigsteroids:
1. Games define their own Action enum (e.g. .shoot, .thrust, .pause)
2. Binding tables (KeyBinding, GamepadBinding) map actions to keys/buttons
3. InputManager uses @intFromEnum(action) as index into binding arrays
4. Raw joydev path (Linux) and GLFW gamepad mappings ported verbatim

API: init(allocator, bindings, action_count), update(), isDown(action_idx),
isPressed(action_idx), rotationAmount(), isGamepadConnected(), gamepadName()