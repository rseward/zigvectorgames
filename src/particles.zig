// particles.zig — Particle system for line debris and dot explosions
//
// Extracted from zigsteroids Particle/splatLines/splatDots.
// Particles wrap around a toroidal playfield, decay TTL, auto-remove dead.

const std = @import("std");
const rl = @import("raylib");
const rlm = rl.math;
const Vector2 = rl.Vector2;
const math = std.math;
const render_mod = @import("render.zig");

const ParticleType = enum { LINE, DOT };

const Particle = struct {
    pos: Vector2,
    vel: Vector2,
    ttl: f32,
    color: rl.Color,
    values: union(ParticleType) {
        LINE: struct { rot: f32, length: f32 },
        DOT: struct { radius: f32 },
    },
};

pub const ParticleConfig = struct {
    color: rl.Color = rl.Color.white,
    speed: f32 = 2.0,
    ttl: f32 = 3.0,
    scale: f32 = 38.0,
};

pub const Particles = struct {
    items: std.ArrayList(Particle),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Particles {
        return .{
            .items = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Particles) void {
        self.items.deinit(self.allocator);
    }

    /// Spawn line debris particles (explosion fragments).
    pub fn spawnLines(self: *Particles, pos: Vector2, count: usize, config: ParticleConfig, rand: *std.Random) !void {
        for (0..count) |_| {
            const angle = math.tau * rand.float(f32);
            try self.items.append(self.allocator, .{
                .pos = rlm.vector2Add(pos, .{
                    .x = rand.float(f32) * 3,
                    .y = rand.float(f32) * 3,
                }),
                .vel = rlm.vector2Scale(
                    .{ .x = math.cos(angle), .y = math.sin(angle) },
                    config.speed * rand.float(f32),
                ),
                .ttl = config.ttl + rand.float(f32),
                .color = config.color,
                .values = .{ .LINE = .{
                    .rot = math.tau * rand.float(f32),
                    .length = config.scale * (0.6 + 0.4 * rand.float(f32)),
                } },
            });
        }
    }

    /// Spawn dot particles (explosion sparks).
    pub fn spawnDots(self: *Particles, pos: Vector2, count: usize, config: ParticleConfig, rand: *std.Random) !void {
        for (0..count) |_| {
            const angle = math.tau * rand.float(f32);
            try self.items.append(self.allocator, .{
                .pos = rlm.vector2Add(pos, .{
                    .x = rand.float(f32) * 3,
                    .y = rand.float(f32) * 3,
                }),
                .vel = rlm.vector2Scale(
                    .{ .x = math.cos(angle), .y = math.sin(angle) },
                    config.speed + 4.0 * rand.float(f32),
                ),
                .ttl = 0.5 + 0.4 * rand.float(f32),
                .color = config.color,
                .values = .{ .DOT = .{ .radius = config.scale * 0.025 } },
            });
        }
    }

    /// Update all particles: move, wrap, decay TTL, remove dead.
    pub fn update(self: *Particles, dt: f32, field_size: Vector2) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            var p = &self.items.items[i];
            p.pos = rlm.vector2Add(p.pos, p.vel);
            p.pos = .{
                .x = @mod(p.pos.x, field_size.x),
                .y = @mod(p.pos.y, field_size.y),
            };
            if (p.ttl > dt) {
                p.ttl -= dt;
                i += 1;
            } else {
                _ = self.items.swapRemove(i);
            }
        }
    }

    /// Render all particles using vector drawing primitives.
    pub fn render(self: *const Particles) void {
        for (self.items.items) |p| {
            switch (p.values) {
                .LINE => |line| {
                    const points = [_]Vector2{
                        .{ .x = -0.5, .y = 0 },
                        .{ .x = 0.5, .y = 0 },
                    };
                    render_mod.drawLinesRaw(p.pos, line.length, line.rot, &points, true, p.color);
                },
                .DOT => |dot| {
                    rl.drawCircleV(p.pos, dot.radius, p.color);
                },
            }
        }
    }
};