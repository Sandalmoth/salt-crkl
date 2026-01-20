pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

const std = @import("std");

const log = std.log.scoped(.sdl);

pub const Window = c.SDL_Window;
pub const Event = c.SDL_Event;

pub fn getError() [*c]const u8 {
    return c.SDL_GetError();
}

pub fn setMainReady() void {
    c.SDL_SetMainReady();
}

pub fn init(flags: u32) !void {
    if (!c.SDL_Init(flags)) {
        log.err("SDL_Init: {s}", .{getError()});
        return error.Sdl;
    }
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn createWindow(title: []const u8, w: c_int, h: c_int, flags: u64) !*Window {
    return c.SDL_CreateWindow(title.ptr, w, h, flags) orelse {
        log.err("SDL_CreateWindow: {s}", .{getError()});
        return error.Sdl;
    };
}

pub fn destroyWindow(window: *Window) void {
    c.SDL_DestroyWindow(window);
}

pub fn setWindowRelativeMouseMode(window: *Window, enabled: bool) !void {
    if (!c.SDL_SetWindowRelativeMouseMode(window, enabled)) {
        log.err("SDL_SetWindowRelativeMouseMode: {s}", .{getError()});
        return error.Sdl;
    }
}

pub fn pollEvent(event: *Event) bool {
    return c.SDL_PollEvent(event);
}
