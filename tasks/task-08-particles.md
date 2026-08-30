# Task 08: Implement particles.zig

Extract particle system from zigsteroids (Particle, splatLines, splatDots).

ParticleConfig: color, speed, ttl, scale (matches BASE_SCALE).

Particles struct: init(allocator), deinit(), spawnLines(pos, count, config, rand),
spawnDots(pos, count, config, rand), update(dt, field_size), render().

Particles wrap around toroidal playfield, decay TTL, auto-remove dead.
LINE particles render as rotated line segments, DOT particles as circles.