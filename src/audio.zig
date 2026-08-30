// audio.zig — AudioManager: load and play sound clips
//
// Games provide a list of sound files at init. AudioManager loads them into
// raylib Sound objects and plays by index. The resource_dir is prepended to
// each filename, so games just list filenames like "shoot.wav".

const std = @import("std");
const rl = @import("raylib");

pub const AudioConfig = struct {
    /// Sound filenames relative to resource_dir, e.g. &.{ "shoot.wav", "thrust.wav" }
    clips: []const []const u8,
    /// Directory path for sound files (relative or absolute).
    resource_dir: []const u8 = "resources",
};

pub const AudioManager = struct {
    sounds: []rl.Sound,
    config: AudioConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: AudioConfig) !AudioManager {
        rl.initAudioDevice();

        var sounds = try allocator.alloc(rl.Sound, config.clips.len);
        errdefer allocator.free(sounds);

        for (config.clips, 0..) |clip, i| {
            const path = try std.fs.path.joinZ(allocator, &.{ config.resource_dir, clip });
            defer allocator.free(path);
            sounds[i] = try rl.loadSound(path);
        }

        return .{
            .sounds = sounds,
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AudioManager) void {
        for (self.sounds) |s| rl.unloadSound(s);
        self.allocator.free(self.sounds);
        rl.closeAudioDevice();
    }

    /// Play a sound by index.
    pub fn play(self: *const AudioManager, index: usize) void {
        if (index < self.sounds.len) {
            rl.playSound(self.sounds[index]);
        }
    }

    /// Set master volume (0.0 to 1.0).
    pub fn setVolume(self: *const AudioManager, volume: f32) void {
        _ = self;
        rl.setMasterVolume(volume);
    }
};