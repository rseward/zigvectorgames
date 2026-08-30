// VecPong — Classic Pong built on the vgame platform
//
// Player 1: W/S (left paddle), Player 2: Up/Down (right paddle)
// Ball bounces off paddles and top/bottom walls.
// First to 11 points wins.

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

const Paddle = struct {
    pos: Vector2,
    score: usize = 0,
    height: f32 = 120.0,
    width: f32 = 12.0,
    speed: f32 = 500.0,
};

const Ball = struct {
    pos: Vector2,
    vel: Vector2,
    radius: f32 = 10.0,
};

const WIN_SCORE = 11;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "VecPong",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
    });
    defer app.deinit();

    var p1: Paddle = .{ .pos = .{ .x = 60, .y = 480 } };
    var p2: Paddle = .{ .pos = .{ .x = 1220, .y = 480 } };
    var ball: Ball = .{
        .pos = .{ .x = 640, .y = 480 },
        .vel = .{ .x = 350, .y = 250 },
    };
    var game_over = false;
    var winner: []const u8 = "";

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        if (!game_over) {
            // Player 1: W/S
            if (rl.isKeyDown(.w)) p1.pos.y -= p1.speed * dt;
            if (rl.isKeyDown(.s)) p1.pos.y += p1.speed * dt;

            // Player 2: Up/Down arrows
            if (rl.isKeyDown(.up)) p2.pos.y -= p2.speed * dt;
            if (rl.isKeyDown(.down)) p2.pos.y += p2.speed * dt;

            // Clamp paddles
            p1.pos.y = @max(p1.height / 2, @min(fs.y - p1.height / 2, p1.pos.y));
            p2.pos.y = @max(p2.height / 2, @min(fs.y - p2.height / 2, p2.pos.y));

            // Ball movement
            ball.pos.x += ball.vel.x * dt;
            ball.pos.y += ball.vel.y * dt;

            // Top/bottom bounce
            if (ball.pos.y < ball.radius) {
                ball.pos.y = ball.radius;
                ball.vel.y = @abs(ball.vel.y);
            }
            if (ball.pos.y > fs.y - ball.radius) {
                ball.pos.y = fs.y - ball.radius;
                ball.vel.y = -@abs(ball.vel.y);
            }

            // Paddle collision (left)
            if (ball.vel.x < 0 and ball.pos.x < p1.pos.x + p1.width / 2 + ball.radius and
                @abs(ball.pos.y - p1.pos.y) < p1.height / 2 + ball.radius)
            {
                ball.vel.x = @abs(ball.vel.x);
                // Add angle based on hit position
                const offset = (ball.pos.y - p1.pos.y) / (p1.height / 2);
                ball.vel.y = offset * 400;
            }

            // Paddle collision (right)
            if (ball.vel.x > 0 and ball.pos.x > p2.pos.x - p2.width / 2 - ball.radius and
                @abs(ball.pos.y - p2.pos.y) < p2.height / 2 + ball.radius)
            {
                ball.vel.x = -@abs(ball.vel.x);
                const offset = (ball.pos.y - p2.pos.y) / (p2.height / 2);
                ball.vel.y = offset * 400;
            }

            // Scoring
            if (ball.pos.x < -20) {
                p2.score += 1;
                ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
                ball.vel = .{ .x = 350, .y = 250 };
            }
            if (ball.pos.x > fs.x + 20) {
                p1.score += 1;
                ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
                ball.vel = .{ .x = -350, .y = 250 };
            }

            // Win check
            if (p1.score >= WIN_SCORE) {
                game_over = true;
                winner = "PLAYER 1 WINS!";
            }
            if (p2.score >= WIN_SCORE) {
                game_over = true;
                winner = "PLAYER 2 WINS!";
            }
        } else {
            if (rl.isKeyPressed(.r)) {
                p1.score = 0;
                p2.score = 0;
                ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
                ball.vel = .{ .x = 350, .y = 250 };
                game_over = false;
            }
        }

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Center line (dashed)
        const dash_count: i32 = 30;
        const dash_h = fs.y / @as(f32, @floatFromInt(dash_count * 2));
        for (0..dash_count) |i| {
            const y = @as(f32, @floatFromInt(i * 2)) * dash_h;
            ctx.drawRect(.{ .x = fs.x / 2 - 3, .y = y, .width = 6, .height = dash_h }, vgame.Color.ray_white);
        }

        // Paddles
        ctx.drawRect(.{
            .x = p1.pos.x - p1.width / 2,
            .y = p1.pos.y - p1.height / 2,
            .width = p1.width,
            .height = p1.height,
        }, vgame.Color.ray_white);
        ctx.drawRect(.{
            .x = p2.pos.x - p2.width / 2,
            .y = p2.pos.y - p2.height / 2,
            .width = p2.width,
            .height = p2.height,
        }, vgame.Color.ray_white);

        // Ball
        ctx.drawCircle(ball.pos, ball.radius, vgame.Color.white);

        // Scores (vector numbers)
        ctx.drawNumber(p1.score, .{ .x = fs.x / 4, .y = 80 });
        ctx.drawNumber(p2.score, .{ .x = fs.x * 3 / 4, .y = 80 });

        // Game over overlay
        if (game_over) {
            var win_buf: [64:0]u8 = undefined;
            const win_z = std.fmt.bufPrintZ(&win_buf, "{s}", .{winner}) catch unreachable;
            vgame.drawOverlay(fs, .{
                .title = win_z,
                .title_color = vgame.Color.yellow,
                .lines = &.{"Press R to play again"},
                .fullscreen_dim = true,
                .bg_color = .{ .r = 16, .g = 60, .b = 140, .a = 200 },
            });
        }
    }
}