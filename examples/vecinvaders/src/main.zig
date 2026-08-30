// VecInvaders — Space Invaders built on the vgame platform
//
// Left/Right: move ship. Space: shoot. Aliens march and shoot back.
// Aliens speed up as fewer remain. Clear the board for a new (faster) wave.
// 3 lives. Game over when aliens reach you or lives run out.

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

const Alien = struct {
    pos: Vector2,
    alive: bool = true,
};

const Player = struct {
    pos: Vector2,
    lives: usize = 3,
};

const Bullet = struct {
    pos: Vector2,
    vel: Vector2,
    from_player: bool,
    remove: bool = false,
};

const COLS = 8;
const ROWS = 4;
const SPACING: f32 = 80.0;
const CELL_SIZE: f32 = 25.0;

const ALIEN_SHAPE = [_]Vector2{
    .{ .x = -0.4, .y = -0.3 }, .{ .x = -0.2, .y = 0.3 },
    .{ .x = 0.2, .y = 0.3 }, .{ .x = 0.4, .y = -0.3 },
    .{ .x = 0.2, .y = -0.1 }, .{ .x = -0.2, .y = -0.1 },
    .{ .x = -0.4, .y = -0.3 },
};

const PLAYER_SHAPE = [_]Vector2{
    .{ .x = -0.3, .y = -0.3 }, .{ .x = 0.0, .y = 0.4 },
    .{ .x = 0.3, .y = -0.3 }, .{ .x = 0.2, .y = -0.2 },
    .{ .x = -0.2, .y = -0.2 }, .{ .x = -0.3, .y = -0.3 },
};

