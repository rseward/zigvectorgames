// config.zig — Configuration structs for App initialization

const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const AppConfig = struct {
    title: [:0]const u8 = "vgame",
    design_size: Vector2 = .{ .x = 1280, .y = 960 },
    base_scale: f32 = 38.0,
    fullscreen: bool = false,
    window_resizable: bool = true,
    target_fps: i32 = 60,
    background_color: rl.Color = rl.Color.black,
    /// Enable MSAA 4x anti-aliasing for smoother vector lines.
    msaa: bool = true,
    /// Enable bloom/glow post-processing. Renders the scene to a
    /// texture, then composites additive blurred copies on top to
    /// produce a soft CRT-vector glow around all bright lines.
    glow: bool = true,
};