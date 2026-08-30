# Task 02: Implement color.zig and math.zig

Port the color palette (MyColor/getMyColor) and math helpers from zigsteroids.

color.zig: Color type (re-export rl.Color), Palette struct with named presets,
lerpColor for interpolation, rgba() helper for overlay backgrounds.

math.zig: circleCollision, pointInCircle, wrapPos (toroidal), normalize, scale,
add, sub, distance -- thin wrappers over rlm functions.