fn spawnAliens(aliens: *std.ArrayList(Alien), alloc: std.mem.Allocator, gx: f32) !void {
    aliens.clearRetainingCapacity();
    for (0..ROWS) |row| {
        for (0..COLS) |col| {
            try aliens.append(alloc, .{
                .pos = .{
                    .x = gx + @as(f32, @floatFromInt(col)) * SPACING,
                    .y = 120 + @as(f32, @floatFromInt(row)) * SPACING,
                },
            });
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "VecInvaders",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
    });
    defer app.deinit();

    var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
    var rand = prng.random();

    const field = app.screen.size;

    var aliens = try std.ArrayList(Alien).initCapacity(allocator, COLS * ROWS);
    defer aliens.deinit(allocator);
    var bullets = std.ArrayList(Bullet).empty;
    defer bullets.deinit(allocator);
    var particles = vgame.Particles.init(allocator);
    defer particles.deinit();

    var player = Player{ .pos = .{ .x = field.x / 2, .y = field.y - 80 } };
    var score: usize = 0;
    var game_over = false;
    var paused = false;
    var alien_dir: f32 = 1.0;
    var alien_speed: f32 = 60.0;
    const alien_drop: f32 = 30.0;
    var alien_shoot_timer: f32 = 0;
    var wave: usize = 1;

    const grid_x = field.x / 2 - (@as(f32, @floatFromInt(COLS)) * SPACING) / 2;

    try spawnAliens(&aliens, allocator, grid_x);

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        if (!game_over and !paused) {
            // Player movement
            if (rl.isKeyDown(.left)) player.pos.x -= 500 * dt;
            if (rl.isKeyDown(.right)) player.pos.x += 500 * dt;
            player.pos.x = @max(40, @min(fs.x - 40, player.pos.x));

            // Shoot
            if (rl.isKeyPressed(.space)) {
                try bullets.append(allocator, .{
                    .pos = player.pos,
                    .vel = .{ .x = 0, .y = -700 },
                    .from_player = true,
                });
            }

            // Alien movement
            var hit_edge = false;
            for (aliens.items) |*a| {
                if (a.alive) {
                    a.pos.x += alien_dir * alien_speed * dt;
                    if (a.pos.x < 40 or a.pos.x > fs.x - 40) hit_edge = true;
                }
            }
            if (hit_edge) {
                alien_dir *= -1;
                for (aliens.items) |*a| a.pos.y += alien_drop;
            }

            // Alien shooting (random interval)
            alien_shoot_timer += dt;
            if (alien_shoot_timer > 1.0 + rand.float(f32) * 2.0) {
                alien_shoot_timer = 0;
                // Pick a random alive alien
                var alive_list = std.ArrayList(usize).empty;
                defer alive_list.deinit(allocator);
                for (aliens.items, 0..) |a, i| if (a.alive) try alive_list.append(allocator, i);
                if (alive_list.items.len > 0) {
                    const idx = alive_list.items[rand.intRangeLessThan(usize, 0, alive_list.items.len)];
                    try bullets.append(allocator, .{
                        .pos = aliens.items[idx].pos,
                        .vel = .{ .x = 0, .y = 350 },
                        .from_player = false,
                    });
                }
            }

            // Update bullets
            var i: usize = 0;
            while (i < bullets.items.len) {
                var b = &bullets.items[i];
                b.pos.x += b.vel.x * dt;
                b.pos.y += b.vel.y * dt;
                if (b.pos.y < 0 or b.pos.y > fs.y) b.remove = true;

                if (!b.remove) {
                    if (b.from_player) {
                        for (aliens.items) |*a| {
                            if (a.alive and vgame.circleCollision(b.pos, 5, a.pos, CELL_SIZE)) {
                                a.alive = false;
                                b.remove = true;
                                score += 100;
                                try particles.spawnDots(a.pos, 10, .{
                                    .color = vgame.Color.green,
                                    .scale = app.screen.scale,
                                }, &rand);
                            }
                        }
                    } else {
                        if (vgame.circleCollision(b.pos, 5, player.pos, 25)) {
                            b.remove = true;
                            player.lives -= 1;
                            try particles.spawnDots(player.pos, 15, .{
                                .color = vgame.Color.red,
                                .scale = app.screen.scale,
                            }, &rand);
                            if (player.lives == 0) game_over = true;
                        }
                    }
                }

                if (b.remove) _ = bullets.swapRemove(i) else i += 1;
            }

            // Check aliens reaching player
            for (aliens.items) |a| {
                if (a.alive and a.pos.y > player.pos.y - 40) game_over = true;
            }

            // Check win (all aliens dead)
            var all_dead = true;
            for (aliens.items) |a| if (a.alive) { all_dead = false; break; };
            if (all_dead) {
                wave += 1;
                alien_speed = 60.0 + @as(f32, @floatFromInt(wave)) * 15.0;
                alien_dir = 1.0;
                try spawnAliens(&aliens, allocator, grid_x);
            }

            particles.update(dt, fs);

            if (rl.isKeyPressed(.p)) paused = true;
        } else if (paused) {
            if (rl.isKeyPressed(.p) or rl.isKeyPressed(.space)) paused = false;
        } else if (game_over) {
            if (rl.isKeyPressed(.r)) {
                player = .{ .pos = .{ .x = fs.x / 2, .y = fs.y - 80 }, .lives = 3 };
                score = 0;
                wave = 1;
                game_over = false;
                alien_speed = 60.0;
                alien_dir = 1.0;
                bullets.clearRetainingCapacity();
                try spawnAliens(&aliens, allocator, grid_x);
            }
        }

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Aliens
        for (aliens.items) |a| {
            if (a.alive) {
                ctx.drawLines(a.pos, app.screen.scale * 0.5, 0, &ALIEN_SHAPE, true, vgame.Color.green);
            }
        }

        // Player
        ctx.drawLines(player.pos, app.screen.scale * 0.5, 0, &PLAYER_SHAPE, true, vgame.Color.white);

        // Bullets
        for (bullets.items) |b| {
            const c: vgame.Color = if (b.from_player) vgame.Color.white else vgame.Color.red;
            ctx.drawCircle(b.pos, 4, c);
        }

        // Particles
        particles.render();

        // Score
        ctx.drawNumber(score, .{ .x = fs.x - 200, .y = 50 });

        // Wave
        var wave_buf: [32:0]u8 = undefined;
        const wave_str = std.fmt.bufPrintZ(&wave_buf, "Wave {d}", .{wave}) catch unreachable;
        const wave_w = rl.measureText(wave_str, 20);
        ctx.drawText(wave_str, @as(i32, @intFromFloat(fs.x / 2)) - @divTrunc(wave_w, 2), 30, 20, vgame.Color.white);

        // Lives
        for (0..player.lives) |li| {
            ctx.drawLines(
                .{ .x = 50 + @as(f32, @floatFromInt(li)) * 45, .y = 60 },
                app.screen.scale * 0.3,
                0,
                &PLAYER_SHAPE,
                true,
                vgame.Color.white,
            );
        }

        // Overlays
        if (paused) {
            vgame.drawOverlay(fs, .{
                .title = "PAUSED",
                .lines = &.{
                    "P or SPACE to resume",
                    "",
                    "LEFT/RIGHT  Move",
                    "SPACE       Shoot",
                },
            });
        }
        if (game_over) {
            var score_buf: [64:0]u8 = undefined;
            const score_str = std.fmt.bufPrintZ(&score_buf, "Score: {d}", .{score}) catch unreachable;
            vgame.drawOverlay(fs, .{
                .title = "GAME OVER",
                .title_color = vgame.Color.red,
                .lines = &.{ score_str, "", "Press R to play again" },
                .bg_color = .{ .r = 80, .g = 16, .b = 16, .a = 200 },
                .border_color = .{ .r = 220, .g = 80, .b = 80, .a = 220 },
                .fullscreen_dim = true,
            });
        }
    }
}