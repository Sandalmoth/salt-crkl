const sc = @import("framework");
const std = @import("std");

pub fn main() !void {
    try sc.init();
    defer sc.deinit();

    const window = try sc.sdl.createWindow(
        "example-framework",
        800,
        600,
        sc.sdl.c.SDL_WINDOW_RESIZABLE,
    );
    defer window.destroy();
    const gpu_device = try sc.sdl.createGPUDevice(
        sc.sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        "example-framework",
    );
    defer gpu_device.destroy();

    try gpu_device.claimWindow(window);
}
