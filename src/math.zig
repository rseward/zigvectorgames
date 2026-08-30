// math.zig — Vector math and collision helpers

const rl = @import("raylib");
const Vector2 = rl.Vector2;
const rlm = rl.math;

/// Circle-vs-circle collision: true if distance between centers < sum of radii.
pub fn circleCollision(pos_a: Vector2, radius_a: f32, pos_b: Vector2, radius_b: f32) bool {
    return rlm.vector2Distance(pos_a, pos_b) < (radius_a + radius_b);
}

/// Point-vs-circle collision.
pub fn pointInCircle(point: Vector2, center: Vector2, radius: f32) bool {
    return rlm.vector2Distance(point, center) < radius;
}

/// Wrap a position around a toroidal playfield (mod into [0, size)).
pub fn wrapPos(pos: Vector2, size: Vector2) Vector2 {
    return .{
        .x = @mod(pos.x, size.x),
        .y = @mod(pos.y, size.y),
    };
}

/// Normalize a Vector2 (returns zero vector if input is zero).
pub fn normalize(v: Vector2) Vector2 {
    return rlm.vector2Normalize(v);
}

/// Scale a Vector2 by a scalar.
pub fn scale(v: Vector2, s: f32) Vector2 {
    return rlm.vector2Scale(v, s);
}

/// Add two Vector2s.
pub fn add(a: Vector2, b: Vector2) Vector2 {
    return rlm.vector2Add(a, b);
}

/// Subtract two Vector2s.
pub fn sub(a: Vector2, b: Vector2) Vector2 {
    return rlm.vector2Subtract(a, b);
}

/// Distance between two points.
pub fn distance(a: Vector2, b: Vector2) f32 {
    return rlm.vector2Distance(a, b);
}