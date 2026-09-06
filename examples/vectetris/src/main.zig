// VecTetris — Vector-based Tetris with colored vector-drawn tetromino pieces
//
// Left/Right: move. Up: rotate clockwise. Down: soft drop. Space: hard drop.
// P: pause. R: restart after game over. M: toggle music.
// 7 tetromino types (I, O, T, S, Z, L, J), each with a distinct color.
// 7-bag randomizer ensures fair piece distribution.
// Standard scoring: 1 line=100, 2=300, 3=500, 4=800. Level up every 10 lines.
// Lock delay: 0.5s grace period when a piece can't fall. During this
// period the player can slide the piece horizontally up to 2 squares
// (each slide resets the timer), allowing last-second adjustments.
//
// Background music: resources/tetris.xm (XM module format, played via
// raylib's built-in module loader). Music pauses with the game, stops
// on game over, and restarts on new game. Press M to toggle music on/off
// — the toggle remembers the playback position and resumes from there.
//
// Xbox gamepad: D-pad left/right to move, D-pad up to rotate, D-pad down
// to soft drop, A to hard drop, Back to pause. Read through a single
// vgame.InputManager (gamepad_index 0), which falls back to raw
// /dev/input/js0 polling when raylib's GLFW/SDL mapping doesn't
// recognize the controller.

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;

// Actions bound to both keyboard and gamepad 0 — see BINDINGS below.
const Action = enum { move_left, move_right, rotate, soft_drop, hard_drop, pause, restart };
const action_count = @typeInfo(Action).@"enum".fields.len;

const BINDINGS = vgame.InputBindings{
    .keyboard = &.{
        .{ .key = .left },
        .{ .key = .right },
        .{ .key = .up },
        .{ .key = .down },
        .{ .key = .space },
        .{ .key = .p },
        .{ .key = .r },
    },
    .gamepad = &.{
        .{ .button = .left_face_left },
        .{ .button = .left_face_right },
        .{ .button = .left_face_up },
        .{ .button = .left_face_down },
        .{ .button = .right_face_down },
        .{ .button = .middle_left },
        .{ .button = .right_face_down },
    },
};

