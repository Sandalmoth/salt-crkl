const sc = @import("framework");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var blka_impl: sc.mem.BlockAllocator = .init(gpa);
    defer blka_impl.deinit();
    const blka = blka_impl.allocator();

    var seed: u32 = undefined;
    io.random(std.mem.asBytes(&seed));
    var keygen: sc.KeyGen = .init(seed);

    try sc.init();
    defer sc.deinit();

    const window = try sc.sdl.createWindow(
        "example-framework",
        800,
        600,
        sc.sdl.c.SDL_WINDOW_RESIZABLE,
    );
    defer window.destroy();
    // const gpu_device = try sc.sdl.createGPUDevice(
    //     sc.sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
    //     true,
    //     "example-framework",
    // );
    // defer gpu_device.destroy();

    // try gpu_device.claimWindow(window);

    const W = sc.ecs.World(struct { x: u32 });
    var w: W = .init(gpa, blka, &keygen);
    defer w.deinit();
}
