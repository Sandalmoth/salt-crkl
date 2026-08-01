const std = @import("std");

pub const ecs = @import("ecs");
pub const sdl = @import("sdl.zig");

pub fn init() !void {
    sdl.setMainReady();

    try sdl.init(sdl.c.SDL_INIT_VIDEO);
}

pub fn deinit() void {
    sdl.quit();
}
