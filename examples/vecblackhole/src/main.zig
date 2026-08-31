// VecBlackhole — Black hole with surrounding star field
//
// Simulates a Schwarzschild (non-rotating) black hole with stars that orbit,
// get gravitationally lensed, accreted, and eventually consumed. When all
// stars are gone, the simulation resets with a new random field.
//
// Physics:
//   - Newtonian gravity with 1/r^2 falloff for the orbital mechanics
//   - Schwarzschild radius (event horizon) where escape velocity > c
//   - Gravitational redshift: light loses energy climbing out of the well,
//     shifting color toward red/infrared as stars approach the horizon
//   - Relativistic Doppler beaming: stars moving toward viewer are blue-shifted,
//     away are red-shifted (simplified 2D projection)
//   - Photon sphere at 1.5 Rs: stars crossing this get a brightness boost
//     from gravitational lensing focusing their light
//   - Accretion disk glow: material spiraling in heats up and emits
//     progressively hotter radiation (IR -> red -> orange -> white -> blue)
//
// Controls: R = reset, P = pause, + = speed up, - = slow down, ESC = quit

const std = @import("std");
const vgame = @import("vgame");
const rl = vgame.rl;
const Vector2 = vgame.Vector2;

// ── Simulation constants ───────────────────────────────────────────

const DESIGN_W: f32 = 1280.0;
const DESIGN_H: f32 = 960.0;

const NUM_STARS: usize = 80;

// Black hole parameters (in design-space pixels)
const BH_MASS: f32 = 8000.0;        // gravitational mass parameter
const BH_RS: f32 = 28.0;            // Schwarzschild radius (event horizon)
const BH_PHOTON_SPHERE: f32 = 42.0; // 1.5 * Rs — photon sphere
const BH_ISCO: f32 = 84.0;          // 3 * Rs — innermost stable circular orbit
const BH_GLOW: f32 = 140.0;         // accretion disk outer glow radius

// Physics tuning
const G: f32 = 0.8;            // gravitational constant (tuned for visual effect)
const SPEED_OF_LIGHT: f32 = 600.0; // c in design-space units (for redshift calc)
const MAX_VEL: f32 = 500.0;    // velocity cap to prevent numerical explosion
const TIME_SCALE_MIN: f32 = 0.1;
const TIME_SCALE_MAX: f32 = 5.0;
const TIME_SCALE_STEP: f32 = 0.2;

// Star visual parameters
const STAR_MIN_RADIUS: f32 = 1.5;
const STAR_MAX_RADIUS: f32 = 4.0;
const STAR_BASE_BRIGHTNESS: f32 = 1.0;

// ── Star color temperature model ───────────────────────────────────
// Based on blackbody radiation color temperature.
// Hot stars (30,000K+) are blue. Cool stars (3,000K) are red-orange.
// As a star approaches the event horizon, gravitational redshift pushes
// its apparent color toward infrared (deep red, then fades).

const StarClass = enum {
    O, // blue-white, hottest
    B, // blue-white
    A, // white
    F, // yellow-white
    G, // yellow (like our Sun)
    K, // orange
    M, // red, coolest
};

const STAR_CLASSES = [_]StarClass{ .O, .B, .A, .F, .G, .G, .K, .K, .M, .M };

fn starClassColor(class: StarClass) vgame.Color {
    return switch (class) {
        .O => .{ .r = 155, .g = 176, .b = 255, .a = 255 }, // blue
        .B => .{ .r = 170, .g = 191, .b = 255, .a = 255 }, // blue-white
        .A => .{ .r = 202, .g = 215, .b = 255, .a = 255 }, // white-blue
        .F => .{ .r = 248, .g = 247, .b = 255, .a = 255 }, // white
        .G => .{ .r = 255, .g = 244, .b = 234, .a = 255 }, // yellow-white
        .K => .{ .r = 255, .g = 210, .b = 161, .a = 255 }, // orange
        .M => .{ .r = 255, .g = 163, .b = 100, .a = 255 }, // red-orange
    };
}

