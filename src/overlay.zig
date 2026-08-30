// overlay.zig — Overlay panels for pause, help, and game-over screens
//
// Extracted from zigsteroids drawHelpBox() and drawGameOverBox().
// drawOverlay() auto-sizes a centered translucent panel with title + lines +
// optional gamepad section + optional stats section.

const std = @import("std");
const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const OverlayOptions = struct {
    title: [:0]const u8,
    title_color: rl.Color = rl.Color.white,
    lines: []const [:0]const u8 = &.{},
    bg_color: rl.Color = .{ .r = 16, .g = 60, .b = 140, .a = 200 },
    border_color: rl.Color = .{ .r = 80, .g = 160, .b = 255, .a = 220 },
    font_size: i32 = 30,
    line_spacing: i32 = 10,
    padding: i32 = 40,
    /// Full-screen dark overlay behind the panel (for game-over style).
    fullscreen_dim: bool = false,
    dim_color: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 140 },
    panel_width: f32 = 520,
};

/// Draw a centered overlay panel with title and lines.
pub fn drawOverlay(field_size: Vector2, opts: OverlayOptions) void {
    if (opts.fullscreen_dim) {
        rl.drawRectangleRec(
            .{ .x = 0, .y = 0, .width = field_size.x, .height = field_size.y },
            opts.dim_color,
        );
    }

    const total_line_height = opts.font_size + opts.line_spacing;
    const line_count: i32 = @intCast(opts.lines.len);

    const panel_width = opts.panel_width;
    const panel_height: f32 = @floatFromInt(
        line_count * total_line_height +
            total_line_height + // title
            opts.padding * 2,
    );

    const panel_x = (field_size.x - panel_width) / 2;
    const panel_y = (field_size.y - panel_height) / 2;

    rl.drawRectangleRec(
        .{ .x = panel_x, .y = panel_y, .width = panel_width, .height = panel_height },
        opts.bg_color,
    );
    rl.drawRectangleLinesEx(
        .{ .x = panel_x, .y = panel_y, .width = panel_width, .height = panel_height },
        2,
        opts.border_color,
    );

    var y: i32 = @as(i32, @intFromFloat(panel_y)) + opts.padding;

    // Title
    {
        const tw = rl.measureText(opts.title, opts.font_size);
        const x: i32 = @as(i32, @intFromFloat(panel_x + (panel_width - @as(f32, @floatFromInt(tw))) / 2));
        rl.drawText(opts.title, x, y, opts.font_size, opts.title_color);
        y += total_line_height;
    }

    // Lines
    for (opts.lines) |line| {
        const tw = rl.measureText(line, opts.font_size);
        const x: i32 = @as(i32, @intFromFloat(panel_x + (panel_width - @as(f32, @floatFromInt(tw))) / 2));
        rl.drawText(line, x, y, opts.font_size, rl.Color.white);
        y += total_line_height;
    }
}

/// Draw a centered text label at a given y position (center_x is horizontal center).
pub fn centeredText(text_str: [:0]const u8, center_x: f32, y: i32, font_size: i32, color: rl.Color) void {
    const tw = rl.measureText(text_str, font_size);
    const x: i32 = @as(i32, @intFromFloat(center_x - @as(f32, @floatFromInt(tw)) / 2));
    rl.drawText(text_str, x, y, font_size, color);
}