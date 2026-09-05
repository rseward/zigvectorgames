// VecInvaders — Space Invaders built on the vgame platform
//
// Left/Right: move ship. Space: shoot (one bullet at a time).
// Aliens march and shoot back. Aliens speed up as fewer remain —
// speed is inversely proportional to the number alive.
// Clear the board for a new (faster) wave.
// 3 lives. Game over when aliens reach you or lives run out.
//
// Invaders have two alternating shapes (jaws open / jaws closed).
// The shape alternates each time the squadron advances a step.
// All invaders in the same column share the same shape state.
//
// Alien shooting: one bullet per column at a time. Fire rate doubles
// each wave. Columns near the player are more likely to fire (weighted
// by inverse distance). The lowest alien in a column fires.
//
// Bullets are vector-drawn rods — a short line segment in the direction
// of travel. Player rods are white (20px, upward), alien rods are red
// (16px, downward).
//
// Four vector bunkers sit between the player and the aliens. Both player
// and alien bullets damage bunkers cell-by-cell.
//
// Player ship points UP (toward the invaders at the top of the screen)
// and is approximately the same size as an invader.
//
// Sound effects (generated WAV files in resources/):
//   - Player laser: pitch-decreasing square wave sweep
//   - Alien laser:  pitch-increasing square wave sweep
//   - Explosion:    filtered noise burst with exponential decay
//   - March clicks: 4 ascending tones that cycle on each alien step

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

const Alien = struct {
    pos: Vector2,
    alive: bool = true,
    /// 0 = jaws closed, 1 = jaws open
    shape_state: u1 = 0,
};

const Player = struct {
    pos: Vector2,
    lives: usize = 3,
};

const Bullet = struct {
    pos: Vector2,
    vel: Vector2,
    from_player: bool,
    /// Which alien column this bullet came from (0..COLS-1).
    /// -1 (or any value >= COLS) for player bullets.
    column: i32 = -1,
    remove: bool = false,
};

// ── Squadron configuration ──────────────────────────────────────
const COLS: usize = 8;
const ROWS: usize = 4;
const FIELD_COVERAGE: f32 = 0.70;
const TOTAL_ALIENS: usize = COLS * ROWS;

// ── Bunker configuration ────────────────────────────────────────
const BUNKER_COUNT: usize = 4;
const BUNKER_COLS: usize = 6;
const BUNKER_ROWS: usize = 4;
const BUNKER_CELL: f32 = 18.0;