// ── Star ───────────────────────────────────────────────────────────

const Star = struct {
    pos: Vector2,
    vel: Vector2,
    radius: f32,
    class: StarClass,
    base_color: vgame.Color,
    alive: bool = true,
    // Accretion state: when star crosses ISCO it starts spiraling
    accreting: bool = false,
    accretion_heat: f32 = 0.0, // 0 = cool, 1 = max heat (blue-hot)
    // Trail for visual effect as star spirals in
    trail: [8]Vector2 = @splat(.{ .x = 0, .y = 0 }),
    trail_len: usize = 0,
};

// ── Simulation ─────────────────────────────────────────────────────

const Simulation = struct {
    stars: [NUM_STARS]Star = undefined,
    bh_x: f32 = DESIGN_W / 2,
    bh_y: f32 = DESIGN_H / 2,
    num_alive: usize = NUM_STARS,
    time: f32 = 0,
    paused: bool = false,
    reset_timer: f32 = 0,
    resetting: bool = false,
    time_scale: f32 = 1.0,

    fn init(self: *Simulation, prng: *std.Random.DefaultPrng) void {
        self.bh_x = DESIGN_W / 2;
        self.bh_y = DESIGN_H / 2;
        self.time = 0;
        self.paused = false;
        self.reset_timer = 0;
        self.resetting = false;
        self.num_alive = NUM_STARS;

        const rand = prng.random();

        for (0..NUM_STARS) |i| {
            const angle = rand.float(f32) * 2.0 * std.math.pi;

            if (i < 3) {
                // First few stars: place close to the black hole, just outside
                // the photon sphere, with unstable orbits so they spiral in
                // and get consumed within the first few minutes.
                const close_dist = BH_PHOTON_SPHERE + 15.0 + rand.float(f32) * 25.0;
                const px = self.bh_x + @cos(angle) * close_dist;
                const py = self.bh_y + @sin(angle) * close_dist;

                // Low orbital velocity — not enough for a stable orbit at this
                // distance, so the star will be pulled in quickly.
                const orbit_speed = @sqrt(G * BH_MASS / close_dist) * 0.5;
                const vx = -@sin(angle) * orbit_speed;
                const vy = @cos(angle) * orbit_speed;

                const class = STAR_CLASSES[rand.intRangeLessThan(usize, 0, STAR_CLASSES.len)];
                const radius = STAR_MIN_RADIUS + rand.float(f32) * (STAR_MAX_RADIUS - STAR_MIN_RADIUS);

                self.stars[i] = .{
                    .pos = .{ .x = px, .y = py },
                    .vel = .{ .x = vx, .y = vy },
                    .radius = radius,
                    .class = class,
                    .base_color = starClassColor(class),
                    .alive = true,
                    .accreting = false,
                    .accretion_heat = 0.0,
                    .trail = @splat(.{ .x = 0, .y = 0 }),
                    .trail_len = 0,
                };
            } else {
                // Remaining stars: place in a ring well outside ISCO with
                // stable-ish orbits.
                const min_dist = BH_ISCO + 80.0;
                const max_dist = 460.0;
                // Use sqrt distribution for uniform area coverage
                const t = rand.float(f32);
                const dist = min_dist + (max_dist - min_dist) * @sqrt(t);

                const px = self.bh_x + @cos(angle) * dist;
                const py = self.bh_y + @sin(angle) * dist;

                // Orbital velocity: v = sqrt(G*M/r) for circular orbit
                // Add some eccentricity by randomizing the factor
                const orbit_speed = @sqrt(G * BH_MASS / dist);
                const eccentricity = rand.float(f32) * 0.4 + 0.8; // 0.8 to 1.2
                const speed = orbit_speed * eccentricity;

                // Perpendicular velocity for orbital motion (counterclockwise)
                const vx = -@sin(angle) * speed;
                const vy = @cos(angle) * speed;

                const class = STAR_CLASSES[rand.intRangeLessThan(usize, 0, STAR_CLASSES.len)];
                const radius = STAR_MIN_RADIUS + rand.float(f32) * (STAR_MAX_RADIUS - STAR_MIN_RADIUS);

                self.stars[i] = .{
                    .pos = .{ .x = px, .y = py },
                    .vel = .{ .x = vx, .y = vy },
                    .radius = radius,
                    .class = class,
                    .base_color = starClassColor(class),
                    .alive = true,
                    .accreting = false,
                    .accretion_heat = 0.0,
                    .trail = @splat(.{ .x = 0, .y = 0 }),
                    .trail_len = 0,
                };
            }
        }
    }

    fn update(self: *Simulation, dt: f32) void {
        if (self.paused) return;

        if (self.resetting) {
            self.reset_timer += dt;
            if (self.reset_timer >= 2.0) {
                var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
                self.init(&prng);
            }
            return;
        }

        self.time += dt;
        const sim_dt = dt * self.time_scale;

        for (0..NUM_STARS) |i| {
            if (!self.stars[i].alive) continue;
            self.updateStar(&self.stars[i], sim_dt);
        }

        // Check if all stars consumed
        if (self.num_alive == 0 and !self.resetting) {
            self.resetting = true;
            self.reset_timer = 0;
        }
    }

    fn updateStar(self: *Simulation, star: *Star, dt: f32) void {
        // Vector from star to black hole
        const dx = self.bh_x - star.pos.x;
        const dy = self.bh_y - star.pos.y;
        const dist_sq = dx * dx + dy * dy;
        const dist = @sqrt(dist_sq);

        // ── Event horizon check ──
        // Once a star crosses Rs, it's consumed — no return.
        if (dist < BH_RS) {
            star.alive = false;
            self.num_alive -= 1;
            return;
        }

        // ── Gravity ──
        // F = G * M / r^2, directed toward the black hole
        // Use softened gravity to avoid singularity at very close range
        const softening: f32 = 4.0;
        const softened_sq = dist_sq + softening * softening;
        const force = G * BH_MASS / softened_sq;
        const ax = (dx / dist) * force;
        const ay = (dy / dist) * force;

        star.vel.x += ax * dt;
        star.vel.y += ay * dt;

        // Cap velocity to prevent numerical instability
        const speed_sq = star.vel.x * star.vel.x + star.vel.y * star.vel.y;
        if (speed_sq > MAX_VEL * MAX_VEL) {
            const speed = @sqrt(speed_sq);
            star.vel.x = (star.vel.x / speed) * MAX_VEL;
            star.vel.y = (star.vel.y / speed) * MAX_VEL;
        }

        // ── Accretion disk physics ──
        // When star crosses ISCO (innermost stable circular orbit),
        // it begins to spiral in. Material heats up from friction and
        // compression, emitting progressively hotter radiation.
        if (dist < BH_ISCO) {
            star.accreting = true;
            // Heat increases as star gets closer to horizon
            const heat_factor = 1.0 - ((dist - BH_RS) / (BH_ISCO - BH_RS));
            star.accretion_heat = @max(star.accretion_heat, @min(1.0, heat_factor));

            // Add drag to simulate orbital decay from gravitational radiation
            // and gas friction in the accretion disk
            const drag = 0.15 * dt;
            star.vel.x *= (1.0 - drag);
            star.vel.y *= (1.0 - drag);

            // Add slight inward spiral component
            const inward_force = 20.0 * dt;
            star.vel.x += (dx / dist) * inward_force;
            star.vel.y += (dy / dist) * inward_force;
        } else {
            // ── Gravitational wave orbital decay ──
            // In general relativity, orbiting bodies radiate gravitational
            // waves and slowly lose orbital energy. The power radiated scales
            // as 1/r^4 (quadrupole formula), so distant stars barely decay
            // while closer ones spiral in faster. Over the simulation's
            // timescale every star eventually falls in.
            const gw_coeff = 8.0e6; // tuned for visible decay within minutes
            const gw_drag = gw_coeff / (dist * dist * dist * dist) * dt;
            const clamped_drag = @min(0.01, gw_drag); // prevent runaway at close range
            star.vel.x *= (1.0 - clamped_drag);
            star.vel.y *= (1.0 - clamped_drag);
        }

        // Update position
        star.pos.x += star.vel.x * dt;
        star.pos.y += star.vel.y * dt;

        // ── Trail update for accreting stars ──
        if (star.accreting) {
            // Shift trail
            if (star.trail.len > 0) {
                var j: usize = star.trail_len;
                while (j > 0) {
                    j -= 1;
                    if (j < star.trail.len - 1) {
                        star.trail[j + 1] = star.trail[j];
                    }
                }
                star.trail[0] = star.pos;
                if (star.trail_len < star.trail.len) {
                    star.trail_len += 1;
                }
            }
        }
    }

    /// Calculate the apparent color of a star after gravitational redshift
    /// and Doppler effects. Based on Schwarzschild metric redshift:
    /// z = 1/sqrt(1 - Rs/r) - 1
    /// Light emitted at radius r appears redshifted to an observer at infinity.
    fn starApparentColor(star: *const Star, bh_x: f32, bh_y: f32) vgame.Color {
        const dx = bh_x - star.pos.x;
        const dy = bh_y - star.pos.y;
        const dist = @sqrt(dx * dx + dy * dy);

        // Gravitational redshift factor: 1/sqrt(1 - Rs/r)
        // At r = Rs this goes to infinity (infinite redshift = invisible)
        // At r >> Rs this approaches 1 (no redshift)
        var redshift: f32 = 1.0;
        if (dist > BH_RS) {
            const ratio = BH_RS / dist;
            if (ratio < 0.99) {
                redshift = 1.0 / @sqrt(1.0 - ratio);
            } else {
                redshift = 10.0; // extreme redshift near horizon
            }
        }

        // Redshift factor > 1 means wavelength stretches, so:
        // - Blue light shifts toward red
        // - Red light shifts toward infrared (invisible/dark)
        // We model this by scaling color components down and shifting toward red
        const redshift_amount = @min(1.0, (redshift - 1.0) / 3.0); // normalize 0..1

        // Doppler effect: star moving toward viewer (up-left on screen) = blueshift
        // Star moving away (down-right) = redshift
        // Simplified: project velocity along view direction
        const radial_vel = (star.vel.x * (-dx / dist) + star.vel.y * (-dy / dist));
        const doppler_factor = @max(-0.3, @min(0.3, radial_vel / SPEED_OF_LIGHT));

        var r: f32 = @floatFromInt(star.base_color.r);
        var g: f32 = @floatFromInt(star.base_color.g);
        var b: f32 = @floatFromInt(star.base_color.b);

        // Apply gravitational redshift: shift toward red, dim blue
        r = r * (1.0 - redshift_amount * 0.3);
        g = g * (1.0 - redshift_amount * 0.7);
        b = b * (1.0 - redshift_amount * 0.95);

        // Apply Doppler: blueshift adds blue, redshift adds red
        if (doppler_factor > 0) {
            // Moving toward viewer — blueshift
            b = @min(255, b * (1.0 + doppler_factor));
            g = @min(255, g * (1.0 + doppler_factor * 0.5));
        } else {
            // Moving away — redshift
            r = @min(255, r * (1.0 - doppler_factor));
            b = b * (1.0 + doppler_factor);
        }

        // Accretion heating: as material spirals in, it heats up
        // IR -> red -> orange -> yellow -> white -> blue-hot
        if (star.accretion_heat > 0) {
            const heat = star.accretion_heat;
            // Blend toward white-hot then blue-hot based on heat
            const heat_r = @min(255, r * (1.0 - heat * 0.3) + 255 * heat * 0.8);
            const heat_g = @min(255, g * (1.0 - heat * 0.2) + 200 * heat * 0.6);
            const heat_b = @min(255, b * (1.0 - heat * 0.1) + 255 * heat * (0.4 + heat * 0.4));
            r = heat_r;
            g = heat_g;
            b = heat_b;
        }

        // Brightness boost near photon sphere (gravitational lensing)
        const lensing_boost = if (dist < BH_PHOTON_SPHERE * 2.0)
            1.0 + (@max(0.0, (BH_PHOTON_SPHERE * 2.0 - dist) / (BH_PHOTON_SPHERE * 2.0))) * 0.5
        else
            1.0;

        r = @min(255, r * lensing_boost);
        g = @min(255, g * lensing_boost);
        b = @min(255, b * lensing_boost);

        // Fade to black as star approaches horizon (time dilation effect)
        var alpha: f32 = 255.0;
        if (dist < BH_RS * 2.5) {
            const fade = @max(0.0, (dist - BH_RS) / (BH_RS * 1.5));
            alpha = 255.0 * fade;
        }

        return .{
            .r = @intFromFloat(@max(0, @min(255, r))),
            .g = @intFromFloat(@max(0, @min(255, g))),
            .b = @intFromFloat(@max(0, @min(255, b))),
            .a = @intFromFloat(@max(0, @min(255, alpha))),
        };
    }
};

