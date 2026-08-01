const std = @import("std");
pub const c = @import("c");

const log = std.log.scoped(.sdl);

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

pub fn createWindow(title: []const u8, w: c_int, h: c_int, flags: u64) !Window {
    return .{ .window = c.SDL_CreateWindow(title.ptr, w, h, flags) orelse {
        log.err("SDL_CreateWindow: {s}", .{getError()});
        return error.Sdl;
    } };
}

pub fn createGPUDevice(format_flags: u32, debug_mode: bool, name: ?[]const u8) !GPUDevice {
    return .{ .gpu_device = c.SDL_CreateGPUDevice(
        format_flags,
        debug_mode,
        if (name == null) null else name.?.ptr,
    ) orelse {
        log.err("SDL_CreateGPUDevice: {s}", .{getError()});
        return error.Sdl;
    } };
}

pub const Window = struct {
    window: *c.SDL_Window,

    pub fn destroy(window: Window) void {
        c.SDL_DestroyWindow(window.window);
    }

    pub fn setWindowRelativeMouseMode(window: Window, enabled: bool) !void {
        if (!c.SDL_SetWindowRelativeMouseMode(window.window, enabled)) {
            log.err("SDL_SetWindowRelativeMouseMode: {s}", .{getError()});
            return error.Sdl;
        }
    }
};

pub const GPUDevice = struct {
    gpu_device: *c.SDL_GPUDevice,

    pub fn destroy(gpu_device: GPUDevice) void {
        c.SDL_DestroyGPUDevice(gpu_device.gpu_device);
    }

    pub fn claimWindow(gpu_device: GPUDevice, window: Window) !void {
        if (!c.SDL_ClaimWindowForGPUDevice(gpu_device.gpu_device, window.window)) {
            log.err("SDL_ClaimWindowForGPUDevice: {s}", .{getError()});
            return error.Sdl;
        }
    }
};
