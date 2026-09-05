// VecTetris — Vector-based Tetris with colored vector-drawn tetromino pieces
//
// Left/Right: move. Up: rotate clockwise. Down: soft drop. Space: hard drop.
// P: pause. R: restart after game over.
// 7 tetromino types (I, O, T, S, Z, L, J), each with a distinct color.
// Standard scoring: 1 line=100, 2=300, 3=500, 4=800. Level up every 10 lines.

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;

const GRID_W: usize = 10;
const GRID_H: usize = 20;
const CELL: f32 = 35.0; // pixel size of each cell
const LOCK_DELAY_TIME: f32 = 0.5; // grace period before locking (seconds)

// Tetromino shapes — each piece defined as 4 (row, col) offsets from a pivot.
// Rotations computed at runtime by rotating around the pivot.
const PieceType = enum(usize) { I, O, T, S, Z, L, J };
const PIECE_COUNT: usize = 7;

// Base shapes (row, col) for each piece type in each of 4 rotations.
// Uses the Super Rotation System (SRS) convention: pieces rotate around
// their geometric center. States are precomputed to avoid floating-point
// rounding issues with half-integer centroids.
const SHAPES = [PIECE_COUNT][4][4][2]i32{
    // I: horizontal line — rotates around center of the 4 cells
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 } },
        .{ .{ 0, 2 }, .{ 1, 2 }, .{ 2, 2 }, .{ 3, 2 } },
        .{ .{ 3, 0 }, .{ 3, 1 }, .{ 3, 2 }, .{ 3, 3 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 }, .{ 3, 0 } },
    },
    // O: 2x2 square — visually identical in all rotations
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } },
    },
    // T: T-shape — rotates around the center of the 3-wide top
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 1, 1 } },
        .{ .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 0 } },
    },
    // S: S-shape — rotates around center
    .{
        .{ .{ 0, 1 }, .{ 0, 2 }, .{ 1, 0 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, -1 }, .{ 1, 0 } },
        .{ .{ 0, -1 }, .{ 1, -1 }, .{ 1, 0 }, .{ 2, 0 } },
    },
    // Z: Z-shape — rotates around center
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 0 } },
        .{ .{ 0, -1 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 1 } },
    },
    // L: L-shape — rotates around center
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 1, 0 } },
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 0 }, .{ 2, 1 } },
        .{ .{ 0, 2 }, .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 2, 1 } },
    },
    // J: J-shape — rotates around center
    .{
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 1, 2 } },
        .{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 2, 0 } },
        .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 1, 2 } },
        .{ .{ 0, 1 }, .{ 1, 1 }, .{ 2, 0 }, .{ 2, 1 } },
    },
};

// Colors for each piece type (standard Tetris guideline colors)
const PIECE_COLORS = [PIECE_COUNT]vgame.Color{
    .{ .r = 0, .g = 255, .b = 255, .a = 255 }, // I = cyan
    .{ .r = 255, .g = 255, .b = 0, .a = 255 }, // O = yellow
    .{ .r = 200, .g = 0, .b = 255, .a = 255 }, // T = purple
    .{ .r = 0, .g = 255, .b = 0, .a = 255 }, // S = green
    .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Z = red
    .{ .r = 255, .g = 165, .b = 0, .a = 255 }, // L = orange
    .{ .r = 0, .g = 0, .b = 255, .a = 255 }, // J = blue
};

const Piece = struct {
    type: PieceType,
    /// Grid row/col of the pivot (top-left of the piece's bounding box).
    row: i32,
    col: i32,
    /// Current rotation state (0-3).
    rotation: u2 = 0,
};

const GameState = enum { normal, dissolving };

