// VecPong — Classic Pong built on the vgame platform
//
// Default mode: Player vs Computer (AI opponent).
// Press 2 at the title screen for two-player mode (keyboard or two gamepads).
//
// Player 1 controls:
//   Keyboard: Up/Down arrows
//   Gamepad 0: Left stick Y / D-pad up-down
//
// Player 2 controls (two-player mode only):
//   Keyboard: W/S
//   Gamepad 1: Left stick Y / D-pad up-down
//
// F toggles fullscreen (platform default).
// P pauses and shows the help screen.
// R restarts after a game ends. 1/2 selects mode at title screen.

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

// AI tuning — imperfection values make the computer beatable.
const AI_REACTION_DELAY: f32 = 0.12; // seconds of lag before AI responds
const AI_MAX_SPEED: f32 = 380.0; // slower than player's 500
const AI_DEADZONE: f32 = 30.0; // don't chase tiny misalignments

const Mode = enum { title, vs_computer, two_player };

const GameMode = enum { title, playing, paused, game_over };

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

    var mode: Mode = .title;
    var game_state: GameMode = .title;
    var winner: []const u8 = "";

    // AI state
    var ai_target_y: f32 = 480;
    var ai_timer: f32 = 0;

    // Serve delay — brief pause before ball launches after a point
    var serve_delay: f32 = 0;

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        // ── Title screen ──────────────────────────────────────────
        if (game_state == .title) {
            if (rl.isKeyPressed(.one)) {
                mode = .vs_computer;
                game_state = .playing;
                resetGame(&p1, &p2, &ball, fs);
            }
            if (rl.isKeyPressed(.two)) {
                mode = .two_player;
                game_state = .playing;
                resetGame(&p1, &p2, &ball, fs);
            }
        }

        // ── Gameplay ──────────────────────────────────────────────
        if (game_state == .playing) {
            // Serve delay
            if (serve_delay > 0) {
                serve_delay -= dt;
            }

            // ── Player 1 input (keyboard: Up/Down + gamepad 0) ──
            if (rl.isKeyDown(.up)) p1.pos.y -= p1.speed * dt;
            if (rl.isKeyDown(.down)) p1.pos.y += p1.speed * dt;
            // Gamepad 0: left stick Y (inverted) + d-pad
            if (rl.isGamepadAvailable(0)) {
                const ly = rl.getGamepadAxisMovement(0, .left_y);
                if (@abs(ly) > 0.15) p1.pos.y += ly * p1.speed * dt;
                if (rl.isGamepadButtonDown(0, .left_face_up)) p1.pos.y -= p1.speed * dt;
                if (rl.isGamepadButtonDown(0, .left_face_down)) p1.pos.y += p1.speed * dt;
            }
            p1.pos.y = @max(p1.height / 2, @min(fs.y - p1.height / 2, p1.pos.y));

            // ── Player 2 input ──
            if (mode == .two_player) {
                // Keyboard: W/S
                if (rl.isKeyDown(.w)) p2.pos.y -= p2.speed * dt;
                if (rl.isKeyDown(.s)) p2.pos.y += p2.speed * dt;
                // Gamepad 1: left stick Y + d-pad
                if (rl.isGamepadAvailable(1)) {
                    const ly2 = rl.getGamepadAxisMovement(1, .left_y);
                    if (@abs(ly2) > 0.15) p2.pos.y += ly2 * p2.speed * dt;
                    if (rl.isGamepadButtonDown(1, .left_face_up)) p2.pos.y -= p2.speed * dt;
                    if (rl.isGamepadButtonDown(1, .left_face_down)) p2.pos.y += p2.speed * dt;
                }
                p2.pos.y = @max(p2.height / 2, @min(fs.y - p2.height / 2, p2.pos.y));
            } else {
                // ── AI opponent ──
                // React with a delay so the AI isn't perfect.
                ai_timer += dt;
                if (ai_timer >= AI_REACTION_DELAY) {
                    ai_timer = 0;
                    // Predict where the ball will be — only track when ball
                    // is moving toward AI side, otherwise drift to center.
                    if (ball.vel.x > 0) {
                        // Simple prediction: current ball y plus velocity * distance / speed
                        const dist = p2.pos.x - ball.pos.x;
                        const time_to_reach = dist / ball.vel.x;
                        ai_target_y = ball.pos.y + ball.vel.y * time_to_reach;
                        // Account for bounces (mirror off top/bottom walls)
                        const field_h = fs.y;
                        while (ai_target_y < 0 or ai_target_y > field_h) {
                            if (ai_target_y < 0) ai_target_y = -ai_target_y;
                            if (ai_target_y > field_h) ai_target_y = 2 * field_h - ai_target_y;
                        }
                    } else {
                        // Ball moving away — drift toward center
                        ai_target_y = fs.y / 2;
                    }
                }

                // Move toward target with max speed cap
                const diff = ai_target_y - p2.pos.y;
                if (@abs(diff) > AI_DEADZONE) {
                    const move = @max(-AI_MAX_SPEED * dt, @min(AI_MAX_SPEED * dt, diff));
                    p2.pos.y += move;
                }
                p2.pos.y = @max(p2.height / 2, @min(fs.y - p2.height / 2, p2.pos.y));
            }

            // ── Ball movement (only after serve delay) ──
            if (serve_delay <= 0) {
                ball.pos.x += ball.vel.x * dt;
                ball.pos.y += ball.vel.y * dt;
            }

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
                ball.vel.x = @abs(ball.vel.x) * 1.05; // slight speedup
                const offset = (ball.pos.y - p1.pos.y) / (p1.height / 2);
                ball.vel.y = offset * 400;
            }

            // Paddle collision (right)
            if (ball.vel.x > 0 and ball.pos.x > p2.pos.x - p2.width / 2 - ball.radius and
                @abs(ball.pos.y - p2.pos.y) < p2.height / 2 + ball.radius)
            {
                ball.vel.x = -@abs(ball.vel.x) * 1.05;
                const offset = (ball.pos.y - p2.pos.y) / (p2.height / 2);
                ball.vel.y = offset * 400;
            }

            // Cap ball speed
            const max_speed: f32 = 700;
            const speed = @sqrt(ball.vel.x * ball.vel.x + ball.vel.y * ball.vel.y);
            if (speed > max_speed) {
                ball.vel.x = ball.vel.x / speed * max_speed;
                ball.vel.y = ball.vel.y / speed * max_speed;
            }

            // Scoring
            if (ball.pos.x < -20) {
                p2.score += 1;
                ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
                ball.vel = .{ .x = 350, .y = 250 };
                serve_delay = 1.0;
            }
            if (ball.pos.x > fs.x + 20) {
                p1.score += 1;
                ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
                ball.vel = .{ .x = -350, .y = 250 };
                serve_delay = 1.0;
            }

            // Win check
            if (p1.score >= WIN_SCORE) {
                game_state = .game_over;
                winner = if (mode == .vs_computer) "YOU WIN!" else "PLAYER 1 WINS!";
            }
            if (p2.score >= WIN_SCORE) {
                game_state = .game_over;
                winner = if (mode == .vs_computer) "COMPUTER WINS!" else "PLAYER 2 WINS!";
            }

            // Pause toggle
            if (rl.isKeyPressed(.p)) game_state = .paused;
        } else if (game_state == .paused) {
            // P or Space resumes
            if (rl.isKeyPressed(.p) or rl.isKeyPressed(.space)) game_state = .playing;
        } else if (game_state == .game_over) {
            if (rl.isKeyPressed(.r)) {
                game_state = .playing;
                resetGame(&p1, &p2, &ball, fs);
                serve_delay = 1.0;
            }
            if (rl.isKeyPressed(.one)) {
                mode = .vs_computer;
                game_state = .playing;
                resetGame(&p1, &p2, &ball, fs);
                serve_delay = 1.0;
            }
            if (rl.isKeyPressed(.two)) {
                mode = .two_player;
                game_state = .playing;
                resetGame(&p1, &p2, &ball, fs);
                serve_delay = 1.0;
            }
        }

        // ── Render ────────────────────────────────────────────────
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

        // Ball (hidden during serve delay or pause)
        if (serve_delay <= 0 and game_state == .playing) {
            ctx.drawCircle(ball.pos, ball.radius, vgame.Color.white);
        }

        // Scores (vector numbers)
        ctx.drawNumber(p1.score, .{ .x = fs.x / 4, .y = 80 });
        ctx.drawNumber(p2.score, .{ .x = fs.x * 3 / 4, .y = 80 });

        // Mode label
        {
            const label: [:0]const u8 = if (mode == .vs_computer) "VS COMPUTER" else "TWO PLAYER";
            const lw = rl.measureText(label, 20);
            const lx: i32 = @as(i32, @intFromFloat(fs.x / 2)) - @divTrunc(lw, 2);
            ctx.drawText(label, lx, 20, 20, vgame.Color.gray);
        }

        // Gamepad connection indicators
        {
            var gp_buf: [128:0]u8 = undefined;
            if (rl.isGamepadAvailable(0)) {
                const name = rl.getGamepadName(0);
                const gp_str = std.fmt.bufPrintZ(&gp_buf, "P1: {s}", .{name}) catch "P1: Gamepad";
                ctx.drawText(gp_str, 10, @as(i32, @intFromFloat(fs.y)) - 30, 18, vgame.Color.gray);
            }
            if (rl.isGamepadAvailable(1)) {
                const name = rl.getGamepadName(1);
                const gp_str = std.fmt.bufPrintZ(&gp_buf, "P2: {s}", .{name}) catch "P2: Gamepad";
                const w = rl.measureText(gp_str, 18);
                ctx.drawText(gp_str, @as(i32, @intFromFloat(fs.x)) - w - 10, @as(i32, @intFromFloat(fs.y)) - 30, 18, vgame.Color.gray);
            }
        }

        // Title screen overlay
        if (game_state == .title) {
            vgame.drawOverlay(fs, .{
                .title = "VECPONG",
                .title_color = vgame.Color.white,
                .lines = &.{
                    "",
                    "Press 1 for Player vs Computer",
                    "Press 2 for Two Players",
                    "",
                    "Player 1: Up/Down or Gamepad 0",
                    "Player 2: W/S or Gamepad 1",
                    "",
                    "P = Pause   F = Fullscreen",
                },
                .bg_color = .{ .r = 16, .g = 60, .b = 140, .a = 200 },
            });
        }

        // Pause overlay (same help info as title screen)
        if (game_state == .paused) {
            vgame.drawOverlay(fs, .{
                .title = "PAUSED",
                .title_color = vgame.Color.white,
                .lines = &.{
                    "",
                    "Press P or Space to resume",
                    "",
                    "Player 1: Up/Down or Gamepad 0",
                    "Player 2: W/S or Gamepad 1",
                    "",
                    "F = Fullscreen",
                },
                .bg_color = .{ .r = 16, .g = 60, .b = 140, .a = 200 },
            });
        }

        // Game over overlay
        if (game_state == .game_over) {
            var win_buf: [64:0]u8 = undefined;
            const win_z = std.fmt.bufPrintZ(&win_buf, "{s}", .{winner}) catch unreachable;
            vgame.drawOverlay(fs, .{
                .title = win_z,
                .title_color = vgame.Color.yellow,
                .lines = &.{
                    "",
                    "Press R to play again (same mode)",
                    "Press 1 for Player vs Computer",
                    "Press 2 for Two Players",
                },
                .fullscreen_dim = true,
                .bg_color = .{ .r = 16, .g = 60, .b = 140, .a = 200 },
            });
        }
    }
}

fn resetGame(p1: *Paddle, p2: *Paddle, ball: *Ball, fs: Vector2) void {
    p1.score = 0;
    p2.score = 0;
    p1.pos.y = fs.y / 2;
    p2.pos.y = fs.y / 2;
    ball.pos = .{ .x = fs.x / 2, .y = fs.y / 2 };
    ball.vel = .{ .x = 350, .y = 250 };
}