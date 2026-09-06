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

const ParticleType = enum { LINE, DOT, SQUARE };

const Particle = struct {
    pos: Vector2,
    vel: Vector2,
    ttl: f32,
    color: rl.Color,
    values: union(ParticleType) {
        LINE: struct { rot: f32, length: f32 },
        DOT: struct { radius: f32 },
        SQUARE: struct { size: f32, rot: f32, rot_speed: f32 },
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
    /// Velocities are in design-space units per second (dt-scaled).
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
                    config.speed * 60.0 * rand.float(f32),
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
    /// Velocities are in design-space units per second (dt-scaled).
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
                    (config.speed + 4.0 * rand.float(f32)) * 60.0,
                ),
                .ttl = 0.5 + 0.4 * rand.float(f32),
                .color = config.color,
                .values = .{ .DOT = .{ .radius = config.scale * 0.025 } },
            });
        }
    }

    /// Spawn square fragment particles from an explosion.
    /// `total_pixels` is the screen-space pixel area of the object being
    /// destroyed.  Each fragment is a 4-pixel square (2x2), so the number
    /// of fragments = total_pixels / 4.  Fragments fly outward with
    /// random velocities and spin, then fade.
    /// `frag_size` is the side length in design-space units (not screen
    /// pixels) so fragments are visible at any render scale.
    pub fn spawnSquares(
        self: *Particles,
        pos: Vector2,
        total_pixels: usize,
        config: ParticleConfig,
        rand: *std.Random,
    ) !void {
        const fragment_pixel_area: usize = 4; // 2x2 pixels per fragment
        const count = total_pixels / fragment_pixel_area / 3; // 1/3 density — satisfying without overdoing it
        // Cap to avoid pathological counts from very large shapes
        const capped = @min(count, 200);
        // Size fragments in design-space: 4 screen pixels divided by
        // render_scale gives design-space units.  But we don't know
        // render_scale here, so use a fraction of config.scale instead.
        // config.scale is the base_scale (e.g. 38.0).  A 2x2 screen pixel
        // square at render_scale ~1.5 is about 1.3 design units.  Use
        // config.scale * 0.08 as a reasonable visible size (~3 design units).
        const frag_size: f32 = config.scale * 0.08;

        for (0..capped) |_| {
            const angle = math.tau * rand.float(f32);
            const speed = config.speed * (0.5 + 1.5 * rand.float(f32));
            try self.items.append(self.allocator, .{
                .pos = rlm.vector2Add(pos, .{
                    .x = (rand.float(f32) - 0.5) * config.scale * 0.5,
                    .y = (rand.float(f32) - 0.5) * config.scale * 0.5,
                }),
                .vel = rlm.vector2Scale(
                    .{ .x = math.cos(angle), .y = math.sin(angle) },
                    speed,
                ),
                .ttl = config.ttl * (0.5 + rand.float(f32)),
                .color = config.color,
                .values = .{ .SQUARE = .{
                    .size = frag_size,
                    .rot = math.tau * rand.float(f32),
                    .rot_speed = (rand.float(f32) - 0.5) * 10.0,
                } },
            });
        }
    }

    /// Update all particles: move, wrap, decay TTL, remove dead.
    pub fn update(self: *Particles, dt: f32, field_size: Vector2) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            var p = &self.items.items[i];
            // Velocity is in design-space units per second
            p.pos = rlm.vector2Add(p.pos, rlm.vector2Scale(p.vel, dt));
            p.pos = .{
                .x = @mod(p.pos.x, field_size.x),
                .y = @mod(p.pos.y, field_size.y),
            };
            // Spin square fragments
            switch (p.values) {
                .SQUARE => |*sq| sq.rot += sq.rot_speed * dt,
                else => {},
            }
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
            // Fade out as TTL decreases (simple alpha based on TTL)
            const alpha: u8 = if (p.ttl < 1.0)
                @intFromFloat(@max(0.0, @min(255.0, p.ttl * 255.0)))
            else
                255;
            const fade_color = rl.Color{
                .r = p.color.r,
                .g = p.color.g,
                .b = p.color.b,
                .a = alpha,
            };
            switch (p.values) {
                .LINE => |line| {
                    const points = [_]Vector2{
                        .{ .x = -0.5, .y = 0 },
                        .{ .x = 0.5, .y = 0 },
                    };
                    render_mod.drawLinesRaw(p.pos, line.length, line.rot, &points, true, fade_color);
                },
                .DOT => |dot| {
                    rl.drawCircleV(p.pos, dot.radius, fade_color);
                },
                .SQUARE => |sq| {
                    // Draw a filled, rotated square using drawRectanglePro.
                    // The rectangle is centered at p.pos with origin at its
                    // center, rotated by sq.rot (in radians, but raylib
                    // expects degrees for drawRectanglePro — convert).
                    const rec = rl.Rectangle{
                        .x = p.pos.x - sq.size / 2.0,
                        .y = p.pos.y - sq.size / 2.0,
                        .width = sq.size,
                        .height = sq.size,
                    };
                    const origin = Vector2{
                        .x = sq.size / 2.0,
                        .y = sq.size / 2.0,
                    };
                    const deg = sq.rot * 180.0 / math.pi;
                    rl.drawRectanglePro(rec, origin, deg, fade_color);
                },
            }
        }
    }
};