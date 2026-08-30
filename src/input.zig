// input.zig — Unified keyboard + Xbox gamepad input abstraction
//
// Ported from zigsteroids input.zig, generalized to work with game-defined
// action enums via binding tables.
//
// On Linux, supports two input paths:
//   1. raylib mapped (GLFW + SDL GameControllerDB mappings)
//   2. Raw joydev (/dev/input/js*) — fallback when GLFW lacks a mapping
//
// On non-Linux, only the raylib mapped path is used.
//
// Game actions are abstracted behind an enum so the game logic never
// needs to know whether input came from keyboard or gamepad.

const std = @import("std");
const rl = @import("raylib");
const builtin = @import("builtin");

const is_linux = builtin.os.tag == .linux;

// ── Analog stick deadzone and trigger threshold ────────────────────
const STICK_DEADZONE: f32 = 0.15;
const TRIGGER_THRESHOLD: f32 = 0.1;

// ── Linux joystick ioctl constants (precomputed for x86_64) ────────
const JSIOCGAXES: u32 = 0x80016a11;
const JSIOCGBUTTONS: u32 = 0x80016a12;
const JSIOCGNAME: u32 = 0x80806a80;

const JS_EVENT_BUTTON: u8 = 0x01;
const JS_EVENT_AXIS: u8 = 0x02;
const JS_EVENT_INIT: u8 = 0x80;

const js_event = extern struct {
    time: u32,
    value: i16,
    type: u8,
    number: u8,
};

// ── Map raw js0 button index to raylib GamepadButton ────────────────
const JS_BTN_MAP = [32]rl.GamepadButton{
    .right_face_down, // 0  A
    .right_face_right, // 1  B
    .right_face_left, // 2  X
    .right_face_up, // 3  Y
    .left_trigger_1, // 4  LB
    .right_trigger_1, // 5  RB
    .middle_left, // 6  Back
    .middle_right, // 7  Start
    .middle, // 8  Guide
    .left_thumb, // 9  LS
    .right_thumb, // 10 RS
    .unknown, // 11
    .unknown, .unknown, .unknown, .unknown,
    .unknown, .unknown, .unknown, .unknown,
    .unknown, .unknown, .unknown, .unknown,
    .unknown, .unknown, .unknown, .unknown,
    .unknown, .unknown, .unknown, .unknown,
};

// ── Gamepad mapping strings for GLFW's mapped path ─────────────────
const GAMEPAD_MAPPINGS: [:0]const u8 =
    \\030000005e0400008e02000000010000,Microsoft Xbox 360 Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\030000005e040000d102000001010000,Microsoft Xbox One Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\030000005e040000ea02000000000000,Microsoft Xbox One S Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\050000005e040000e002000003090000,Microsoft Xbox One S Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\060000005e040000120b000000000000,Microsoft Xbox Series X|S Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,misc1:b11,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\050000005e040000120b000000000000,Microsoft Xbox Series X|S Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,misc1:b11,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\030000005e040000120b000000000000,Microsoft Xbox Series X|S Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,misc1:b11,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,platform:Linux,
    \\
;