// ── Rendering ──────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var app = try vgame.App.init(allocator, .{
        .title = "VecBlackhole",
        .design_size = .{ .x = DESIGN_W, .y = DESIGN_H },
        .base_scale = 38.0,
    });
    defer app.deinit();

    var prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
    var sim = Simulation{};
    sim.init(&prng);

    var show_help = false;

    while (app.frame()) {
        const dt = app.delta;
        const fs = app.screen.size;

        // Input
        if (rl.isKeyPressed(.h)) show_help = !show_help;
        if (rl.isKeyPressed(.p)) sim.paused = !sim.paused;
        if (rl.isKeyPressed(.r)) {
            var new_prng = std.Random.Xoshiro256.init(@bitCast(std.time.timestamp()));
            sim.init(&new_prng);
        }
        if (rl.isKeyPressed(.equal) or rl.isKeyPressed(.kp_add)) {
            sim.time_scale = @min(TIME_SCALE_MAX, sim.time_scale + TIME_SCALE_STEP);
        }
        if (rl.isKeyPressed(.minus) or rl.isKeyPressed(.kp_subtract)) {
            sim.time_scale = @max(TIME_SCALE_MIN, sim.time_scale - TIME_SCALE_STEP);
        }

        sim.update(dt);

        // ── Render ──
        var ctx = app.beginRender();
        defer ctx.end();

        // Deep space background (near-black with slight blue tint)
        ctx.drawRect(.{ .x = 0, .y = 0, .width = DESIGN_W, .height = DESIGN_H },
            .{ .r = 3, .g = 3, .b = 8, .a = 255 });

        // ── Accretion disk glow ──
        // The accretion disk emits radiation from heated infalling matter.
        // Color gradient: blue-hot inner -> white -> orange -> dark red outer
        drawAccretionGlow(&ctx, sim.bh_x, sim.bh_y, sim.time);

        // ── Photon sphere ring ──
        // Light orbits the black hole at 1.5 Rs. We draw a faint ring.
        const photon_alpha: u8 = @intFromFloat(60.0 + 20.0 * @sin(sim.time * 2.0));
        ctx.drawCircleLines(
            .{ .x = sim.bh_x, .y = sim.bh_y },
            BH_PHOTON_SPHERE,
            .{ .r = 100, .g = 120, .b = 200, .a = photon_alpha },
        );

        // ── Stars ──
        for (0..NUM_STARS) |i| {
            if (!sim.stars[i].alive) continue;
            drawStar(&ctx, &sim.stars[i], sim.bh_x, sim.bh_y);
        }

        // ── Event horizon (black disk) ──
        // The event horizon is a perfect black disk — no light escapes.
        // Draw it ON TOP of stars so that stars passing behind it are hidden.
        ctx.drawCircle(.{ .x = sim.bh_x, .y = sim.bh_y }, BH_RS + 2,
            .{ .r = 0, .g = 0, .b = 0, .a = 255 });

        // ── Einstein ring / gravitational lensing artifact ──
        // A thin bright ring at the photon sphere where lensed light
        // from background stars gets focused into a ring around the hole.
        drawEinsteinRing(&ctx, sim.bh_x, sim.bh_y, sim.time);

        // ── HUD ──
        ctx.drawText("VecBlackhole — Schwarzschild Simulation",
            20, 20, 24, .{ .r = 150, .g = 150, .b = 180, .a = 200 });
        var stars_buf: [16:0]u8 = undefined;
        const stars_str = std.fmt.bufPrintZ(&stars_buf, "Stars: {d}", .{sim.num_alive}) catch unreachable;
        ctx.drawText(stars_str, 20, 55, 20, .{ .r = 120, .g = 120, .b = 140, .a = 200 });

        var speed_buf: [32:0]u8 = undefined;
        const speed_str = std.fmt.bufPrintZ(&speed_buf, "Speed: {d:.1}x", .{sim.time_scale}) catch unreachable;
        ctx.drawText(speed_str, 20, 80, 20, .{ .r = 120, .g = 120, .b = 140, .a = 200 });

        ctx.drawText("+/- speed  P pause  R reset  H help",
            20, 105, 18, .{ .r = 90, .g = 90, .b = 110, .a = 180 });

        if (show_help) {
            vgame.drawOverlay(fs, .{
                .title = "VecBlackhole",
                .lines = &.{
                    "Stars have different colors based on their",
                    "temperature, just like real stars:",
                    "",
                    "  Blue    = hottest (O-type, 30,000K+)",
                    "  White   = hot (A/F-type, ~8,000K)",
                    "  Yellow  = Sun-like (G-type, ~6,000K)",
                    "  Orange  = cool (K-type, ~4,000K)",
                    "  Red     = coolest (M-type, ~3,000K)",
                    "",
                    "As stars fall toward the black hole:",
                    "  - They turn red: gravity stretches light",
                    "    (gravitational redshift)",
                    "  - Stars moving toward you look bluer",
                    "    (Doppler shift, like a siren)",
                    "  - Near the event horizon they heat up and",
                    "    glow white then blue (accretion disk)",
                    "  - The bright ring is the Einstein ring,",
                    "    where gravity bends light into a circle",
                    "",
                    "Press H to close this help",
                },
            });
        }

        if (sim.paused) {
            vgame.drawOverlay(fs, .{
                .title = "PAUSED",
                .lines = &.{
                    "P to resume",
                    "R to reset",
                },
            });
        }

        if (sim.resetting) {
            const fade = @min(1.0, sim.reset_timer / 2.0);
            const alpha: u8 = @intFromFloat(255.0 * fade);
            vgame.drawOverlay(fs, .{
                .title = "ALL STARS CONSUMED",
                .lines = &.{ "Generating new star field...", "" },
                .bg_color = .{ .r = 10, .g = 5, .b = 20, .a = alpha },
                .border_color = .{ .r = 100, .g = 60, .b = 140, .a = alpha },
                .fullscreen_dim = true,
            });
        }
    }
}

