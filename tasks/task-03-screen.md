# Task 03: Implement screen.zig

Extract screen scaling and letterboxing from zigsteroids updateScreenSize().

Screen struct holds: design_size, base_scale, runtime size/scale/offset,
screen_w/screen_h. init() takes design size + base scale. update() recalculates
from actual window dimensions. changed() detects runtime size changes.

Replaces zigsteroids globals: SCALE, SIZE, RENDER_OFFSET, DESIGN_SIZE, BASE_SCALE.