// screen.zig — Screen scaling and letterboxing
//
// Games define a design resolution (e.g. 1280x960) and base scale (e.g. 38.0).
// All game logic operates in design-space coordinates — positions, collisions,
// spawning, everything uses the fixed design_size. The platform scales the
// render to fit the actual window via a Camera2D zoom (see App.beginRender).
//
// At runtime, Screen computes:
//   render_scale — uniform scale from design-space to screen pixels
//   offset       — pixel offset to center the letterboxed playfield
//
// Games should always use `screen.size` (= design_size) and `screen.scale`
// (= base_scale). These are constants regardless of window size.

const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const Screen = struct {
    design_size: Vector2,
    base_scale: f32,
    /// Playfield size in design-space (always equals design_size).
    /// Games use this for all positioning, collision, and spawning.
    size: Vector2,
    /// Vector drawing scale in design-space (always equals base_scale).
    scale: f32,
    /// Scale factor from design-space to actual screen pixels.
    /// Used by Camera2D zoom and for scaling thickness/font_size.
    render_scale: f32 = 1.0,
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

    /// Recalculate render_scale and offset from the actual window dimensions.
    /// size and scale stay constant (always design-space values).
    /// Call after window creation, fullscreen toggle, and every frame
    /// (to catch runtime size changes from the compositor).
    pub fn update(self: *Screen) void {
        const w = rl.getScreenWidth();
        const h = rl.getScreenHeight();
        if (w <= 0 or h <= 0) return;
        self.screen_w = w;
        self.screen_h = h;

        // Uniform scale: the smaller of the x/y ratios against the design size.
        self.render_scale = @min(
            @as(f32, @floatFromInt(w)) / self.design_size.x,
            @as(f32, @floatFromInt(h)) / self.design_size.y,
        );

        // Center the letterboxed playfield on the actual screen.
        const scaled_w = self.design_size.x * self.render_scale;
        const scaled_h = self.design_size.y * self.render_scale;
        self.offset = .{
            .x = (@as(f32, @floatFromInt(w)) - scaled_w) / 2.0,
            .y = (@as(f32, @floatFromInt(h)) - scaled_h) / 2.0,
        };
    }

    /// True if the window dimensions changed since last update.
    pub fn changed(self: *const Screen) bool {
        return rl.getScreenWidth() != self.screen_w or
            rl.getScreenHeight() != self.screen_h;
    }
};