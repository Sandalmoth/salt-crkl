const std = @import("std");

pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");
pub const Renderer = @import("renderer.zig");

pub const KeyGen = @import("keygen").KeyGen;

pub const ecs = struct {
    pub const raw = @import("ecs");
    pub const Key = raw.Key;

    pub fn World(comptime Spec: type) type {
        return raw.World(.{ .block_size = defines.block_size }, Spec);
    }
};

pub const mem = struct {
    pub const raw = @import("mem");
    pub const BlockAllocator = raw.BlockAllocator(.{ .block_size = defines.block_size });
};

pub fn init() !void {
    sdl.setMainReady();

    try sdl.init(sdl.c.SDL_INIT_VIDEO);
    errdefer sdl.quit();
}

pub fn deinit() void {
    sdl.quit();
}
