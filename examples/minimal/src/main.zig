// minimal — Bouncing vector triangle demonstrating vgame platform
//
// Shows: App lifecycle, RenderContext, vector drawing, screen scaling,
// and percentage-based positioning (the design language for the platform).

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

pub fn main() void {
    mainImpl() catch |err| {
        std.log.err("game error: {}", .{err});
    };
}

fn mainImpl() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Design resolution is 1280x960. All game logic uses these coordinates.
    // The platform scales rendering to fit the actual window automatically.
    var app = try vgame.App.init(allocator, .{
        .title = "vgame minimal",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
    });
    defer app.deinit();

    // Position expressed as percentage of design resolution (0.0–1.0).
    // 50% width, 50% height = center of the field.
    var pos = Vector2{ .x = 640, .y = 480 };
    var vel = Vector2{ .x = 200, .y = 150 };

    while (app.frame()) {
        const dt = app.delta;
        // screen.size is always the design_size (1280x960) — it never changes
        // regardless of window size. Games work in this fixed coordinate space.
        const field = app.screen.size;

        // Update: bounce the triangle around the field
        pos.x += vel.x * dt;
        pos.y += vel.y * dt;

        if (pos.x < 50 or pos.x > field.x - 50) vel.x *= -1;
        if (pos.y < 50 or pos.y > field.y - 50) vel.y *= -1;

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Draw a vector ship/triangle at the current position.
        // Scale is in design-space pixels (app.screen.scale = base_scale = 38.0).
        ctx.drawLines(pos, app.screen.scale, 0, &.{
            .{ .x = -0.4, .y = -0.5 },
            .{ .x = 0.0, .y = 0.5 },
            .{ .x = 0.4, .y = -0.5 },
            .{ .x = 0.3, .y = -0.4 },
            .{ .x = -0.3, .y = -0.4 },
        }, true, vgame.Color.white);

        // Draw a number in the top-left corner
        ctx.drawNumber(@intFromFloat(pos.x), .{ .x = 200, .y = 100 });

        // Draw corner markers using percentage positioning:
        // ctx.pct(0.0, 0.0) = top-left, ctx.pct(1.0, 1.0) = bottom-right
        const tl = ctx.pct(0.05, 0.05);
        const tr = ctx.pct(0.95, 0.05);
        const bl = ctx.pct(0.05, 0.95);
        const br = ctx.pct(0.95, 0.95);
        ctx.drawCircle(tl, 8, vgame.Color.green);
        ctx.drawCircle(tr, 8, vgame.Color.green);
        ctx.drawCircle(bl, 8, vgame.Color.green);
        ctx.drawCircle(br, 8, vgame.Color.green);
    }
}