const GRID_W: usize = 10;
const GRID_H: usize = 20;
const CELL: f32 = 35.0; // pixel size of each cell
const LOCK_DELAY_TIME: f32 = 0.5; // grace period before locking (seconds)
const MAX_SLIDES: usize = 2; // max horizontal slides during lock delay before forced lock

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
    slide_count: usize = 0,  // horizontal slides used during current lock delay
    state: GameState = .normal,
    dissolve_timer: f32 = 0,
    dissolve_rows: [4]usize = .{ 0, 0, 0, 0 },
    dissolve_count: usize = 0,
    // 7-bag randomizer: each bag contains all 7 piece types in random
    // order. Deal from the bag; when empty, refill and shuffle.
    bag: [PIECE_COUNT]PieceType = undefined,
    bag_pos: usize = PIECE_COUNT, // start empty so first init refills

    fn init(rand: *std.Random) Game {
        var g = Game{
            .grid = @splat(@splat(null)),
            .piece = .{ .type = .I, .row = 0, .col = 3 },
            .next = .I,
        };
        g.refillBag(rand);
        g.piece = .{ .type = g.bag[g.bag_pos], .row = 0, .col = 3, .rotation = 0 };
        g.bag_pos += 1;
        g.next = g.bag[g.bag_pos];
        g.bag_pos += 1;
        if (!g.isValidPos(g.piece)) {
            g.game_over = true;
        }
        return g;
    }

    /// Shuffle the bag with all 7 piece types using Fisher-Yates.
    fn refillBag(self: *Game, rand: *std.Random) void {
        // Fill with all piece types in enum order
        for (0..PIECE_COUNT) |i| {
            self.bag[i] = @enumFromInt(i);
        }
        // Fisher-Yates shuffle
        var i: usize = PIECE_COUNT;
        while (i > 1) {
            i -= 1;
            const j = rand.intRangeLessThan(usize, 0, i + 1);
            const tmp = self.bag[i];
            self.bag[i] = self.bag[j];
            self.bag[j] = tmp;
        }
        self.bag_pos = 0;
    }

    /// Draw the next piece type from the bag, refilling if empty.
    fn drawFromBag(self: *Game, rand: *std.Random) PieceType {
        if (self.bag_pos >= PIECE_COUNT) {
            self.refillBag(rand);
        }
        const pt = self.bag[self.bag_pos];
        self.bag_pos += 1;
        return pt;
    }

    fn spawnNew(self: *Game, rand: *std.Random) void {
        // The previewed 'next' piece becomes the active piece
        self.piece = .{ .type = self.next, .row = 0, .col = 3, .rotation = 0 };
        // Draw a new 'next' piece from the 7-bag
        self.next = self.drawFromBag(rand);
        self.touching = false;
        self.lock_delay = 0;
        self.slide_count = 0;
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

    fn lockPiece(self: *Game) void {
        const cells = getCells(self.piece);
        const color = PIECE_COLORS[@intFromEnum(self.piece.type)];
        for (cells) |cell| {
            const r = cell[0];
            const c = cell[1];
            if (r >= 0 and r < GRID_H and c >= 0 and c < GRID_W) {
                self.grid[@intCast(r)][@intCast(c)] = color;
            }
        }
        // Detect completed rows
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
            // Enter dissolve state — new piece spawns after dissolve finishes
            self.state = .dissolving;
            self.dissolve_timer = 0;
        } else {
            // No lines cleared — spawn next piece immediately
            // (handled by caller via spawnNextAfterLock)
        }
    }

    /// Called after lockPiece when no lines were cleared, OR after
    /// finishClearLines when the dissolve animation is done.
    fn spawnNextAfterLock(self: *Game, rand: *std.Random) void {
        self.spawnNew(rand);
    }

    fn finishClearLines(self: *Game, rand: *std.Random) void {
        const cleared = self.dissolve_count;
        // Compact the grid: copy all non-completed rows from bottom to top,
        // then fill the vacated rows at the top with empty. This avoids the
        // stale-row-index bug that occurs when shifting rows one at a time
        // (each shift invalidates the stored indices of rows above it).
        if (cleared > 0) {
            // Build a set of completed row indices for O(1) lookup
            var is_complete = [_]bool{false} ** GRID_H;
            for (0..cleared) |i| {
                is_complete[self.dissolve_rows[i]] = true;
            }
            // Compact: walk from bottom to top, keeping non-completed rows
            var write_row: usize = GRID_H;
            var read_row: usize = GRID_H;
            while (read_row > 0) {
                read_row -= 1;
                if (!is_complete[read_row]) {
                    write_row -= 1;
                    if (write_row != read_row) {
                        self.grid[write_row] = self.grid[read_row];
                    }
                }
            }
            // Fill vacated rows at the top with empty
            while (write_row > 0) {
                write_row -= 1;
                self.grid[write_row] = @splat(null);
            }

            // Scoring
            const points = [_]usize{ 0, 100, 300, 500, 800 };
            self.score += points[cleared] * self.level;
            self.lines += cleared;
            self.level = 1 + self.lines / 10;
            self.drop_interval = @max(0.1, 1.0 - @as(f32, @floatFromInt(self.level - 1)) * 0.1);
        }
        self.dissolve_count = 0;
        self.state = .normal;
        // Now spawn the next piece — this happens after rows are cleared,
        // so the new piece sees a clean grid
        self.spawnNew(rand);
    }

    fn hardDrop(self: *Game, rand: *std.Random) void {
        while (self.tryMove(1, 0)) {}
        self.lockPiece();
        if (self.dissolve_count == 0) {
            self.spawnNextAfterLock(rand);
        }
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
        .glow = true,
        .msaa = true,
    });
    defer app.deinit();

    var input = vgame.InputManager.init(allocator, &BINDINGS, action_count, 0);
    defer input.deinit();

    // Audio — load the background music module
    rl.initAudioDevice();
    var music: ?rl.Music = null;
    music = rl.loadMusicStream("resources/tetris.xm") catch |err| blk: {
        std.log.warn("Failed to load tetris.xm (game will be silent): {}", .{err});
        break :blk null;
    };
    defer if (music) |*m| rl.unloadMusicStream(m.*);
    if (music) |*m| {
        rl.setMusicVolume(m.*, 0.5);
        rl.playMusicStream(m.*);
    }

    // Music mute toggle — remembers playback position to restore on unmute
    var music_muted: bool = false;
    var music_resume_pos: f32 = 0.0;

    // Horizontal auto-repeat (DAS — Delayed Auto Shift)
    // Initial delay before repeating, then interval between repeats.
    const DAS_DELAY: f32 = 0.17;
    const DAS_REPEAT: f32 = 0.05;
    var das_timer: f32 = 0;
    var das_dir: i32 = 0; // -1 = left, +1 = right, 0 = none

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

        input.update();

        // Update music stream every frame (required by raylib)
        if (music) |m| rl.updateMusicStream(m);

        // M key toggles music mute, remembering playback position
        if (rl.isKeyPressed(.m)) {
            if (music) |m| {
                if (music_muted) {
                    // Unmute — seek to saved position and resume
                    rl.seekMusicStream(m, music_resume_pos);
                    rl.resumeMusicStream(m);
                    music_muted = false;
                } else {
                    // Mute — save position and pause
                    music_resume_pos = rl.getMusicTimePlayed(m);
                    rl.pauseMusicStream(m);
                    music_muted = true;
                }
            }
        }

        if (!game.game_over and !game.paused) {
            if (game.state == .dissolving) {
                // Row dissolve animation — no input or gravity while dissolving
                game.dissolve_timer += dt;
                if (game.dissolve_timer >= 0.5) {
                    game.dissolve_timer = 0;
                    game.finishClearLines(&rand);
                }
            } else {
                // Input — player can always move/rotate, even while touching

                // Horizontal movement with DAS auto-repeat.
                // Pressing left/right moves once immediately. Holding past
                // DAS_DELAY triggers repeating at DAS_REPEAT interval.
                // Supports both keyboard arrows and Xbox D-pad.
                // While touching (lock delay active), each successful
                // horizontal move counts as a "slide" — up to MAX_SLIDES
                // slides reset the lock delay timer, giving the player
                // time to nudge the piece into position.
                var did_slide: bool = false;
                const left_down = input.isDown(@intFromEnum(Action.move_left));
                const right_down = input.isDown(@intFromEnum(Action.move_right));
                const left_pressed = input.isPressed(@intFromEnum(Action.move_left));
                const right_pressed = input.isPressed(@intFromEnum(Action.move_right));

                // Determine active direction — new key press takes priority
                if (left_pressed) {
                    das_dir = -1;
                    das_timer = 0;
                    if (game.tryMove(0, -1)) did_slide = game.touching;
                } else if (right_pressed) {
                    das_dir = 1;
                    das_timer = 0;
                    if (game.tryMove(0, 1)) did_slide = game.touching;
                } else if (left_down and das_dir == -1) {
                    // Holding left — advance DAS timer
                    das_timer += dt;
                    if (das_timer >= DAS_DELAY) {
                        // After initial delay, repeat at faster interval
                        const repeat_timer = das_timer - DAS_DELAY;
                        if (repeat_timer >= DAS_REPEAT) {
                            das_timer = DAS_DELAY; // reset to delay threshold
                            if (game.tryMove(0, -1)) did_slide = game.touching;
                        }
                    }
                } else if (right_down and das_dir == 1) {
                    // Holding right — advance DAS timer
                    das_timer += dt;
                    if (das_timer >= DAS_DELAY) {
                        const repeat_timer = das_timer - DAS_DELAY;
                        if (repeat_timer >= DAS_REPEAT) {
                            das_timer = DAS_DELAY;
                            if (game.tryMove(0, 1)) did_slide = game.touching;
                        }
                    }
                } else if (!left_down and !right_down) {
                    // Both released — reset DAS
                    das_dir = 0;
                    das_timer = 0;
                } else if (left_down and das_dir != -1) {
                    // Switched from right to left
                    das_dir = -1;
                    das_timer = 0;
                    if (game.tryMove(0, -1)) did_slide = game.touching;
                } else if (right_down and das_dir != 1) {
                    // Switched from left to right
                    das_dir = 1;
                    das_timer = 0;
                    if (game.tryMove(0, 1)) did_slide = game.touching;
                }

                // If the piece was touching and just slid horizontally,
                // count the slide and reset the lock delay (up to MAX_SLIDES).
                if (did_slide and game.touching) {
                    if (game.slide_count < MAX_SLIDES) {
                        game.slide_count += 1;
                        game.lock_delay = 0;
                    }
                    // After MAX_SLIDES, the lock delay keeps counting —
                    // no more resets, piece will lock when timer expires.
                }

                if (input.isPressed(@intFromEnum(Action.rotate))) _ = game.tryRotate();
                if (input.isDown(@intFromEnum(Action.soft_drop))) {
                    if (game.tryMove(1, 0)) game.drop_timer = 0;
                }
                if (input.isPressed(@intFromEnum(Action.hard_drop))) {
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
                        game.slide_count = 0;
                    } else {
                        // Can't move down — piece is touching something
                        if (!game.touching) {
                            game.touching = true;
                            game.lock_delay = 0;
                            game.slide_count = 0;
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
                        game.slide_count = 0;
                        game.drop_timer = 0;
                    } else if (game.lock_delay >= LOCK_DELAY_TIME) {
                        // Grace period expired — lock the piece
                        game.lockPiece();
                        if (game.dissolve_count == 0) {
                            game.spawnNextAfterLock(&rand);
                        }
                    }
                }

                if (input.isPressed(@intFromEnum(Action.pause))) {
                    game.paused = true;
                    if (music) |m| rl.pauseMusicStream(m);
                }
            }
        } else if (game.paused) {
            if (input.isPressed(@intFromEnum(Action.pause)) or input.isPressed(@intFromEnum(Action.hard_drop))) {
                game.paused = false;
                // Only resume music if it wasn't user-muted
                if (music) |m| {
                    if (!music_muted) rl.resumeMusicStream(m);
                }
            }
        } else if (game.game_over) {
            if (music) |m| {
                if (rl.isMusicStreamPlaying(m)) rl.stopMusicStream(m);
            }
            if (input.isPressed(@intFromEnum(Action.restart))) {
                game = Game.init(&rand);
                // Restart music from beginning (unless user-muted)
                if (music) |m| {
                    if (!music_muted) {
                        rl.playMusicStream(m);
                    } else {
                        // Even if muted, restart the stream so position is fresh
                        music_resume_pos = 0.0;
                    }
                }
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

        // Draw current piece (ghost + actual) — skip during dissolve
        // because the piece is already locked into the grid
        if (game.state != .dissolving and !game.game_over) {
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
            ctx.drawText("M    Music on/off", @as(i32, @intFromFloat(ctrl_x)), 265, 20, vgame.Color.gray);
        }

        // Gamepad connection indicator
        if (input.isGamepadConnected()) {
            var gp_buf: [128:0]u8 = undefined;
            const gp_str = std.fmt.bufPrintZ(&gp_buf, "Gamepad: {s}", .{input.gamepadName()}) catch "Gamepad connected";
            ctx.drawText(gp_str, 10, @as(i32, @intFromFloat(fs.y)) - 30, 18, vgame.Color.gray);
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