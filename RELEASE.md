# Release Notes

## v0.1.0 — Initial Release

First public release of the vgame vector game platform, targeting Zig 0.15.2.

### Platform / Engine

- **Vector rendering** with letterbox scaling: games work in a fixed design
  resolution (1280x960), the engine scales to any window size automatically
- **MSAA 4x anti-aliasing** enabled by default for smooth, crisp vector lines
- **Bloom/glow post-processing** enabled by default — renders the scene to an
  offscreen texture and composites additive blurred passes for a soft CRT
  vector glow around all bright lines (configurable via `AppConfig.glow`)
- **Audio system** — load and play WAV sound clips by index with
  `AudioManager`; audio init is optional, games run silent if unavailable
- **Particle system** — line debris, dot sparks, and square explosion
  fragments with fade-out, rotation, and toroidal wrap
- **Overlays** — pause and game-over screens with configurable colors
- **Platform-level controls** — F key toggles fullscreen in all games
- **Input manager** — keyboard + gamepad support with configurable bindings

### Sample Games

- **VecInvaders** — Space Invaders with SVG-derived ant-head invader shapes
  (jaws open/closed animation), 4 destructible bunkers, wave-based difficulty
  scaling, sound effects (player/alien lasers, explosions, marching clicks),
  and volume-accurate explosion fragments (fragment pixel mass matches the
  destroyed shape's screen area)
- **VecPong** — Pong with AI opponent, keyboard and gamepad controls
- **VecLander** — Lunar lander with velocity-safe landing detection
- **VecTetris** — Tetris with SRS rotation, row dissolve animation, lock
  delay grace period, and next-piece preview
- **VecBlackhole** — Schwarzschild black hole simulator with star field,
  spaghettification effect, gravitational wave orbital decay, and
  adjustable simulation speed
- **Minimal** — Minimal example showing the basic App/render loop

### Build

Requires Zig 0.15.2 (install via [zvm](https://github.com/ziglang/zvm)).

```
make build          # build the vgame platform library
make build-samples  # build all sample games
make run-vecinvaders  # build and run a specific game
```

### Dependencies

- [raylib-zig](https://github.com/raylib-zig/raylib-zig) 5.6.0-dev
  (pinned via `build.zig.zon`)
- System libraries: GLFW, Mesa GL, X11 (see `make deps` for Fedora)