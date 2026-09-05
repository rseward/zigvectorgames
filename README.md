# zigvectorgames
A 2D vector based game engine (zig and raylib)

## Features
- MSAA 4x anti-aliasing for crisp, smooth vector lines (enabled by default)
- Bloom/glow post-processing for a soft CRT-vector look (enabled by default)
  - Renders the scene to an offscreen texture, then composites additive
    blurred copies on top to produce a glow around all bright lines
  - Can be disabled per-game via `AppConfig{ .glow = false }`
- Letterbox scaling: games work in a fixed design resolution, the engine
  scales to any window size
- Audio: load and play WAV sound clips by index
- Particles, overlays, vector 7-segment numbers, and bitmap text