/// Draw a star with its apparent (redshifted, doppler-shifted, heated) color.
fn drawStar(ctx: *const vgame.RenderContext, star: *const Star, bh_x: f32, bh_y: f32) void {
    const color = Simulation.starApparentColor(star, bh_x, bh_y);

    // Draw trail for accreting stars
    if (star.accreting and star.trail_len > 1) {
        for (1..star.trail_len) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(star.trail_len));
            const trail_alpha: u8 = @intFromFloat(@as(f32, @floatFromInt(color.a)) * (1.0 - t) * 0.4);
            const trail_color = vgame.Color{
                .r = color.r,
                .g = color.g,
                .b = color.b,
                .a = trail_alpha,
            };
            ctx.drawCircle(star.trail[i], star.radius * (1.0 - t * 0.5), trail_color);
        }
    }

    // Glow halo (bigger for hot/accreting stars)
    const glow_radius = if (star.accreting) star.radius * 3.5 else star.radius * 2.0;
    const glow_alpha: u8 = if (star.accreting) 60 else 40;
    ctx.drawCircle(star.pos, glow_radius,
        .{ .r = color.r, .g = color.g, .b = color.b, .a = glow_alpha });

    // Star body
    ctx.drawCircle(star.pos, star.radius, color);

    // Bright core
    if (star.accretion_heat > 0.3) {
        ctx.drawCircle(star.pos, star.radius * 0.5,
            .{ .r = 255, .g = 255, .b = 255, .a = color.a });
    }
}