const Bunker = struct {
    x: f32,
    y: f32,
    cells: [BUNKER_ROWS][BUNKER_COLS]bool,

    fn init(x: f32, y: f32) Bunker {
        return .{
            .x = x,
            .y = y,
            .cells = @splat(@splat(true)),
        };
    }

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

    fn draw(self: *const Bunker, ctx: *const vgame.RenderContext) void {
        for (0..BUNKER_ROWS) |r| {
            for (0..BUNKER_COLS) |c| {
                if (!self.cells[r][c]) continue;
                const cx = self.x + @as(f32, @floatFromInt(c)) * BUNKER_CELL;
                const cy = self.y + @as(f32, @floatFromInt(r)) * BUNKER_CELL;
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
// Invader shapes derived from examples/design/invader1.svg (jaws closed)
// and invader2.svg (jaws open). Coordinates converted from the SVG
// viewBox (100x95) to normalized game space centered at (0,0).
// The head is slightly wider than the original polygon shapes to give
// a fatter appearance while keeping the same height ratio.

// Invader shape A: jaws closed (antennae inward) — from invader1.svg
const ALIEN_SHAPE_A = [_]Vector2{
    .{ .x = 0, .y = -0.375 }, .{ .x = -0.114, .y = -0.287 }, .{ .x = -0.186, .y = -0.4 }, .{ .x = -0.457, .y = -0.2 },
    .{ .x = -0.4, .y = -0.15 }, .{ .x = -0.186, .y = -0.287 }, .{ .x = -0.214, .y = -0.1 }, .{ .x = -0.214, .y = 0.1 },
    .{ .x = -0.143, .y = 0.25 }, .{ .x = -0.214, .y = 0.275 }, .{ .x = -0.171, .y = 0.4 }, .{ .x = 0, .y = 0.312 },
    .{ .x = 0.171, .y = 0.4 }, .{ .x = 0.214, .y = 0.275 }, .{ .x = 0.143, .y = 0.25 }, .{ .x = 0.214, .y = 0.1 },
    .{ .x = 0.214, .y = -0.1 }, .{ .x = 0.186, .y = -0.287 }, .{ .x = 0.4, .y = -0.15 }, .{ .x = 0.457, .y = -0.2 },
    .{ .x = 0.186, .y = -0.4 }, .{ .x = 0.114, .y = -0.287 },
};

// Invader shape B: jaws open (antennae outward) — from invader2.svg
const ALIEN_SHAPE_B = [_]Vector2{
    .{ .x = 0, .y = -0.35 }, .{ .x = -0.114, .y = -0.287 }, .{ .x = -0.186, .y = -0.362 }, .{ .x = -0.5, .y = -0.15 },
    .{ .x = -0.443, .y = -0.1 }, .{ .x = -0.214, .y = -0.263 }, .{ .x = -0.214, .y = -0.1 }, .{ .x = -0.214, .y = 0.1 },
    .{ .x = -0.143, .y = 0.25 }, .{ .x = -0.257, .y = 0.3 }, .{ .x = -0.229, .y = 0.45 }, .{ .x = 0, .y = 0.312 },
    .{ .x = 0.229, .y = 0.45 }, .{ .x = 0.257, .y = 0.3 }, .{ .x = 0.143, .y = 0.25 }, .{ .x = 0.214, .y = 0.1 },
    .{ .x = 0.214, .y = -0.1 }, .{ .x = 0.214, .y = -0.263 }, .{ .x = 0.443, .y = -0.1 }, .{ .x = 0.5, .y = -0.15 },
    .{ .x = 0.186, .y = -0.362 }, .{ .x = 0.114, .y = -0.287 },
};

// Eyes — small quadrilateral polygons from the SVGs, drawn as closed polylines
const ALIEN_EYE_L_A = [_]Vector2{
    .{ .x = -0.171, .y = -0.225 }, .{ .x = -0.043, .y = -0.175 },
    .{ .x = -0.1, .y = -0.087 }, .{ .x = -0.2, .y = -0.138 },
};
const ALIEN_EYE_R_A = [_]Vector2{
    .{ .x = 0.171, .y = -0.225 }, .{ .x = 0.043, .y = -0.175 },
    .{ .x = 0.1, .y = -0.087 }, .{ .x = 0.2, .y = -0.138 },
};
const ALIEN_EYE_L_B = [_]Vector2{
    .{ .x = -0.171, .y = -0.212 }, .{ .x = -0.043, .y = -0.163 },
    .{ .x = -0.1, .y = -0.075 }, .{ .x = -0.2, .y = -0.125 },
};
const ALIEN_EYE_R_B = [_]Vector2{
    .{ .x = 0.171, .y = -0.212 }, .{ .x = 0.043, .y = -0.163 },
    .{ .x = 0.1, .y = -0.075 }, .{ .x = 0.2, .y = -0.125 },
};

// Player ship points UP, same size as an invader.
const PLAYER_SHAPE = [_]Vector2{
    .{ .x = 0.0, .y = -0.4 },  // tip (top)
    .{ .x = 0.3, .y = 0.3 },   // bottom-right
    .{ .x = 0.2, .y = 0.2 },   // notch
    .{ .x = -0.2, .y = 0.2 },  // notch
    .{ .x = -0.3, .y = 0.3 },  // bottom-left
    .{ .x = 0.0, .y = -0.4 },  // close back to tip
};

// ── Precomputed polygon areas (normalized, for explosion fragment counts) ──
// The screen-space pixel area of a shape is:
//   normalized_area * entity_scale^2 * render_scale^2
// The number of 4-pixel explosion fragments is that / 4.

/// Shoelace formula for polygon area from a list of 2D points.
fn shoelaceArea(points: []const Vector2) f32 {
    var area: f32 = 0;
    for (0..points.len) |i| {
        const j = (i + 1) % points.len;
        area += points[i].x * points[j].y;
        area -= points[j].x * points[i].y;
    }
    return @abs(area) / 2.0;
}

// Precompute at comptime — alien area includes body + both eyes
const ALIEN_AREA_A: f32 = blk: {
    const body = shoelaceArea(&ALIEN_SHAPE_A);
    const eye_l = shoelaceArea(&ALIEN_EYE_L_A);
    const eye_r = shoelaceArea(&ALIEN_EYE_R_A);
    break :blk body + eye_l + eye_r;
};
const ALIEN_AREA_B: f32 = blk: {
    const body = shoelaceArea(&ALIEN_SHAPE_B);
    const eye_l = shoelaceArea(&ALIEN_EYE_L_B);
    const eye_r = shoelaceArea(&ALIEN_EYE_R_B);
    break :blk body + eye_l + eye_r;
};
const PLAYER_AREA: f32 = shoelaceArea(&PLAYER_SHAPE);

// ── Spawning ────────────────────────────────────────────────────

fn spawnAliens(aliens: *std.ArrayList(Alien), alloc: std.mem.Allocator, field_w: f32) !struct { spacing: f32, grid_x: f32 } {
    aliens.clearRetainingCapacity();
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
                .shape_state = 0,
            });
        }
    }
    return .{ .spacing = spacing, .grid_x = grid_x };
}

