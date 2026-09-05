// VecLander — Lunar Lander built on the vgame platform
//
// Rotate with Left/Right, thrust with Up. Gravity pulls you down.
// Land on flat terrain sections slowly and level. Too fast or tilted = crash.
// Fuel is limited. R restarts after landing/crash.

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;
const math = std.math;

const GRAVITY: f32 = 50.0;
const THRUST_POWER: f32 = 150.0;
const ROT_SPEED: f32 = 2.5;
const FUEL_MAX: f32 = 1000.0;
const FUEL_BURN: f32 = 25.0;
const SAFE_SPEED: f32 = 60.0;
const SAFE_ANGLE: f32 = 0.35; // radians from upright

const LANDER_LINES = [_]Vector2{
    .{ .x = -0.3, .y = -0.4 },
    .{ .x = 0.3, .y = -0.4 },
    .{ .x = 0.2, .y = 0.2 },
    .{ .x = 0.4, .y = 0.5 },
    .{ .x = -0.4, .y = 0.5 },
    .{ .x = -0.2, .y = 0.2 },
    .{ .x = -0.3, .y = -0.4 },
};

const FLAME_LINES = [_]Vector2{
    .{ .x = -0.15, .y = 0.5 },
    .{ .x = 0.0, .y = 1.2 },
    .{ .x = 0.15, .y = 0.5 },
};

const Lander = struct {
    pos: Vector2,
    vel: Vector2,
    rot: f32 = 0,
    fuel: f32 = FUEL_MAX,
    alive: bool = true,
    landed: bool = false,
};

const Pad = struct { start: usize, end: usize };

const Terrain = struct {
    points: []Vector2,
    /// Index ranges that are flat landing pads (start, end indices into points).
    pads: []const Pad,
    allocator: std.mem.Allocator,

    fn deinit(self: *Terrain) void {
        self.allocator.free(self.points);
        self.allocator.free(self.pads);
    }

    /// Get terrain height at a given x position.
    fn heightAt(self: *const Terrain, x: f32) f32 {
        const pts = self.points;
        for (pts[0..pts.len - 1], 1..) |_, i| {
            if (x >= pts[i - 1].x and x <= pts[i].x) {
                const t = (x - pts[i - 1].x) / (pts[i].x - pts[i - 1].x);
                return pts[i - 1].y + t * (pts[i].y - pts[i - 1].y);
            }
        }
        return pts[pts.len - 1].y;
    }

    /// Check if x is over a flat landing pad.
    fn isOverPad(self: *const Terrain, x: f32) bool {
        for (self.pads) |pad| {
            if (x >= self.points[pad.start].x and x <= self.points[pad.end].x) {
                return true;
            }
        }
        return false;
    }
};