// ── Raw joystick state (bypasses GLFW gamepad mapping) ─────────────
const RawJoystick = if (is_linux) struct {
    fd: ?std.posix.fd_t,
    axes: [8]f32,
    buttons: [32]bool,
    dpad_up: bool,
    dpad_down: bool,
    dpad_left: bool,
    dpad_right: bool,
    name: [128]u8,
    name_len: usize,
    axis_count: u8,
    button_count: u8,
    active: bool,

    fn init() RawJoystick {
        return .{
            .fd = null,
            .axes = @splat(0),
            .buttons = @splat(false),
            .dpad_up = false,
            .dpad_down = false,
            .dpad_left = false,
            .dpad_right = false,
            .name = @splat(0),
            .name_len = 0,
            .axis_count = 0,
            .button_count = 0,
            .active = false,
        };
    }

    fn open(self: *RawJoystick, path: [:0]const u8) bool {
        const fd = std.posix.open(path, std.posix.O{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0) catch return false;
        self.fd = fd;

        self.axis_count = 0;
        self.button_count = 0;
        _ = std.os.linux.ioctl(fd, JSIOCGAXES, @intFromPtr(&self.axis_count));
        _ = std.os.linux.ioctl(fd, JSIOCGBUTTONS, @intFromPtr(&self.button_count));

        var name_buf: [128]u8 = @splat(0);
        const name_rc = std.os.linux.ioctl(fd, JSIOCGNAME, @intFromPtr(&name_buf));
        if (name_rc >= 0) {
            const len: usize = @intCast(name_rc);
            @memcpy(self.name[0..@min(len, 127)], name_buf[0..@min(len, 127)]);
            self.name_len = @min(len, 127);
        } else {
            self.name_len = 0;
        }
        self.name[self.name_len] = 0;

        self.axes = @splat(0);
        self.buttons = @splat(false);
        self.active = true;

        self.poll();
        return true;
    }

    fn close(self: *RawJoystick) void {
        if (self.fd) |fd| {
            std.posix.close(fd);
            self.fd = null;
        }
        self.active = false;
        self.dpad_up = false;
        self.dpad_down = false;
        self.dpad_left = false;
        self.dpad_right = false;
    }

    fn nameSlice(self: *const RawJoystick) [:0]const u8 {
        return self.name[0..self.name_len :0];
    }

    fn poll(self: *RawJoystick) void {
        if (self.fd == null) return;
        const fd = self.fd.?;
        while (true) {
            var ev: js_event = undefined;
            const rc = std.posix.read(fd, std.mem.asBytes(&ev)) catch |err| switch (err) {
                error.WouldBlock => return,
                else => {
                    self.close();
                    return;
                },
            };
            if (rc < @sizeOf(js_event)) return;
            const ev_type = ev.type & ~JS_EVENT_INIT;
            if (ev_type == JS_EVENT_BUTTON) {
                if (ev.number < 32) {
                    self.buttons[ev.number] = ev.value != 0;
                }
            } else if (ev_type == JS_EVENT_AXIS) {
                if (ev.number < 8) {
                    self.axes[ev.number] = @as(f32, @floatFromInt(ev.value)) / 32767.0;
                    if (ev.number == 6) {
                        self.dpad_left = ev.value < 0;
                        self.dpad_right = ev.value > 0;
                    }
                    if (ev.number == 7) {
                        self.dpad_up = ev.value < 0;
                        self.dpad_down = ev.value > 0;
                    }
                }
            }
        }
    }
} else struct {
    axes: [8]f32 = @splat(0),
    buttons: [32]bool = @splat(false),
    dpad_up: bool = false,
    dpad_down: bool = false,
    dpad_left: bool = false,
    dpad_right: bool = false,
    name: [128]u8 = @splat(0),
    name_len: usize = 0,
    axis_count: u8 = 0,
    button_count: u8 = 0,
    active: bool = false,

    fn init() RawJoystick {
        return .{};
    }
    fn open(self: *RawJoystick, path: [:0]const u8) bool {
        _ = self;
        _ = path;
        return false;
    }
    fn close(self: *RawJoystick) void {
        _ = self;
    }
    fn nameSlice(self: *const RawJoystick) [:0]const u8 {
        return self.name[0..0 :0];
    }
    fn poll(self: *RawJoystick) void {
        _ = self;
    }
};

// ── Binding definitions ───────────────────────────────────────────

pub const KeyBinding = struct {
    key: rl.KeyboardKey,
    /// If true, edge-triggered (isKeyPressed). If false, continuous (isKeyDown).
    edge: bool = false,
};

pub const GamepadBinding = struct {
    button: ?rl.GamepadButton = null,
    trigger: ?rl.GamepadAxis = null,
    threshold: f32 = 0.1,
    edge: bool = false,
};

pub const InputBindings = struct {
    /// Keyboard bindings, indexed by @intFromEnum(Action).
    keyboard: []const ?KeyBinding,
    /// Gamepad bindings, indexed by @intFromEnum(Action).
    gamepad: []const ?GamepadBinding,
};

// ── InputManager ───────────────────────────────────────────────────

pub const InputManager = struct {
    bindings: *const InputBindings,
    raw_js: RawJoystick,
    raw_js_open: bool = false,
    use_raw: bool = false,
    detection_done: bool = false,
    connected: bool = false,
    action_count: usize,
    cur_actions: []bool,
    prev_actions: []bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bindings: *const InputBindings, action_count: usize) InputManager {
        _ = rl.setGamepadMappings(GAMEPAD_MAPPINGS);

        var self = InputManager{
            .bindings = bindings,
            .raw_js = RawJoystick.init(),
            .action_count = action_count,
            .cur_actions = allocator.alloc(bool, action_count) catch unreachable,
            .prev_actions = allocator.alloc(bool, action_count) catch unreachable,
            .allocator = allocator,
        };
        @memset(self.cur_actions, false);
        @memset(self.prev_actions, false);

        if (is_linux) {
            var js_buf: [32]u8 = undefined;
            for (0..4) |i| {
                const path = std.fmt.bufPrintZ(&js_buf, "/dev/input/js{d}", .{i}) catch break;
                if (self.raw_js.open(path)) {
                    self.raw_js_open = true;
                    break;
                }
            }
        }

        return self;
    }

    pub fn deinit(self: *InputManager) void {
        if (is_linux and self.raw_js_open) self.raw_js.close();
        self.allocator.free(self.cur_actions);
        self.allocator.free(self.prev_actions);
    }

    /// Poll all input sources. Call exactly once per frame.
    pub fn update(self: *InputManager) void {
        @memcpy(self.prev_actions, self.cur_actions);

        if (is_linux and self.raw_js_open) {
            self.raw_js.poll();
            if (!self.raw_js.active) self.raw_js_open = false;
        }

        self.detectMode();
        self.connected = if (self.use_raw) self.raw_js.active else rl.isGamepadAvailable(0);

        for (0..self.action_count) |i| {
            self.cur_actions[i] = self.checkGamepadAction(i);
        }
    }

    /// Check if an action is currently held down (continuous).
    pub fn isDown(self: *const InputManager, action: usize) bool {
        return self.cur_actions[action] or self.keyboardKeyDown(action);
    }

    /// Check if an action was just pressed this frame (edge-triggered).
    pub fn isPressed(self: *const InputManager, action: usize) bool {
        return (self.cur_actions[action] and !self.prev_actions[action]) or
            self.keyboardKeyPressed(action);
    }

    /// Analog rotation amount: -1.0 (full left) to +1.0 (full right).
    /// Keyboard returns -1, 0, or 1 (digital).
    /// Gamepad left stick X returns analog value (with dead zone).
    /// Gamepad D-pad left/right returns -1 or 1 (digital fallback).
    pub fn rotationAmount(self: *const InputManager) f32 {
        var val: f32 = 0;

        if (rl.isKeyDown(.left)) val -= 1.0;
        if (rl.isKeyDown(.right)) val += 1.0;

        if (self.connected) {
            const lx = self.gamepadAxis(.left_x);
            if (@abs(lx) > STICK_DEADZONE) {
                val = lx;
            }
            if (self.gamepadButtonDown(.left_face_left)) val -= 1.0;
            if (self.gamepadButtonDown(.right_face_right)) val += 1.0;
        }

        return @max(-1.0, @min(1.0, val));
    }

    pub fn isGamepadConnected(self: *const InputManager) bool {
        return self.connected;
    }

    pub fn gamepadName(self: *const InputManager) [:0]const u8 {
        if (!self.connected) return "";
        if (self.use_raw) return self.raw_js.nameSlice();
        return rl.getGamepadName(0);
    }

    // ── Private: auto-detection ──

    fn detectMode(self: *InputManager) void {
        if (self.detection_done) return;

        if (is_linux and self.raw_js_open and rl.isGamepadAvailable(0)) {
            var raw_has_input = false;
            for (0..@min(self.raw_js.button_count, 32)) |b| {
                if (self.raw_js.buttons[b]) {
                    raw_has_input = true;
                    break;
                }
            }
            var rl_has_input = false;
            for (1..18) |b| {
                const btn: rl.GamepadButton = @enumFromInt(b);
                if (rl.isGamepadButtonDown(0, btn)) {
                    rl_has_input = true;
                    break;
                }
            }
            if (raw_has_input and !rl_has_input) {
                self.use_raw = true;
                self.detection_done = true;
            } else if (rl_has_input) {
                self.use_raw = false;
                self.detection_done = true;
            }
        }

        if (is_linux and self.raw_js_open and !rl.isGamepadAvailable(0)) {
            self.use_raw = true;
            self.detection_done = true;
        }
    }

    // ── Private: gamepad button/axis reading ──

    fn gamepadButtonDown(self: *const InputManager, btn: rl.GamepadButton) bool {
        if (!self.connected) return false;

        if (self.use_raw) {
            const js = &self.raw_js;
            if (btn == .left_face_up) return js.dpad_up;
            if (btn == .left_face_down) return js.dpad_down;
            if (btn == .left_face_left) return js.dpad_left;
            if (btn == .left_face_right) return js.dpad_right;
            const btn_int: i32 = @intFromEnum(btn);
            for (JS_BTN_MAP, 0..) |mapped, i| {
                if (@intFromEnum(mapped) == btn_int and i < js.button_count) {
                    return js.buttons[i];
                }
            }
            return false;
        } else {
            return rl.isGamepadButtonDown(0, btn);
        }
    }

    fn gamepadAxis(self: *const InputManager, axis: rl.GamepadAxis) f32 {
        if (!self.connected) return 0.0;

        if (self.use_raw) {
            return switch (axis) {
                .left_x => self.raw_js.axes[0],
                .left_y => self.raw_js.axes[1],
                .right_x => self.raw_js.axes[3],
                .right_y => self.raw_js.axes[4],
                .left_trigger => (self.raw_js.axes[2] + 1.0) / 2.0,
                .right_trigger => (self.raw_js.axes[5] + 1.0) / 2.0,
            };
        } else {
            return rl.getGamepadAxisMovement(0, axis);
        }
    }

    fn checkGamepadAction(self: *const InputManager, action_idx: usize) bool {
        if (action_idx >= self.bindings.gamepad.len) return false;
        const gp = self.bindings.gamepad[action_idx];
        if (gp == null) return false;
        const b = gp.?;
        if (b.button) |btn| {
            return self.gamepadButtonDown(btn);
        }
        if (b.trigger) |axis| {
            return self.gamepadAxis(axis) > b.threshold;
        }
        return false;
    }

    fn keyboardKeyDown(self: *const InputManager, action_idx: usize) bool {
        if (action_idx >= self.bindings.keyboard.len) return false;
        const kb = self.bindings.keyboard[action_idx];
        if (kb == null) return false;
        const b = kb.?;
        if (b.edge) return false;
        return rl.isKeyDown(b.key);
    }

    fn keyboardKeyPressed(self: *const InputManager, action_idx: usize) bool {
        if (action_idx >= self.bindings.keyboard.len) return false;
        const kb = self.bindings.keyboard[action_idx];
        if (kb == null) return false;
        const b = kb.?;
        if (!b.edge) return false;
        return rl.isKeyPressed(b.key);
    }
};