// screen.zig — Screen scaling and letterboxing
//
// Replaces zigsteroids globals: SCALE, SIZE, RENDER_OFFSET, DESIGN_SIZE, BASE_SCALE.
// Games define a design resolution (e.g. 1280x960) and base scale (e.g. 38.0).
// At runtime, Screen computes the largest letterboxed playfield that fits the
// actual window, and a scale factor so vector graphics stay proportional.

const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const Screen = struct {
    design_size: Vector2,
    base_scale: f32,
    /// Runtime playfield size (letterboxed to preserve design aspect ratio).
    size: Vector2,
    /// Runtime vector scale (derived from base_scale and render_scale).
    scale: f32,
    /// Pixel offset to center the letterboxed playfield on screen.
    offset: Vector2,
    screen_w: i32 = 0,
    screen_h: i32 = 0,

    pub fn init(design_size: Vector2, base_scale: f32) Screen {
        return .{
            .design_size = design_size,
            .base_scale = base_scale,
            .size = design_size,
            .scale = base_scale,
            .offset = .{ .x = 0, .y = 0 },
        };
    }

    /// Recalculate size/scale/offset from the actual window dimensions.
    /// Call after window creation, fullscreen toggle, and every frame
    /// (to catch runtime size changes from the compositor).
    pub fn update(self: *Screen) void {
        const w = rl.getScreenWidth();
        const h = rl.getScreenHeight();
        if (w <= 0 or h <= 0) return;
        self.screen_w = w;
        self.screen_h = h;

        // Uniform scale: the smaller of the x/y ratios against the design size.
        const render_scale = @min(
            @as(f32, @floatFromInt(w)) / self.design_size.x,
            @as(f32, @floatFromInt(h)) / self.design_size.y,
        );

        self.size = .{
            .x = self.design_size.x * render_scale,
            .y = self.design_size.y * render_scale,
        };
        self.scale = self.base_scale * render_scale;

        // Center the field; surrounding area stays black (cleared by caller).
        self.offset = .{
            .x = (@as(f32, @floatFromInt(w)) - self.size.x) / 2.0,
            .y = (@as(f32, @floatFromInt(h)) - self.size.y) / 2.0,
        };
    }

    /// True if the window dimensions changed since last update.
    pub fn changed(self: *const Screen) bool {
        return rl.getScreenWidth() != self.screen_w or
            rl.getScreenHeight() != self.screen_h;
    }
};