fn generateTerrain(allocator: std.mem.Allocator, rand: *std.Random, width: f32) !Terrain {
    const segments: usize = 30;
    var points = try allocator.alloc(Vector2, segments);

    const base_y: f32 = 750.0;
    var pad_indices = std.ArrayList(Pad).empty;

    var x: f32 = 0;
    for (0..segments) |i| {
        var y: f32 = base_y + rand.float(f32) * 150;
        // Create flat landing pads every ~8 segments
        if (i > 0 and i % 8 == 0 and i < segments - 2) {
            // Make 2 consecutive flat points
            y = base_y + 50;
            try pad_indices.append(allocator, .{ .start = i, .end = i + 1 });
        }
        points[i] = .{ .x = x, .y = y };
        x += width / @as(f32, @floatFromInt(segments - 1));
    }

    const pads = try pad_indices.toOwnedSlice(allocator);

    return .{
        .points = points,
        .pads = pads,
        .allocator = allocator,
    };
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
        .title = "VecLander",
        .design_size = .{ .x = 1280, .y = 960 },
        .base_scale = 38.0,
        .glow = true,
        .msaa = true,
    });
    defer app.deinit();

    var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
    var rand = prng.random();

    const fs = app.screen.size;
    var terrain = try generateTerrain(allocator, &rand, fs.x);
    defer terrain.deinit();

    var lander = Lander{
        .pos = .{ .x = fs.x / 2, .y = 100 },
        .vel = .{ .x = 50, .y = 0 },
    };

    var thrusting = false;

    while (app.frame()) {
        const dt = app.delta;
        const field = app.screen.size;

        thrusting = false;

        if (lander.alive and !lander.landed) {
            // Rotation
            if (rl.isKeyDown(.left)) lander.rot -= ROT_SPEED * dt;
            if (rl.isKeyDown(.right)) lander.rot += ROT_SPEED * dt;

            // Thrust
            if (rl.isKeyDown(.up) and lander.fuel > 0) {
                const angle = lander.rot - math.pi / 2.0;
                const dir = Vector2{ .x = math.cos(angle), .y = math.sin(angle) };
                lander.vel.x += dir.x * THRUST_POWER * dt;
                lander.vel.y += dir.y * THRUST_POWER * dt;
                lander.fuel -= FUEL_BURN * dt;
                thrusting = true;
            }

            // Gravity
            lander.vel.y += GRAVITY * dt;

            // Move
            lander.pos.x += lander.vel.x * dt;
            lander.pos.y += lander.vel.y * dt;

            // Screen wrap horizontally
            if (lander.pos.x < 0) lander.pos.x += field.x;
            if (lander.pos.x > field.x) lander.pos.x -= field.x;

            // Terrain collision
            const ground_y = terrain.heightAt(lander.pos.x);
            if (lander.pos.y >= ground_y - 15) {
                const speed = @sqrt(lander.vel.x * lander.vel.x + lander.vel.y * lander.vel.y);
                const level = @abs(lander.rot) < SAFE_ANGLE;
                const over_pad = terrain.isOverPad(lander.pos.x);

                if (speed < SAFE_SPEED and level and over_pad) {
                    lander.landed = true;
                    lander.pos.y = ground_y - 15;
                    lander.vel = .{ .x = 0, .y = 0 };
                } else {
                    lander.alive = false;
                }
            }
        } else {
            // Restart
            if (rl.isKeyPressed(.r)) {
                lander = .{
                    .pos = .{ .x = field.x / 2, .y = 100 },
                    .vel = .{ .x = 50, .y = 0 },
                    .fuel = FUEL_MAX,
                };
            }
        }

        // Render
        var ctx = app.beginRender();
        defer ctx.end();

        // Terrain (vector polyline)
        ctx.drawPolyline(terrain.points, 3, vgame.Color.green);

        // Highlight landing pads
        for (terrain.pads) |pad| {
            const p1 = terrain.points[pad.start];
            const p2 = terrain.points[pad.end];
            ctx.drawLine(
                .{ .x = p1.x, .y = p1.y },
                .{ .x = p2.x, .y = p2.y },
                5,
                vgame.Color.yellow,
            );
        }

        // Lander
        const lander_color: vgame.Color = if (lander.alive) vgame.Color.white else vgame.Color.red;
        ctx.drawLines(lander.pos, app.screen.scale * 0.8, lander.rot, &LANDER_LINES, true, lander_color);

        // Thrust flame
        if (thrusting) {
            ctx.drawLines(lander.pos, app.screen.scale * 0.8, lander.rot, &FLAME_LINES, true, vgame.Color.orange);
        }

        // Fuel gauge
        const fuel_pct = lander.fuel / FUEL_MAX;
        ctx.drawRect(.{ .x = 50, .y = 50, .width = 200, .height = 20 }, vgame.Color.gray);
        ctx.drawRect(.{ .x = 50, .y = 50, .width = 200 * fuel_pct, .height = 20 }, vgame.Color.green);
        ctx.drawRectLines(.{ .x = 50, .y = 50, .width = 200, .height = 20 }, 2, vgame.Color.white);

        // Altitude indicator
        const ground_y = terrain.heightAt(lander.pos.x);
        const altitude = ground_y - lander.pos.y;
        var alt_buf: [64:0]u8 = undefined;
        const alt_str = std.fmt.bufPrintZ(&alt_buf, "Altitude: {d:.0}", .{altitude}) catch unreachable;
        ctx.drawText(alt_str, 50, 80, 20, vgame.Color.white);

        // Velocity
        const speed = @sqrt(lander.vel.x * lander.vel.x + lander.vel.y * lander.vel.y);
        var spd_buf: [64:0]u8 = undefined;
        const spd_str = std.fmt.bufPrintZ(&spd_buf, "Speed: {d:.0}", .{speed}) catch unreachable;
        ctx.drawText(spd_str, 50, 105, 20, if (speed < SAFE_SPEED) vgame.Color.green else vgame.Color.red);

        // Overlays
        if (lander.landed) {
            vgame.drawOverlay(field, .{
                .title = "LANDED!",
                .title_color = vgame.Color.green,
                .lines = &.{
                    "Safe landing on the pad!",
                    "",
                    "Press R to play again",
                },
                .bg_color = .{ .r = 0, .g = 60, .b = 0, .a = 200 },
                .border_color = .{ .r = 0, .g = 200, .b = 0, .a = 220 },
            });
        } else if (!lander.alive) {
            vgame.drawOverlay(field, .{
                .title = "CRASHED",
                .title_color = vgame.Color.red,
                .lines = &.{
                    "Your lander is now scattered across the surface.",
                    "",
                    "Press R to try again",
                },
                .bg_color = .{ .r = 60, .g = 0, .b = 0, .a = 200 },
                .border_color = .{ .r = 220, .g = 80, .b = 80, .a = 220 },
                .fullscreen_dim = true,
            });
        }
    }
}