fn spawnBunkers(bunkers: *[BUNKER_COUNT]Bunker, field_w: f32, field_h: f32) void {
    const bunker_w = @as(f32, @floatFromInt(BUNKER_COLS)) * BUNKER_CELL;
    const total_w = @as(f32, @floatFromInt(BUNKER_COUNT)) * bunker_w;
    const gap = (field_w - total_w) / @as(f32, @floatFromInt(BUNKER_COUNT + 1));
    // Moved up to accommodate the larger player ship
    const bunker_y = field_h - 200;
    for (0..BUNKER_COUNT) |i| {
        const x = gap + @as(f32, @floatFromInt(i)) * (bunker_w + gap);
        bunkers[i] = Bunker.init(x, bunker_y);
    }
}

pub fn main() void {
    mainImpl() catch |err| {
        std.log.err("game error: {}", .{err});
    };
}

fn mainImpl() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "VecInvaders",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
        .glow = true,
        .msaa = true,
    });
    defer app.deinit();

    // Audio — sound clips loaded by index:
    //   0: explosion     1: player_laser    2: alien_laser
    //   3: march1 (low)  4: march2          5: march3         6: march4 (high)
    app.initAudio(.{
        .clips = &.{
            "explosion.wav",
            "player_laser.wav",
            "alien_laser.wav",
            "march1.wav",
            "march2.wav",
            "march3.wav",
            "march4.wav",
        },
        .resource_dir = "resources",
    }) catch |err| {
        std.log.warn("Audio init failed (game will be silent): {}", .{err});
    };
    const have_audio = app.audio != null;

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
    const alien_drop: f32 = 30.0;
    var alien_shoot_timer: f32 = 0;
    var wave: usize = 1;
    var alien_spacing: f32 = 80.0;
    var alive_count: usize = TOTAL_ALIENS;

    // Step-based movement: aliens move in discrete steps, not continuously.
    // Each step toggles the shape state and moves the squadron horizontally.
    var step_timer: f32 = 0;
    var step_interval: f32 = 0.5; // seconds between steps (updated by alive count)
    var march_step: u32 = 0; // cycles 0-3 for the four marching tones

    // Initial spawn
    {
        const s = try spawnAliens(&aliens, allocator, 1280);
        alien_spacing = s.spacing;
    }
    spawnBunkers(&bunkers, 1280, 960);

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        player.pos.y = fs.y - 60;

        if (!game_over and !paused) {
            // Player movement
            if (rl.isKeyDown(.left)) player.pos.x -= 500 * dt;
            if (rl.isKeyDown(.right)) player.pos.x += 500 * dt;
            player.pos.x = @max(40, @min(fs.x - 40, player.pos.x));

            // Shoot — only one player bullet on screen at a time
            if (rl.isKeyPressed(.space)) {
                var has_player_bullet = false;
                for (bullets.items) |b| {
                    if (b.from_player and !b.remove) {
                        has_player_bullet = true;
                        break;
                    }
                }
                if (!has_player_bullet) {
                    try bullets.append(allocator, .{
                        .pos = .{ .x = player.pos.x, .y = player.pos.y - 20 },
                        .vel = .{ .x = 0, .y = -700 },
                        .from_player = true,
                    });
                    if (have_audio) app.audio.?.play(1); // player laser
                }
            }

            // ── Step-based alien movement ──
            // Speed is inversely proportional to alive count — tripled so
            // the squadron accelerates aggressively as invaders are killed.
            // Full squadron: slow. Single alien: extremely fast.
            // Each wave is 25% faster than the last to keep escalating difficulty.
            const wave_multiplier: f32 = 1.0 / (1.0 + @as(f32, @floatFromInt(wave - 1)) * 0.25);
            step_interval = (@as(f32, @floatFromInt(alive_count)) * 0.0465 + 0.0575) * wave_multiplier;
            step_timer += dt;
            if (step_timer >= step_interval) {
                step_timer = 0;

                // Marching click — cycles through 4 ascending tones
                if (have_audio) app.audio.?.play(3 + march_step);
                march_step = (march_step + 1) % 4;

                // Toggle shape state for all aliens (advance animation)
                for (aliens.items) |*a| {
                    if (a.alive) a.shape_state = @addWithOverflow(a.shape_state, 1)[0];
                }

                // Check edge collision before moving
                const margin: f32 = alien_spacing * 0.6;
                var hit_edge = false;
                for (aliens.items) |a| {
                    if (!a.alive) continue;
                    const next_x = a.pos.x + alien_dir * alien_spacing * 0.15;
                    if (next_x < margin or next_x > fs.x - margin) {
                        hit_edge = true;
                        break;
                    }
                }

                if (hit_edge) {
                    alien_dir *= -1;
                    for (aliens.items) |*a| a.pos.y += alien_drop;
                } else {
                    for (aliens.items) |*a| {
                        if (a.alive) a.pos.x += alien_dir * alien_spacing * 0.15;
                    }
                }
            }

            // Alien shooting — one bullet per column at a time, fire rate
            // doubles each wave, columns near the player are more likely.
            alien_shoot_timer += dt;
            // Base interval scales with how many aliens are alive (fewer = more
            // frequent), and each wave halves the interval (doubles fire rate).
            const base_interval = 1.2 + rand.float(f32) * 0.8;
            const alive_ratio = @as(f32, @floatFromInt(alive_count)) / @as(f32, @floatFromInt(TOTAL_ALIENS));
            const wave_fire_factor = std.math.pow(f32, 0.5, @as(f32, @floatFromInt(wave - 1)));
            const shoot_interval = base_interval * alive_ratio * wave_fire_factor;
            if (alien_shoot_timer > shoot_interval) {
                alien_shoot_timer = 0;

                // Build list of columns that have at least one alive alien
                // and no active alien bullet in that column.
                var candidate_cols: [COLS]bool = .{false} ** COLS;
                for (0..COLS) |c| candidate_cols[c] = false;
                for (aliens.items, 0..) |a, idx| {
                    if (!a.alive) continue;
                    const col = idx % COLS;
                    // Check if there's already an alien bullet in this column
                    var col_has_bullet = false;
                    for (bullets.items) |b| {
                        if (!b.from_player and !b.remove and b.column == @as(i32, @intCast(col))) {
                            col_has_bullet = true;
                            break;
                        }
                    }
                    if (!col_has_bullet) candidate_cols[col] = true;
                }

                // Collect candidate columns with weights — columns near the
                // player's x position get higher weight.
                var weights: [COLS]f32 = .{0} ** COLS;
                var total_weight: f32 = 0;
                for (0..COLS) |c| {
                    if (!candidate_cols[c]) continue;
                    // Find the x position of this column's aliens
                    var col_x: f32 = 0;
                    var found = false;
                    for (aliens.items, 0..) |a, idx| {
                        if (a.alive and idx % COLS == c) {
                            col_x = a.pos.x;
                            found = true;
                            break;
                        }
                    }
                    if (!found) continue;
                    // Weight inversely proportional to distance from player.
                    // Near columns get ~3x the weight of far columns.
                    const dist = @abs(col_x - player.pos.x);
                    const w = 1.0 / (1.0 + dist / 200.0);
                    weights[c] = w;
                    total_weight += w;
                }

                if (total_weight > 0) {
                    // Weighted random selection
                    const r = rand.float(f32) * total_weight;
                    var cumulative: f32 = 0;
                    var chosen_col: ?usize = null;
                    for (0..COLS) |c| {
                        cumulative += weights[c];
                        if (r <= cumulative and weights[c] > 0) {
                            chosen_col = c;
                            break;
                        }
                    }
                    if (chosen_col == null) {
                        // Fallback: first available column
                        for (0..COLS) |c| {
                            if (candidate_cols[c]) {
                                chosen_col = c;
                                break;
                            }
                        }
                    }

                    if (chosen_col) |cc| {
                        // Pick the lowest alive alien in this column (closest to player)
                        var shooter_idx: ?usize = null;
                        var lowest_y: f32 = -1;
                        for (aliens.items, 0..) |a, idx| {
                            if (a.alive and idx % COLS == cc and a.pos.y > lowest_y) {
                                lowest_y = a.pos.y;
                                shooter_idx = idx;
                            }
                        }
                        if (shooter_idx) |si| {
                            try bullets.append(allocator, .{
                                .pos = aliens.items[si].pos,
                                .vel = .{ .x = 0, .y = 350 },
                                .from_player = false,
                                .column = @intCast(cc),
                            });
                            if (have_audio) app.audio.?.play(2); // alien laser
                        }
                    }
                }
            }

            // Update bullets
            var i: usize = 0;
            while (i < bullets.items.len) {
                var b = &bullets.items[i];
                b.pos.x += b.vel.x * dt;
                b.pos.y += b.vel.y * dt;
                if (b.pos.y < 0 or b.pos.y > fs.y) b.remove = true;

                // Bunker collision (check rod tip)
                if (!b.remove) {
                    const tip_offset: f32 = if (b.from_player) -20.0 else 16.0;
                    const tip: Vector2 = .{
                        .x = b.pos.x,
                        .y = b.pos.y + tip_offset,
                    };
                    for (&bunkers) |*bk| {
                        if (bk.hitTest(tip, 5)) {
                            b.remove = true;
                            break;
                        }
                    }
                }

                if (!b.remove) {
                    const tip_offset2: f32 = if (b.from_player) -20.0 else 16.0;
                    const tip: Vector2 = .{
                        .x = b.pos.x,
                        .y = b.pos.y + tip_offset2,
                    };
                    if (b.from_player) {
                        // Tight hit box — player must aim near the invader's center
                        const alien_radius = alien_spacing * 0.2;
                        for (aliens.items) |*a| {
                            if (a.alive and vgame.circleCollision(tip, 5, a.pos, alien_radius)) {
                                a.alive = false;
                                b.remove = true;
                                score += 100;
                                alive_count -= 1;
                                // Explosion fragments: 4-pixel squares totaling
                                // the invader's screen pixel area
                                const es = alien_spacing * 0.5;
                                const norm_area = if (a.shape_state == 0) ALIEN_AREA_A else ALIEN_AREA_B;
                                const screen_pixels: usize = @intFromFloat(
                                    norm_area * es * es * app.screen.render_scale * app.screen.render_scale,
                                );
                                try particles.spawnSquares(a.pos, screen_pixels, .{
                                    .color = vgame.Color.green,
                                    .scale = app.screen.scale,
                                    .speed = 250.0,
                                    .ttl = 1.0,
                                }, &rand);
                            }
                        }
                    } else {
                        // Tight hit box on player too — matches alien hit difficulty
                        const player_radius = alien_spacing * 0.2;
                        if (vgame.circleCollision(tip, 5, player.pos, player_radius)) {
                            b.remove = true;
                            player.lives -= 1;
                            if (have_audio) app.audio.?.play(0); // explosion
                            // Explosion fragments: 4-pixel squares totaling
                            // the player ship's screen pixel area
                            const es = alien_spacing * 0.5;
                            const screen_pixels: usize = @intFromFloat(
                                PLAYER_AREA * es * es * app.screen.render_scale * app.screen.render_scale,
                            );
                            try particles.spawnSquares(player.pos, screen_pixels, .{
                                .color = vgame.Color.red,
                                .scale = app.screen.scale,
                                .speed = 250.0,
                                .ttl = 1.25,
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
            if (alive_count == 0) {
                wave += 1;
                alien_dir = 1.0;
                const s = try spawnAliens(&aliens, allocator, fs.x);
                alien_spacing = s.spacing;
                alive_count = TOTAL_ALIENS;
                // Bunkers are NOT reset — damage persists across waves
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
                alien_dir = 1.0;
                alive_count = TOTAL_ALIENS;
                bullets.clearRetainingCapacity();
                const s = try spawnAliens(&aliens, allocator, fs.x);
                alien_spacing = s.spacing;
                spawnBunkers(&bunkers, fs.x, fs.y);
            }
        }

        // ── Render ────────────────────────────────────────────────
        var ctx = app.beginRender();
        defer ctx.end();

        // Player and aliens are the same size
        const entity_scale = alien_spacing * 0.5;

        // Aliens — alternating shapes per column, with eyes
        for (aliens.items) |a| {
            if (!a.alive) continue;
            if (a.shape_state == 0) {
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_SHAPE_A, true, vgame.Color.green);
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_EYE_L_A, true, vgame.Color.green);
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_EYE_R_A, true, vgame.Color.green);
            } else {
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_SHAPE_B, true, vgame.Color.green);
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_EYE_L_B, true, vgame.Color.green);
                ctx.drawLines(a.pos, entity_scale, 0, &ALIEN_EYE_R_B, true, vgame.Color.green);
            }
        }

        // Bunkers
        for (&bunkers) |*bk| {
            bk.draw(&ctx);
        }

        // Player (same scale as aliens)
        ctx.drawLines(player.pos, entity_scale, 0, &PLAYER_SHAPE, true, vgame.Color.white);

        // Bullets — vector-drawn rods
        for (bullets.items) |b| {
            const c: vgame.Color = if (b.from_player) vgame.Color.white else vgame.Color.red;
            // Rod: a short vertical line segment in the direction of travel
            const rod_len: f32 = if (b.from_player) 20.0 else 16.0;
            const dir: f32 = if (b.from_player) -1.0 else 1.0;
            const rod_pts = [_]Vector2{
                .{ .x = 0, .y = 0 },
                .{ .x = 0, .y = dir * rod_len },
            };
            ctx.drawLines(b.pos, 1.0, 0, &rod_pts, false, c);
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

        // Lives (drawn at top of screen, twice as big as before)
        for (0..player.lives) |li| {
            ctx.drawLines(
                .{ .x = 50 + @as(f32, @floatFromInt(li)) * 60, .y = 60 },
                app.screen.scale * 0.6,
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
                    "SPACE       Shoot (one bullet)",
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