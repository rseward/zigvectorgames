// vgame — Vector Game Platform
// Re-exports all sub-modules for convenient single-import usage.
//
// Games import vgame and get: App (lifecycle), RenderContext (vector drawing),
// InputManager (keyboard+gamepad), AudioManager, Particles, overlays, and
// math/collision helpers.

pub const rl = @import("raylib");

pub const App = @import("app.zig").App;
pub const AppConfig = @import("config.zig").AppConfig;
pub const RenderContext = @import("render.zig").RenderContext;
pub const Screen = @import("screen.zig").Screen;
pub const InputManager = @import("input.zig").InputManager;
pub const InputBindings = @import("input.zig").InputBindings;
pub const KeyBinding = @import("input.zig").KeyBinding;
pub const GamepadBinding = @import("input.zig").GamepadBinding;
pub const AudioManager = @import("audio.zig").AudioManager;
pub const AudioConfig = @import("audio.zig").AudioConfig;
pub const Particles = @import("particles.zig").Particles;
pub const ParticleConfig = @import("particles.zig").ParticleConfig;
pub const Palette = @import("color.zig").Palette;
pub const Color = @import("color.zig").Color;
pub const OverlayOptions = @import("overlay.zig").OverlayOptions;
pub const drawOverlay = @import("overlay.zig").drawOverlay;
pub const centeredText = @import("overlay.zig").centeredText;
pub const circleCollision = @import("math.zig").circleCollision;
pub const pointInCircle = @import("math.zig").pointInCircle;
pub const wrapPos = @import("math.zig").wrapPos;
pub const normalize = @import("math.zig").normalize;
pub const scale = @import("math.zig").scale;
pub const add = @import("math.zig").add;
pub const sub = @import("math.zig").sub;
pub const distance = @import("math.zig").distance;
pub const lerpColor = @import("color.zig").lerpColor;
pub const rgba = @import("color.zig").rgba;
pub const Vector2 = rl.Vector2;