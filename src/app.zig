// app.zig — App: main lifecycle manager for vector games
//
// Ties together window creation, screen scaling, audio, and rendering.
// Games create an App, optionally init audio, then run a frame loop.
//
// Usage:
//   var app = try vgame.App.init(allocator, .{ .title = "My Game" });
//   defer app.deinit();
//   try app.initAudio(.{ .clips = &.{"shoot.wav"} });
//   while (app.frame()) {
//       // game logic using app.delta, app.time, app.screen
//       const ctx = app.beginRender();
//       defer ctx.end();
//       ctx.drawLines(...);
//   }

const std = @import("std");
const rl = @import("raylib");
const Screen = @import("screen.zig").Screen;
const RenderContext = @import("render.zig").RenderContext;
const AudioManager = @import("audio.zig").AudioManager;
const AudioConfig = @import("audio.zig").AudioConfig;
const AppConfig = @import("config.zig").AppConfig;

pub const App = struct {
    screen: Screen,
    config: AppConfig,
    delta: f32 = 0,
    time: f32 = 0,
    frame_count: usize = 0,
    audio: ?AudioManager = null,
    allocator: std.mem.Allocator,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: AppConfig) !App {
        if (config.window_resizable) {
            rl.setConfigFlags(.{ .window_resizable = true });
        }

        rl.initWindow(
            @intFromFloat(config.design_size.x),
            @intFromFloat(config.design_size.y),
            config.title,
        );

        if (config.fullscreen) {
            rl.toggleFullscreen();
        } else {
            rl.maximizeWindow();
            const mon = rl.getCurrentMonitor();
            const mw = rl.getMonitorWidth(mon);
            const mh = rl.getMonitorHeight(mon);
            if (mw > 0 and mh > 0) {
                rl.setWindowSize(mw, mh);
            }
        }

        var screen = Screen.init(config.design_size, config.base_scale);
        screen.update();

        rl.setTargetFPS(config.target_fps);

        return .{
            .screen = screen,
            .config = config,
            .allocator = allocator,
            .initialized = true,
        };
    }

    pub fn deinit(self: *App) void {
        if (self.audio) |*a| a.deinit();
        if (self.initialized) rl.closeWindow();
    }

    /// Init audio with the given config. Call after App.init if the game uses sound.
    pub fn initAudio(self: *App, audio_config: AudioConfig) !void {
        self.audio = try AudioManager.init(self.allocator, audio_config);
    }

    /// Called at the top of the frame loop. Returns false when the window
    /// should close. Updates delta time, screen size, and frame counter.
    pub fn frame(self: *App) bool {
        if (rl.windowShouldClose()) return false;

        self.delta = rl.getFrameTime();
        self.time += self.delta;

        if (self.screen.changed()) {
            self.screen.update();
        }

        self.frame_count += 1;
        return true;
    }

    /// Begin rendering. Returns a RenderContext for drawing in design-space.
    /// The context sets up a Camera2D for letterbox centering.
    /// Call `ctx.end()` (via defer) to finish drawing.
    pub fn beginRender(self: *App) RenderContext {
        rl.beginDrawing();
        rl.clearBackground(self.config.background_color);

        const camera = rl.Camera2D{
            .offset = self.screen.offset,
            .target = .{ .x = 0, .y = 0 },
            .rotation = 0,
            .zoom = 1,
        };
        camera.begin();

        return .{
            .screen = &self.screen,
            .camera = camera,
        };
    }
};