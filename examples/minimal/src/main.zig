// minimal — Bouncing vector triangle demonstrating vgame platform

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "vgame minimal",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
    });
    defer app.deinit();

    var pos = Vector2{ .x = 640, .y = 480 };
    var vel = Vector2{ .x = 200, .y = 150 };

    while (app.frame()) {
        const dt = app.delta;
        const field = app.screen.size;

        // Update: bounce the triangle around the field
        pos.x += vel.x * dt;
        pos.y += vel.y * dt;

        if (pos.x < 50 or pos.x > field.x - 50) vel.x *= -1;
        if (pos.y < 50 or pos.y > field.y - 50) vel.y *= -1;

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Draw a vector ship/triangle
        ctx.drawLines(pos, app.screen.scale, 0, &.{
            .{ .x = -0.4, .y = -0.5 },
            .{ .x = 0.0, .y = 0.5 },
            .{ .x = 0.4, .y = -0.5 },
            .{ .x = 0.3, .y = -0.4 },
            .{ .x = -0.3, .y = -0.4 },
        }, true, vgame.Color.white);

        // Draw a number in the top-left
        ctx.drawNumber(@intFromFloat(pos.x), .{ .x = 200, .y = 100 });
    }
}