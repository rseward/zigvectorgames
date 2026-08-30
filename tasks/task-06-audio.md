# Task 06: Implement audio.zig

AudioManager loads sound clips from a resource directory at init, plays by index.

AudioConfig: clips ([]const []const u8 filenames), resource_dir (default "resources")

AudioManager: init(allocator, config) -- calls rl.initAudioDevice(), loads each clip.
deinit() -- unloads sounds, closes audio device. play(index) -- rl.playSound.
setVolume(f32) -- rl.setMasterVolume.