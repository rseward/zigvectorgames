# Task 13: Implement VecLander

Lunar Lander: rotate ship with left/right, thrust with up, gravity pulls down.
Vector terrain drawn as connected line segments. Flat sections are landing pads.

Land safely: slow speed + nearly level rotation = success. Too fast/tilted = crash.
Fuel gauge (vector rectangle). Restart with R. Overlay panels for landed/crashed.

Uses vgame for: App, RenderContext (drawLines for terrain+lander, drawRect for gauge),
overlay (drawOverlay for status), audio (thrust.wav, crash.wav), particles (explosions).
~150 lines of game code.