// VecInvaders — Space Invaders built on the vgame platform
//
// Left/Right: move ship. Space: shoot. Aliens march and shoot back.
// Aliens speed up as fewer remain. Clear the board for a new (faster) wave.
// 3 lives. Game over when aliens reach you or lives run out.
//
// Four vector bunkers sit between the player and the aliens. Both player
// and alien bullets damage bunkers cell-by-cell. Each bunker is a grid of
// small vector squares; destroyed cells are simply removed from the draw.
//
// Player ship points UP (toward the invaders at the top of the screen).

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

// ── Squadron configuration ──────────────────────────────────────
// The squadron consumes ~70% of the field width. We compute the alien
// spacing and scale dynamically from the field size at spawn time.
const COLS: usize = 8;
const ROWS: usize = 4;
const FIELD_COVERAGE: f32 = 0.70; // 70% of field width

// ── Bunker configuration ────────────────────────────────────────
const BUNKER_COUNT: usize = 4;
const BUNKER_COLS: usize = 6;
const BUNKER_ROWS: usize = 4;
const BUNKER_CELL: f32 = 18.0; // pixel size of each damageable cell

const Bunker = struct {
    x: f32, // top-left x of the bunker grid
    y: f32, // top-left y
    cells: [BUNKER_ROWS][BUNKER_COLS]bool, // true = intact, false = destroyed

    fn init(x: f32, y: f32) Bunker {
        return .{
            .x = x,
            .y = y,
            .cells = @splat(@splat(true)),
        };
    }

    /// Check if a point hits any intact cell. If so, destroy it and return true.
    fn hitTest(self: *Bunker, pos: Vector2, radius: f32) bool {
        for (0..BUNKER_ROWS) |r| {
            for (0..BUNKER_COLS) |c| {
                if (!self.cells[r][c]) continue;
                const cx = self.x + @as(f32, @floatFromInt(c)) * BUNKER_CELL + BUNKER_CELL / 2;
                const cy = self.y + @as(f32, @floatFromInt(r)) * BUNKER_CELL + BUNKER_CELL / 2;
                if (vgame.circleCollision(pos, radius, .{ .x = cx, .y = cy }, BUNKER_CELL * 0.7)) {
                    self.cells[r][c] = false;
                    return true;
                }
            }
        }
        return false;
    }

    /// Check if any intact cell occupies a vertical band (for alien collision).
    fn reachedByAlien(self: *const Bunker, alien_pos: Vector2, alien_radius: f32) bool {
        for (0..BUNKER_ROWS) |r| {
            for (0..BUNKER_COLS) |c| {
                if (!self.cells[r][c]) continue;
                const cx = self.x + @as(f32, @floatFromInt(c)) * BUNKER_CELL + BUNKER_CELL / 2;
                const cy = self.y + @as(f32, @floatFromInt(r)) * BUNKER_CELL + BUNKER_CELL / 2;
                if (vgame.circleCollision(alien_pos, alien_radius, .{ .x = cx, .y = cy }, BUNKER_CELL * 0.7)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn draw(self: *const Bunker, ctx: *const vgame.RenderContext) void {
        for (0..BUNKER_ROWS) |r| {
            for (0..BUNKER_COLS) |c| {
                if (!self.cells[r][c]) continue;
                const cx = self.x + @as(f32, @floatFromInt(c)) * BUNKER_CELL;
                const cy = self.y + @as(f32, @floatFromInt(r)) * BUNKER_CELL;
                // Filled green cell
                ctx.drawRect(.{
                    .x = cx + 1,
                    .y = cy + 1,
                    .width = BUNKER_CELL - 2,
                    .height = BUNKER_CELL - 2,
                }, vgame.Color.green);
            }
        }
    }
};

// ── Vector shapes ───────────────────────────────────────────────

const ALIEN_SHAPE = [_]Vector2{
    .{ .x = -0.4, .y = -0.3 }, .{ .x = -0.2, .y = 0.3 },
    .{ .x = 0.2, .y = 0.3 }, .{ .x = 0.4, .y = -0.3 },
    .{ .x = 0.2, .y = -0.1 }, .{ .x = -0.2, .y = -0.1 },
    .{ .x = -0.4, .y = -0.3 },
};

// Player ship points UP (toward the invaders at the top).
// Tip at top, base at bottom.
const PLAYER_SHAPE = [_]Vector2{
    .{ .x = 0.0, .y = -0.4 },  // tip (top)
    .{ .x = 0.3, .y = 0.3 },   // bottom-right
    .{ .x = 0.2, .y = 0.2 },   // notch
    .{ .x = -0.2, .y = 0.2 },  // notch
    .{ .x = -0.3, .y = 0.3 },  // bottom-left
    .{ .x = 0.0, .y = -0.4 },  // close back to tip
};

// ── Spawning ────────────────────────────────────────────────────

fn spawnAliens(aliens: *std.ArrayList(Alien), alloc: std.mem.Allocator, field_w: f32) !struct { spacing: f32, grid_x: f32 } {
    aliens.clearRetainingCapacity();
    // Squadron width = 70% of field width, spread across COLS columns.
    const squadron_w = field_w * FIELD_COVERAGE;
    const spacing = squadron_w / @as(f32, @floatFromInt(COLS));
    const grid_x = (field_w - squadron_w) / 2 + spacing / 2;
    for (0..ROWS) |row| {
        for (0..COLS) |col| {
            try aliens.append(alloc, .{
                .pos = .{
                    .x = grid_x + @as(f32, @floatFromInt(col)) * spacing,
                    .y = 120 + @as(f32, @floatFromInt(row)) * spacing,
                },
            });
        }
    }
    return .{ .spacing = spacing, .grid_x = grid_x };
}

fn spawnBunkers(bunkers: *[BUNKER_COUNT]Bunker, field_w: f32, field_h: f32) void {
    // Place 4 bunkers evenly spaced, above the player.
    const bunker_w = @as(f32, @floatFromInt(BUNKER_COLS)) * BUNKER_CELL;
    const total_w = @as(f32, @floatFromInt(BUNKER_COUNT)) * bunker_w;
    const gap = (field_w - total_w) / @as(f32, @floatFromInt(BUNKER_COUNT + 1));
    const bunker_y = field_h - 160; // above the player
    for (0..BUNKER_COUNT) |i| {
        const x = gap + @as(f32, @floatFromInt(i)) * (bunker_w + gap);
        bunkers[i] = Bunker.init(x, bunker_y);
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

    var aliens = try std.ArrayList(Alien).initCapacity(allocator, COLS * ROWS);
    defer aliens.deinit(allocator);
    var bullets = std.ArrayList(Bullet).empty;
    defer bullets.deinit(allocator);
    var particles = vgame.Particles.init(allocator);
    defer particles.deinit();

    var bunkers: [BUNKER_COUNT]Bunker = undefined;

    var player = Player{ .pos = .{ .x = 640, .y = 900 } };
    var score: usize = 0;
    var game_over = false;
    var paused = false;
    var alien_dir: f32 = 1.0;
    var alien_speed: f32 = 60.0;
    const alien_drop: f32 = 30.0;
    var alien_shoot_timer: f32 = 0;
    var wave: usize = 1;
    var alien_spacing: f32 = 80.0;

    // Initial spawn
    {
        const s = try spawnAliens(&aliens, allocator, 1280);
        alien_spacing = s.spacing;
    }
    spawnBunkers(&bunkers, 1280, 960);

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        // Keep player and bunkers positioned relative to field
        player.pos.y = fs.y - 60;

        if (!game_over and !paused) {
            // Player movement
            if (rl.isKeyDown(.left)) player.pos.x -= 500 * dt;
            if (rl.isKeyDown(.right)) player.pos.x += 500 * dt;
            player.pos.x = @max(40, @min(fs.x - 40, player.pos.x));

            // Shoot (bullet goes UP — negative y velocity)
            if (rl.isKeyPressed(.space)) {
                try bullets.append(allocator, .{
                    .pos = .{ .x = player.pos.x, .y = player.pos.y - 20 },
                    .vel = .{ .x = 0, .y = -700 },
                    .from_player = true,
                });
            }

            // Alien movement
            const margin: f32 = alien_spacing * 0.6;
            var hit_edge = false;
            for (aliens.items) |*a| {
                if (a.alive) {
                    a.pos.x += alien_dir * alien_speed * dt;
                    if (a.pos.x < margin or a.pos.x > fs.x - margin) hit_edge = true;
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

                // Bunker collision (both player and alien bullets)
                if (!b.remove) {
                    for (&bunkers) |*bk| {
                        if (bk.hitTest(b.pos, 5)) {
                            b.remove = true;
                            break;
                        }
                    }
                }

                if (!b.remove) {
                    if (b.from_player) {
                        const alien_radius = alien_spacing * 0.35;
                        for (aliens.items) |*a| {
                            if (a.alive and vgame.circleCollision(b.pos, 5, a.pos, alien_radius)) {
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

            // Aliens erode bunkers as they descend
            const alien_radius = alien_spacing * 0.35;
            for (aliens.items) |*a| {
                if (!a.alive) continue;
                for (&bunkers) |*bk| {
                    // Destroy any cells the alien overlaps
                    for (0..BUNKER_ROWS) |r| {
                        for (0..BUNKER_COLS) |c| {
                            if (!bk.cells[r][c]) continue;
                            const cx = bk.x + @as(f32, @floatFromInt(c)) * BUNKER_CELL + BUNKER_CELL / 2;
                            const cy = bk.y + @as(f32, @floatFromInt(r)) * BUNKER_CELL + BUNKER_CELL / 2;
                            if (vgame.circleCollision(a.pos, alien_radius, .{ .x = cx, .y = cy }, BUNKER_CELL * 0.7)) {
                                bk.cells[r][c] = false;
                            }
                        }
                    }
                }
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
                const s = try spawnAliens(&aliens, allocator, fs.x);
                alien_spacing = s.spacing;
                // Restore bunkers on new wave
                spawnBunkers(&bunkers, fs.x, fs.y);
            }

            particles.update(dt, fs);

            if (rl.isKeyPressed(.p)) paused = true;
        } else if (paused) {
            if (rl.isKeyPressed(.p) or rl.isKeyPressed(.space)) paused = false;
        } else if (game_over) {
            if (rl.isKeyPressed(.r)) {
                player = .{ .pos = .{ .x = fs.x / 2, .y = fs.y - 60 }, .lives = 3 };
                score = 0;
                wave = 1;
                game_over = false;
                alien_speed = 60.0;
                alien_dir = 1.0;
                bullets.clearRetainingCapacity();
                const s = try spawnAliens(&aliens, allocator, fs.x);
                alien_spacing = s.spacing;
                spawnBunkers(&bunkers, fs.x, fs.y);
            }
        }

        // ── Render ────────────────────────────────────────────────
        var ctx = app.beginRender();
        defer ctx.end();

        const alien_draw_scale = alien_spacing * 0.5;

        // Aliens
        for (aliens.items) |a| {
            if (a.alive) {
                ctx.drawLines(a.pos, alien_draw_scale, 0, &ALIEN_SHAPE, true, vgame.Color.green);
            }
        }

        // Bunkers
        for (&bunkers) |*bk| {
            bk.draw(&ctx);
        }

        // Player (points up)
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

        // Lives (drawn with the upward-pointing shape)
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