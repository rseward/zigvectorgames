// render.zig — RenderContext: vector drawing primitives with letterbox camera
//
// The RenderContext is created by App.beginRender() each frame. It sets up
// a Camera2D for letterbox centering (via screen.offset), and provides
// vector drawing methods that operate in design-space coordinates.
//
// Usage:
//   const ctx = app.beginRender();
//   defer ctx.end();
//   ctx.drawLines(pos, scale, rot, &points, true, .white);
//   ctx.drawNumber(score, pos);
//   ctx.drawCircle(pos, radius, .green);

const std = @import("std");
const rl = @import("raylib");
const rlm = rl.math;
const Vector2 = rl.Vector2;
const Screen = @import("screen.zig").Screen;
const text = @import("text.zig");

pub const DEFAULT_THICKNESS: f32 = 2.5;

/// Current render_scale for thickness scaling. Set by App.beginRender()
/// each frame so drawLinesRaw can scale line thickness proportionally.
var current_render_scale: f32 = 1.0;

pub fn setRenderScale(s: f32) void {
    current_render_scale = s;
}

pub const RenderContext = struct {
    screen: *Screen,
    camera: rl.Camera2D,
    ended: bool = false,

    /// End rendering — calls camera.end() and rl.endDrawing().
    /// Normally called via `defer ctx.end()`.
    pub fn end(self: *RenderContext) void {
        if (self.ended) return;
        self.ended = true;
        self.camera.end();
        rl.endDrawing();
    }

    /// Draw connected line segments with transformation (translate, scale, rotate).
    /// `points` are in design-space (unit-scale), transformed by org/scale/rot.
    /// `connect` = true closes the polygon (last point connects to first).
    pub fn drawLines(
        self: *const RenderContext,
        org: Vector2,
        scale: f32,
        rot: f32,
        points: []const Vector2,
        connect: bool,
        color: rl.Color,
    ) void {
        _ = self;
        drawLinesRaw(org, scale, rot, points, connect, color);
    }

    /// Draw a number using vector line segments (7-segment style digits).
    pub fn drawNumber(self: *const RenderContext, n: usize, pos: Vector2) void {
        text.drawNumber(n, pos, self.screen.scale, rl.Color.white, drawLinesRaw);
    }

    /// Draw a number with a specific color.
    pub fn drawNumberColored(self: *const RenderContext, n: usize, pos: Vector2, color: rl.Color) void {
        text.drawNumber(n, pos, self.screen.scale, color, drawLinesRaw);
    }

    /// Draw a filled circle.
    pub fn drawCircle(self: *const RenderContext, pos: Vector2, radius: f32, color: rl.Color) void {
        _ = self;
        rl.drawCircleV(pos, radius, color);
    }

    /// Draw circle outline (lines only).
    pub fn drawCircleLines(self: *const RenderContext, pos: Vector2, radius: f32, color: rl.Color) void {
        _ = self;
        rl.drawCircleLinesV(pos, radius, color);
    }

    /// Draw a filled rectangle.
    pub fn drawRect(self: *const RenderContext, rect: rl.Rectangle, color: rl.Color) void {
        _ = self;
        rl.drawRectangleRec(rect, color);
    }

    /// Draw rectangle outline. Thickness is in pixels (f32).
    pub fn drawRectLines(self: *const RenderContext, rect: rl.Rectangle, thickness: f32, color: rl.Color) void {
        _ = self;
        rl.drawRectangleLinesEx(rect, thickness, color);
    }

    /// Draw bitmap text (raylib default font).
    pub fn drawText(self: *const RenderContext, text_str: [:0]const u8, x: i32, y: i32, font_size: i32, color: rl.Color) void {
        _ = self;
        rl.drawText(text_str, x, y, font_size, color);
    }

    /// Draw a polyline at actual screen coordinates (no design-space transform).
    /// Useful for terrain and other pre-positioned geometry.
    pub fn drawPolyline(self: *const RenderContext, points: []const Vector2, thickness: f32, color: rl.Color) void {
        _ = self;
        if (points.len < 2) return;
        for (0..points.len - 1) |i| {
            rl.drawLineEx(points[i], points[i + 1], thickness, color);
        }
    }

    /// Draw a single line from a to b.
    pub fn drawLine(self: *const RenderContext, a: Vector2, b: Vector2, thickness: f32, color: rl.Color) void {
        _ = self;
        rl.drawLineEx(a, b, thickness, color);
    }

    // ── Design-space percentage helpers ───────────────────────────
    // Games can express positions and sizes as percentages of the design
    // resolution (0.0–1.0). These convert to design-space pixels.
    // e.g. ctx.pct(0.5, 0.25) returns the point at 50% width, 25% height.

    /// Convert a percentage position (0.0–1.0) to design-space pixels.
    pub fn pct(self: *const RenderContext, px: f32, py: f32) Vector2 {
        return .{
            .x = px * self.screen.design_size.x,
            .y = py * self.screen.design_size.y,
        };
    }

    /// Convert a percentage of the field width to design-space pixels.
    pub fn pctW(self: *const RenderContext, pw: f32) f32 {
        return pw * self.screen.design_size.x;
    }

    /// Convert a percentage of the field height to design-space pixels.
    pub fn pctH(self: *const RenderContext, ph: f32) f32 {
        return ph * self.screen.design_size.y;
    }

    /// Scale a size value relative to the field (uses the smaller dimension
    /// so it stays proportional on any aspect ratio).
    pub fn pctS(self: *const RenderContext, ps: f32) f32 {
        return ps * @min(self.screen.design_size.x, self.screen.design_size.y);
    }
};

/// Raw drawLines without RenderContext — used as callback for text.drawNumber.
pub fn drawLinesRaw(org: Vector2, scale: f32, rot: f32, points: []const Vector2, connect: bool, color: rl.Color) void {
    const Transformer = struct {
        org: Vector2,
        scale: f32,
        rot: f32,
        fn apply(self_ctx: @This(), p: Vector2) Vector2 {
            return rlm.vector2Add(
                rlm.vector2Scale(rlm.vector2Rotate(p, self_ctx.rot), self_ctx.scale),
                self_ctx.org,
            );
        }
    };
    const t = Transformer{ .org = org, .scale = scale, .rot = rot };
    const thickness = DEFAULT_THICKNESS * current_render_scale;
    const bound = if (connect) points.len else (points.len - 1);
    for (0..bound) |i| {
        rl.drawLineEx(t.apply(points[i]), t.apply(points[(i + 1) % points.len]), thickness, color);
    }
}