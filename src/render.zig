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

pub const DEFAULT_THICKNESS: f32 = 1.25;

/// Current render_scale for thickness scaling. Set by App.beginRender()
/// each frame so drawLinesRaw can scale line thickness proportionally.
var current_render_scale: f32 = 1.0;

pub fn setRenderScale(s: f32) void {
    current_render_scale = s;
}

// ── Glow post-processing state ─────────────────────────────────────
// When glow is active, App.beginRender renders the scene into an offscreen
// RenderTexture instead of directly to the screen. When RenderContext.end()
// is called, it ends texture mode and calls compositeGlow() to draw the
// scene texture to the screen with additive blurred copies for the bloom.

var glow_active: bool = false;
var glow_scene: ?rl.RenderTexture2D = null;
var glow_blur: ?rl.RenderTexture2D = null;
var glow_bg_color: rl.Color = rl.Color.black;

/// Called by App.beginRender to activate glow mode for this frame.
pub fn beginGlowFrame(scene: rl.RenderTexture2D, blur: rl.RenderTexture2D, bg: rl.Color) void {
    glow_active = true;
    glow_scene = scene;
    glow_blur = blur;
    glow_bg_color = bg;
}

/// Composite the offscreen scene texture onto the screen with a glow/bloom
/// effect. Draws the sharp scene first, then several additive blended
/// copies at increasing scales with decreasing alpha to simulate bloom.
fn compositeGlow() void {
    glow_active = false;
    const scene = glow_scene orelse {
        rl.endDrawing();
        return;
    };
    const blur = glow_blur orelse {
        rl.endDrawing();
        return;
    };

    const sw = rl.getScreenWidth();
    const sh = rl.getScreenHeight();
    const tw: f32 = @floatFromInt(scene.texture.width);
    const th: f32 = @floatFromInt(scene.texture.height);

    // Source rect — flip Y because render textures are upside down in raylib
    const src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = tw,
        .height = -th,
    };
    const dest = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(sw),
        .height = @floatFromInt(sh),
    };
    const origin = Vector2{ .x = 0, .y = 0 };

    // Step 1: Build a blurred bright-pass into the blur texture.
    // Draw the scene to the blur texture at reduced scale (downsample),
    // which naturally blurs it via bilinear filtering.
    rl.beginTextureMode(blur);
    rl.clearBackground(rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    // Downsample to half size, then it'll be upsampled back — cheap blur
    const half_src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = tw,
        .height = -th,
    };
    const blur_dest = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(blur.texture.width),
        .height = @floatFromInt(blur.texture.height),
    };
    // Draw scene scaled down with additive blend to capture only bright areas
    rl.beginBlendMode(.additive);
    rl.drawTexturePro(scene.texture, half_src, blur_dest, origin, 0, rl.Color{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 80,
    });
    rl.endBlendMode();
    rl.endTextureMode();

    // Step 2: Draw to the actual screen
    rl.beginDrawing();
    rl.clearBackground(glow_bg_color);

    // Draw the sharp scene
    rl.drawTexturePro(scene.texture, src, dest, origin, 0, rl.Color.white);

    // Draw the blurred bright-pass on top with additive blending for glow
    const blur_src = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(blur.texture.width),
        .height = -@as(f32, @floatFromInt(blur.texture.height)),
    };

    // Multiple passes at slightly different scales for a wider glow
    rl.beginBlendMode(.additive);

    // Pass 1: tight glow (1.0x scale of the blur)
    rl.drawTexturePro(blur.texture, blur_src, dest, origin, 0, rl.Color{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 100,
    });

    // Pass 2: wider glow (scaled up slightly)
    const dest2 = rl.Rectangle{
        .x = -@as(f32, @floatFromInt(sw)) * 0.02,
        .y = -@as(f32, @floatFromInt(sh)) * 0.02,
        .width = @as(f32, @floatFromInt(sw)) * 1.04,
        .height = @as(f32, @floatFromInt(sh)) * 1.04,
    };
    rl.drawTexturePro(blur.texture, blur_src, dest2, origin, 0, rl.Color{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 60,
    });

    // Pass 3: widest glow (scaled up more)
    const dest3 = rl.Rectangle{
        .x = -@as(f32, @floatFromInt(sw)) * 0.04,
        .y = -@as(f32, @floatFromInt(sh)) * 0.04,
        .width = @as(f32, @floatFromInt(sw)) * 1.08,
        .height = @as(f32, @floatFromInt(sh)) * 1.08,
    };
    rl.drawTexturePro(blur.texture, blur_src, dest3, origin, 0, rl.Color{
        .r = 255,
        .g = 255,
        .b = 255,
        .a = 40,
    });

    rl.endBlendMode();

    rl.endDrawing();

    // Clear references
    glow_scene = null;
    glow_blur = null;
}

pub const RenderContext = struct {
    screen: *Screen,
    camera: rl.Camera2D,
    ended: bool = false,
    /// Line stroke thickness in design-space pixels. Games can override
    /// this to make vector lines thinner or thicker. Default is 2.5.
    line_thickness: f32 = DEFAULT_THICKNESS,

    /// End rendering — calls camera.end() and rl.endDrawing().
    /// Normally called via `defer ctx.end()`.
    /// When the App has glow enabled, this composites the offscreen
    /// render texture onto the screen with additive blurred copies
    /// to produce the bloom/glow effect.
    pub fn end(self: *RenderContext) void {
        if (self.ended) return;
        self.ended = true;
        self.camera.end();

        if (glow_active) {
            // End rendering into the offscreen texture, then composite
            // the glow/bloom effect onto the actual screen.
            rl.endTextureMode();
            compositeGlow();
        } else {
            rl.endDrawing();
        }
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
        drawLinesRawThick(org, scale, rot, points, connect, color, self.line_thickness);
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

/// Raw drawLines with default thickness — used as callback for text.drawNumber.
pub fn drawLinesRaw(org: Vector2, scale: f32, rot: f32, points: []const Vector2, connect: bool, color: rl.Color) void {
    drawLinesRawThick(org, scale, rot, points, connect, color, DEFAULT_THICKNESS);
}

/// Raw drawLines with explicit thickness (in design-space pixels, scaled
/// by current_render_scale for the actual draw call).
pub fn drawLinesRawThick(org: Vector2, scale: f32, rot: f32, points: []const Vector2, connect: bool, color: rl.Color, thickness: f32) void {
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
    const scaled_thickness = thickness * current_render_scale;
    const bound = if (connect) points.len else (points.len - 1);
    for (0..bound) |i| {
        rl.drawLineEx(t.apply(points[i]), t.apply(points[(i + 1) % points.len]), scaled_thickness, color);
    }
}