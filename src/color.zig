// color.zig — Color type and palette for vector games

const rl = @import("raylib");

pub const Color = rl.Color;

/// Named color palette. Games can use these presets or define their own.
pub const Palette = struct {
    white: Color = rl.Color.ray_white,
    green: Color = rl.Color.green,
    bright_white: Color = rl.Color.white,
    orange: Color = rl.Color.orange,
    blue: Color = rl.Color.blue,
    dark_blue: Color = rl.Color.dark_blue,
    red: Color = rl.Color.red,
    yellow: Color = rl.Color.yellow,
    purple: Color = rl.Color.purple,
    gray: Color = rl.Color.gray,
    cyan: Color = rl.Color.sky,
    black: Color = rl.Color.black,
};

/// Linear interpolation between two colors (t=0 -> c1, t=1 -> c2).
pub fn lerpColor(c1: Color, c2: Color, t: f32) Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(c1.r)) + t * @as(f32, @floatFromInt(c2.r - c1.r))),
        .g = @intFromFloat(@as(f32, @floatFromInt(c1.g)) + t * @as(f32, @floatFromInt(c2.g - c1.g))),
        .b = @intFromFloat(@as(f32, @floatFromInt(c1.b)) + t * @as(f32, @floatFromInt(c2.b - c1.b))),
        .a = @intFromFloat(@as(f32, @floatFromInt(c1.a)) + t * @as(f32, @floatFromInt(c2.a - c1.a))),
    };
}

/// Convenience: create a color with alpha (for overlay backgrounds).
pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}