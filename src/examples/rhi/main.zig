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

    const ctx: *rhi.Context = try .create(gpa, .{
        .getInstanceProcAddress = &getInstanceProcAddress,
        .getRequiredInstanceExtensions = &getRequiredInstanceExtensions,
        .createWindowSurface = &createWindowSurface,
        .getFramebufferSize = &getFramebufferSize,
        .window = window,
    }, .{}, "example_rhi");
    defer ctx.destroy();

    var frame_in_flight: u32 = 0;

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

        // i guess we should make creating image arrays easy
        // since we cant do the cycle abstraction or it would break the bindless handles i think
        // const backbuffer = ctx.createTexture(size, format, );

        // const command_buffer = ctx.acquireCommandBuffer(.graphics);
        // const pass = command_buffer.beginRenderPass(.{
        //     .color_target = backbuffer[frame_index],
        // });
        // pass.bindPipeline(pipeline_handle);
        // pass.bindIndexBuffer(index_buffer_handle);
        // pass.drawIndexed(index_count);
        // pass.endAndPresent(backbuffer);

        // lets just write out the code to do an empty present
        // just to see what needs to be abstracted
        frame_in_flight = (frame_in_flight + 1) % 2;
        const command_buffer = ctx.acquireCommandBuffer(.graphics);
        try ctx.submitCommandBuffer(command_buffer);
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

fn createWindowSurface(instance: rhi.vk.Instance, window: *anyopaque) !rhi.vk.SurfaceKHR {
    const instance_ptr: ?*sdl.c.struct_VkInstance_T = @ptrFromInt(@intFromEnum(instance));
    var surface_ptr: ?*sdl.c.struct_VkSurfaceKHR_T = null;
    if (!sdl.c.SDL_Vulkan_CreateSurface(@ptrCast(window), instance_ptr, null, &surface_ptr)) {
        std.log.err("SDL_Vulkan_CreateSurface: {s}", .{sdl.getError()});
        return error.Sdl;
    }
    return @enumFromInt(@intFromPtr(surface_ptr));
}

fn getFramebufferSize(window: *anyopaque) !rhi.vk.Extent2D {
    // NOTE this is called when (re)creating the swapchain
    // and SDL_GetWindowSizeInPixels needs to be on main thread in some cases
    // so, for the platform interface we might need to put some threading restrictions?
    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!sdl.c.SDL_GetWindowSizeInPixels(@ptrCast(window), &width, &height)) {
        std.log.err("SDL_GetWindowSizeInPixels: {s}", .{sdl.getError()});
        return error.Sdl;
    }
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
    };
}
