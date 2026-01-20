const rhi = @import("rhi");
const std = @import("std");

const sdl = @import("sdl.zig");

pub fn main() !void {
    sdl.setMainReady();

    var gpa_struct: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_struct.deinit();
    const gpa = gpa_struct.allocator();

    try sdl.init(sdl.c.SDL_INIT_VIDEO);
    defer sdl.quit();

    const window = try sdl.createWindow(
        "example_rhi",
        640,
        480,
        sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_VULKAN,
    );
    defer sdl.destroyWindow(window);

    std.debug.print("{*}\n", .{sdl.c.SDL_Vulkan_GetVkGetInstanceProcAddr()});
    for (try getRequiredInstanceExtensions()) |ext| {
        std.debug.print("{s}\n", .{std.mem.span(ext)});
    }

    var ctx: rhi.Context = try .init(gpa, .{
        .getInstanceProcAddress = &getInstanceProcAddress,
        .getRequiredInstanceExtensions = &getRequiredInstanceExtensions,
        .createWindowSurface = undefined,
        .getFramebufferSize = undefined,
    }, "example_rhi");
    defer ctx.deinit();

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.c.SDL_EVENT_QUIT) break :main_loop;
            if (event.type == sdl.c.SDL_EVENT_KEY_DOWN) switch (event.key.key) {
                sdl.c.SDLK_ESCAPE => break :main_loop,
                else => {},
            };
        }

        std.debug.print("yo\n", .{});

        std.Thread.sleep(100_000_000);
    }
}

fn getInstanceProcAddress(
    instance: rhi.vk.Instance,
    procname: [*:0]const u8,
) rhi.vk.PfnVoidFunction {
    const raw = sdl.c.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse {
        std.log.err("SDL_Vulkan_GetVkGetInstanceProcAddr: {s}", .{sdl.getError()});
        @panic("unrecoverable");
    };
    return @as(rhi.vk.PfnGetInstanceProcAddr, @ptrCast(raw))(instance, procname);
}

fn getRequiredInstanceExtensions() ![]const [*:0]const u8 {
    var n: u32 = 0;
    const exts = sdl.c.SDL_Vulkan_GetInstanceExtensions(&n);
    if (exts == null) {
        std.log.err("SDL_Vulkan_GetInstanceExtensions: {s}", .{sdl.getError()});
        return error.Sdl;
    }
    if (n == 0) return &.{};
    return @ptrCast(exts[0..n]);
}