const Game = struct {
    grid: [GRID_H][GRID_W]?vgame.Color, // color = filled cell, null = empty
    piece: Piece,
    next: PieceType,
    score: usize = 0,
    lines: usize = 0,
    level: usize = 1,
    drop_timer: f32 = 0,
    drop_interval: f32 = 1.0,
    game_over: bool = false,
    paused: bool = false,
    touching: bool = false,   // piece is resting on something below
    lock_delay: f32 = 0,     // time since piece started touching
    state: GameState = .normal,
    dissolve_timer: f32 = 0,
    dissolve_rows: [4]usize = .{ 0, 0, 0, 0 },
    dissolve_count: usize = 0,

    fn init(rand: *std.Random) Game {
        const t: PieceType = @enumFromInt(rand.intRangeLessThan(usize, 0, PIECE_COUNT));
        var g = Game{
            .grid = @splat(@splat(null)),
            .piece = .{ .type = t, .row = 0, .col = 3 },
            .next = @enumFromInt(rand.intRangeLessThan(usize, 0, PIECE_COUNT)),
        };
        if (!g.isValidPos(g.piece)) {
            g.game_over = true;
        }
        return g;
    }

    fn spawnNew(self: *Game, rand: *std.Random) void {
        // The previewed 'next' piece becomes the active piece
        self.piece = .{ .type = self.next, .row = 0, .col = 3, .rotation = 0 };
        // Roll a new 'next' piece for the preview
        self.next = @enumFromInt(rand.intRangeLessThan(usize, 0, PIECE_COUNT));
        self.touching = false;
        self.lock_delay = 0;
        if (!self.isValidPos(self.piece)) {
            self.game_over = true;
        }
    }

    /// Get the 4 cell coordinates for a piece in its current rotation.
    /// Uses precomputed SRS rotation states — each piece type has 4
    /// explicit shape tables, so no runtime rotation math is needed.
    fn getCells(piece: Piece) [4][2]i32 {
        var cells: [4][2]i32 = undefined;
        const shape = SHAPES[@intFromEnum(piece.type)][piece.rotation];
        for (shape, 0..) |s, i| {
            cells[i] = .{ piece.row + s[0], piece.col + s[1] };
        }
        return cells;
    }

    /// Check if the piece's current position is valid (all cells empty and in-bounds).
    fn isValidPos(self: *const Game, piece: Piece) bool {
        const cells = getCells(piece);
        for (cells) |cell| {
            const r = cell[0];
            const c = cell[1];
            if (c < 0 or c >= GRID_W) return false;
            if (r >= GRID_H) return false;
            if (r >= 0 and self.grid[@intCast(r)][@intCast(c)] != null) return false;
        }
        return true;
    }

    fn tryMove(self: *Game, drow: i32, dcol: i32) bool {
        var p = self.piece;
        p.row += drow;
        p.col += dcol;
        if (self.isValidPos(p)) {
            self.piece = p;
            return true;
        }
        return false;
    }

    fn tryRotate(self: *Game) bool {
        var p = self.piece;
        p.rotation = @addWithOverflow(p.rotation, 1)[0];
        // Wall kick: try shifting left/right if rotation collides with wall
        const kicks = [_]i32{ 0, -1, 1, -2, 2 };
        for (kicks) |kick| {
            p.col = self.piece.col + kick;
            if (self.isValidPos(p)) {
                self.piece = p;
                return true;
            }
        }
        return false;
    }

    fn lockPiece(self: *Game, rand: *std.Random) void {
        const cells = getCells(self.piece);
        const color = PIECE_COLORS[@intFromEnum(self.piece.type)];
        for (cells) |cell| {
            const r = cell[0];
            const c = cell[1];
            if (r >= 0 and r < GRID_H and c >= 0 and c < GRID_W) {
                self.grid[@intCast(r)][@intCast(c)] = color;
            }
        }
        var count: usize = 0;
        for (0..GRID_H) |row| {
            var full = true;
            for (0..GRID_W) |c| {
                if (self.grid[row][c] == null) { full = false; break; }
            }
            if (full) {
                self.dissolve_rows[count] = row;
                count += 1;
            }
        }
        self.dissolve_count = count;
        if (count > 0) {
            self.state = .dissolving;
            self.dissolve_timer = 0;
        }
        self.spawnNew(rand);
    }

    fn finishClearLines(self: *Game) void {
        const cleared = self.dissolve_count;
        const rows: [4]usize = self.dissolve_rows;
        // Process bottom-up so shifts don't interfere
        for (0..cleared) |i| {
            const row = rows[cleared - 1 - i];
            var r = row;
            while (r > 0) {
                r -= 1;
                self.grid[r + 1] = self.grid[r];
            }
            self.grid[0] = @splat(null);
        }
        self.dissolve_count = 0;
        self.state = .normal;
        if (cleared > 0) {
            const points = [_]usize{ 0, 100, 300, 500, 800 };
            self.score += points[cleared] * self.level;
            self.lines += cleared;
            self.level = 1 + self.lines / 10;
            self.drop_interval = @max(0.1, 1.0 - @as(f32, @floatFromInt(self.level - 1)) * 0.1);
        }
    }

    fn hardDrop(self: *Game, rand: *std.Random) void {
        while (self.tryMove(1, 0)) {}
        self.lockPiece(rand);
    }
};

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
        .title = "VecTetris",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
    });
    defer app.deinit();

    var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
    var rand = prng.random();

    var game = Game.init(&rand);

    // Playfield offset to center it on screen
    const grid_w_px = @as(f32, @floatFromInt(GRID_W)) * CELL;
    const grid_h_px = @as(f32, @floatFromInt(GRID_H)) * CELL;
    const grid_x: f32 = (1280 - grid_w_px) / 2 - 150; // shift left to make room for preview
    const grid_y: f32 = (960 - grid_h_px) / 2;

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        if (!game.game_over and !game.paused) {
            if (game.state == .dissolving) {
                // Row dissolve animation — no input or gravity while dissolving
                game.dissolve_timer += dt;
                if (game.dissolve_timer >= 0.5) {
                    game.dissolve_timer = 0;
                    game.finishClearLines();
                }
            } else {
                // Input — player can always move/rotate, even while touching
                if (rl.isKeyPressed(.left)) _ = game.tryMove(0, -1);
                if (rl.isKeyPressed(.right)) _ = game.tryMove(0, 1);
                if (rl.isKeyPressed(.up)) _ = game.tryRotate();
                if (rl.isKeyDown(.down)) {
                    if (game.tryMove(1, 0)) game.drop_timer = 0;
                }
                if (rl.isKeyPressed(.space)) {
                    game.hardDrop(&rand);
                }

                // Gravity + lock delay
                game.drop_timer += dt;
                if (game.drop_timer >= game.drop_interval) {
                    game.drop_timer = 0;
                    if (game.tryMove(1, 0)) {
                        // Piece moved down successfully — no longer touching
                        game.touching = false;
                        game.lock_delay = 0;
                    } else {
                        // Can't move down — piece is touching something
                        if (!game.touching) {
                            game.touching = true;
                            game.lock_delay = 0;
                        }
                    }
                }

                // If touching, count up the lock delay. If the player slid
                // the piece into a gap (tryMove succeeds), un-touch.
                if (game.touching) {
                    game.lock_delay += dt;
                    // Check if the piece can now fall (maybe it was nudged sideways)
                    if (game.tryMove(1, 0)) {
                        game.touching = false;
                        game.lock_delay = 0;
                        game.drop_timer = 0;
                    } else if (game.lock_delay >= LOCK_DELAY_TIME) {
                        // Grace period expired — lock the piece
                        game.lockPiece(&rand);
                    }
                }

                if (rl.isKeyPressed(.p)) game.paused = true;
            }
        } else if (game.paused) {
            if (rl.isKeyPressed(.p) or rl.isKeyPressed(.space)) game.paused = false;
        } else if (game.game_over) {
            if (rl.isKeyPressed(.r)) {
                game = Game.init(&rand);
            }
        }

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Grid border
        ctx.drawRectLines(.{
            .x = grid_x - 3,
            .y = grid_y - 3,
            .width = grid_w_px + 6,
            .height = grid_h_px + 6,
        }, 3, vgame.Color.white);

        // Grid background
        ctx.drawRect(.{
            .x = grid_x,
            .y = grid_y,
            .width = grid_w_px,
            .height = grid_h_px,
        }, .{ .r = 10, .g = 10, .b = 20, .a = 255 });

        // Draw filled cells
        for (0..GRID_H) |r| {
            for (0..GRID_W) |c| {
                if (game.grid[r][c]) |color| {
                    drawCell(&ctx, grid_x + @as(f32, @floatFromInt(c)) * CELL,
                        grid_y + @as(f32, @floatFromInt(r)) * CELL, color);
                }
            }
        }

        // Row dissolve animation: white flash fading out over completed rows
        if (game.state == .dissolving) {
            const progress = @min(1.0, game.dissolve_timer / 0.5);
            const white = vgame.Color{ .r = 255, .g = 255, .b = 255, .a = @intCast(@as(u32, @intFromFloat(@min(255, @max(0, (1.0 - progress) * 255.0))))) };
            for (0..game.dissolve_count) |i| {
                const row = game.dissolve_rows[i];
                for (0..GRID_W) |c| {
                    ctx.drawRect(.{
                        .x = grid_x + @as(f32, @floatFromInt(c)) * CELL,
                        .y = grid_y + @as(f32, @floatFromInt(row)) * CELL,
                        .width = CELL,
                        .height = CELL,
                    }, white);
                }
            }
        }

        // Draw current piece (ghost + actual)
        const cells = Game.getCells(game.piece);
        const piece_color = PIECE_COLORS[@intFromEnum(game.piece.type)];

        // Ghost piece: show where it would land
        var ghost_piece = game.piece;
        while (blk: {
            var p = ghost_piece;
            p.row += 1;
            if (game.isValidPos(p)) {
                ghost_piece = p;
                break :blk true;
            }
            break :blk false;
        }) {}
        const ghost_cells = Game.getCells(ghost_piece);
        for (ghost_cells) |cell| {
            if (cell[0] >= 0) {
                drawGhostCell(&ctx, grid_x + @as(f32, @floatFromInt(cell[1])) * CELL,
                    grid_y + @as(f32, @floatFromInt(cell[0])) * CELL, piece_color);
            }
        }

        // Actual piece
        for (cells) |cell| {
            if (cell[0] >= 0) {
                drawCell(&ctx, grid_x + @as(f32, @floatFromInt(cell[1])) * CELL,
                    grid_y + @as(f32, @floatFromInt(cell[0])) * CELL, piece_color);
            }
        }

        // Grid lines (faint)
        for (1..GRID_W) |c| {
            const x = grid_x + @as(f32, @floatFromInt(c)) * CELL;
            ctx.drawLine(.{ .x = x, .y = grid_y }, .{ .x = x, .y = grid_y + grid_h_px }, 1,
                .{ .r = 40, .g = 40, .b = 50, .a = 255 });
        }
        for (1..GRID_H) |r| {
            const y = grid_y + @as(f32, @floatFromInt(r)) * CELL;
            ctx.drawLine(.{ .x = grid_x, .y = y }, .{ .x = grid_x + grid_w_px, .y = y }, 1,
                .{ .r = 40, .g = 40, .b = 50, .a = 255 });
        }

        // Next piece preview
        const preview_x = grid_x + grid_w_px + 60;
        const preview_y = grid_y;
        ctx.drawText("NEXT", @as(i32, @intFromFloat(preview_x)), @as(i32, @intFromFloat(preview_y)), 24, vgame.Color.white);
        const next_shape = SHAPES[@intFromEnum(game.next)][0]; // rotation 0 for preview
        const next_color = PIECE_COLORS[@intFromEnum(game.next)];
        for (next_shape) |s| {
            drawCell(&ctx, preview_x + @as(f32, @floatFromInt(s[1])) * (CELL * 0.7),
                preview_y + 40 + @as(f32, @floatFromInt(s[0])) * (CELL * 0.7), next_color);
        }

        // Score, level, lines — positioned right of the grid with enough
        // room for drawNumber (which draws digits right-to-left from x)
        const stats_x = grid_x + grid_w_px + 60;
        const stats_x_right = stats_x + 200; // right edge for drawNumber
        const stats_y = preview_y + 200;
        ctx.drawText("SCORE", @as(i32, @intFromFloat(stats_x)), @as(i32, @intFromFloat(stats_y)), 24, vgame.Color.white);
        ctx.drawNumber(game.score, .{ .x = stats_x_right, .y = stats_y + 35 });

        ctx.drawText("LINES", @as(i32, @intFromFloat(stats_x)), @as(i32, @intFromFloat(stats_y + 90)), 24, vgame.Color.white);
        ctx.drawNumber(game.lines, .{ .x = stats_x_right, .y = stats_y + 125 });

        ctx.drawText("LEVEL", @as(i32, @intFromFloat(stats_x)), @as(i32, @intFromFloat(stats_y + 180)), 24, vgame.Color.white);
        ctx.drawNumber(game.level, .{ .x = stats_x_right, .y = stats_y + 215 });

        // Controls hint
        const ctrl_x = grid_x - 200;
        if (ctrl_x > 10) {
            ctx.drawText("CONTROLS", @as(i32, @intFromFloat(ctrl_x)), 100, 24, vgame.Color.white);
            ctx.drawText("L/R  Move", @as(i32, @intFromFloat(ctrl_x)), 140, 20, vgame.Color.gray);
            ctx.drawText("UP   Rotate", @as(i32, @intFromFloat(ctrl_x)), 165, 20, vgame.Color.gray);
            ctx.drawText("DOWN Soft Drop", @as(i32, @intFromFloat(ctrl_x)), 190, 20, vgame.Color.gray);
            ctx.drawText("SPACE Hard Drop", @as(i32, @intFromFloat(ctrl_x)), 215, 20, vgame.Color.gray);
            ctx.drawText("P    Pause", @as(i32, @intFromFloat(ctrl_x)), 240, 20, vgame.Color.gray);
        }

        // Overlays
        if (game.paused) {
            vgame.drawOverlay(fs, .{
                .title = "PAUSED",
                .lines = &.{
                    "P or SPACE to resume",
                    "",
                    "L/R   Move piece",
                    "UP    Rotate",
                    "DOWN  Soft drop",
                    "SPACE Hard drop",
                },
            });
        }
        if (game.game_over) {
            var score_buf: [64:0]u8 = undefined;
            const score_str = std.fmt.bufPrintZ(&score_buf, "Final Score: {d}", .{game.score}) catch unreachable;
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

/// Draw a single cell as a filled vector square with a colored border.
fn drawCell(ctx: *const vgame.RenderContext, x: f32, y: f32, color: vgame.Color) void {
    // Filled background (slightly darker)
    const dark = vgame.Color{
        .r = @intCast(@as(u32, color.r) * 3 / 5),
        .g = @intCast(@as(u32, color.g) * 3 / 5),
        .b = @intCast(@as(u32, color.b) * 3 / 5),
        .a = 255,
    };
    ctx.drawRect(.{ .x = x + 1, .y = y + 1, .width = CELL - 2, .height = CELL - 2 }, dark);
    // Colored border
    ctx.drawRectLines(.{ .x = x + 1, .y = y + 1, .width = CELL - 2, .height = CELL - 2 }, 2, color);
    // Inner highlight (top-left, gives 3D look)
    ctx.drawLine(.{ .x = x + 3, .y = y + 3 }, .{ .x = x + CELL - 4, .y = y + 3 }, 1,
        .{ .r = @intCast(@min(255, @as(u32, color.r) + 60)), .g = @intCast(@min(255, @as(u32, color.g) + 60)), .b = @intCast(@min(255, @as(u32, color.b) + 60)), .a = 255 });
    ctx.drawLine(.{ .x = x + 3, .y = y + 3 }, .{ .x = x + 3, .y = y + CELL - 4 }, 1,
        .{ .r = @intCast(@min(255, @as(u32, color.r) + 60)), .g = @intCast(@min(255, @as(u32, color.g) + 60)), .b = @intCast(@min(255, @as(u32, color.b) + 60)), .a = 255 });
}

/// Draw a ghost cell (outline only, semi-transparent).
fn drawGhostCell(ctx: *const vgame.RenderContext, x: f32, y: f32, color: vgame.Color) void {
    const ghost_color = vgame.Color{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = 80,
    };
    ctx.drawRectLines(.{ .x = x + 2, .y = y + 2, .width = CELL - 4, .height = CELL - 4 }, 1, ghost_color);
}