/// Draw the accretion disk glow around the black hole.
/// The disk radiates from infrared (outer) to blue-hot (inner).
/// We approximate this with concentric rings of decreasing radius
/// and increasing temperature.
fn drawAccretionGlow(ctx: *const vgame.RenderContext, cx: f32, cy: f32, time: f32) void {
    // Multiple concentric circles with increasing brightness toward center
    const rings = [_]struct { r: f32, color: vgame.Color }{
        .{ .r = BH_GLOW, .color = .{ .r = 80, .g = 20, .b = 10, .a = 15 } },   // outer IR (deep red)
        .{ .r = BH_GLOW * 0.75, .color = .{ .r = 120, .g = 40, .b = 15, .a = 20 } }, // red
        .{ .r = BH_GLOW * 0.55, .color = .{ .r = 200, .g = 80, .b = 20, .a = 25 } }, // orange
        .{ .r = BH_ISCO, .color = .{ .r = 255, .g = 140, .b = 40, .a = 30 } },  // bright orange
        .{ .r = BH_ISCO * 0.7, .color = .{ .r = 255, .g = 200, .b = 100, .a = 35 } }, // yellow-white
        .{ .r = BH_PHOTON_SPHERE * 1.2, .color = .{ .r = 200, .g = 200, .b = 255, .a = 40 } }, // white-blue
    };

    for (rings) |ring| {
        // Pulsing brightness
        const pulse = 0.85 + 0.15 * @sin(time * 1.5 + ring.r * 0.01);
        const a: u8 = @intFromFloat(@as(f32, @floatFromInt(ring.color.a)) * pulse);
        ctx.drawCircle(.{ .x = cx, .y = cy }, ring.r,
            .{ .r = ring.color.r, .g = ring.color.g, .b = ring.color.b, .a = a });
    }
}

/// Draw the Einstein ring — a bright thin ring at the photon sphere
/// where gravitational lensing focuses background light.
fn drawEinsteinRing(ctx: *const vgame.RenderContext, cx: f32, cy: f32, time: f32) void {
    // The ring shimmers as different background sources lens through
    const shimmer = 0.7 + 0.3 * @sin(time * 3.0);
    const base_alpha: u8 = @intFromFloat(180.0 * shimmer);

    // Outer bright ring
    ctx.drawCircleLines(.{ .x = cx, .y = cy }, BH_PHOTON_SPHERE,
        .{ .r = 180, .g = 160, .b = 220, .a = base_alpha });

    // Inner subtle ring (just outside horizon)
    const inner_alpha: u8 = @intFromFloat(100.0 * shimmer);
    ctx.drawCircleLines(.{ .x = cx, .y = cy }, BH_RS * 1.15,
        .{ .r = 100, .g = 80, .b = 140, .a = inner_alpha });
}