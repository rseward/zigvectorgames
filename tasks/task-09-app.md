# Task 09: Implement config.zig and app.zig

AppConfig: title, design_size, base_scale, fullscreen, window_resizable,
target_fps, background_color.

App struct ties everything together:
- init(allocator, config) -- creates window, Screen, sets target FPS
- deinit() -- closes window, cleans up audio
- initAudio(config) -- optional, loads sound clips
- frame() -- returns false on windowShouldClose, updates delta/time/screen
- beginRender() -- returns RenderContext with camera + beginDrawing

Games call: while (app.frame()) { logic; const ctx = app.beginRender(); defer ctx.end(); draw }