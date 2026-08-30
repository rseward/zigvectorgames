// text.zig — Vector digit rendering (7-segment style numbers)
//
// Ported from zigsteroids drawNumber(). Each digit 0-9 is defined as a set of
// line segments in a unit square [0,1]x[0,1]. The drawLinesFn callback renders
// the transformed points, so this module has no direct raylib dependency
// beyond the Vector2 type.

const std = @import("std");
const rl = @import("raylib");
const Vector2 = rl.Vector2;

pub const NUMBER_LINES = [10][]const [2]f32{
    &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 } },
    &.{ .{ 0.5, 0 }, .{ 0.5, 1 } },
    &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 0 }, .{ 1, 0 } },
    &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } },
    &.{ .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 1 }, .{ 1, 0 } },
    &.{ .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 1, 0 }, .{ 0, 0 } },
    &.{ .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.5 }, .{ 0, 0.5 } },
    &.{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } },
    &.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 }, .{ 0, 0.5 }, .{ 0, 0 } },
    &.{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0.5 }, .{ 1, 0.5 } },
};

pub const DrawLinesFn = *const fn (org: Vector2, scale: f32, rot: f32, points: []const Vector2, connect: bool, color: rl.Color) void;

/// Draw a number using vector line segments at the given position.
/// Digits are drawn right-to-left (least significant digit at `pos`).
/// `scale` controls digit size; each digit occupies `scale` width.
pub fn drawNumber(n: usize, pos: Vector2, scale: f32, color: rl.Color, drawLinesFn: DrawLinesFn) void {
    var pos2 = pos;
    var val = n;
    while (val >= 0) {
        var buffer: [16]Vector2 = undefined;
        var points = std.ArrayListUnmanaged(Vector2).initBuffer(&buffer);
        for (NUMBER_LINES[val % 10]) |p| {
            points.appendAssumeCapacity(.{
                .x = p[0] - 0.5,
                .y = (1.0 - p[1]) - 0.5,
            });
        }
        drawLinesFn(pos2, scale * 0.8, 0, points.items, false, color);
        pos2.x -= scale;
        val /= 10;
        if (val == 0) break;
    }
}