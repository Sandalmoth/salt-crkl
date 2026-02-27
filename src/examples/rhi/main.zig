const rhi = @import("rhi");
const std = @import("std");

const sdl = @import("sdl.zig");

const shader_vertex_spv align(@alignOf(u32)) = @embedFile("slang_shader_vertex_spv").*;
const shader_fragment_spv align(@alignOf(u32)) = @embedFile("slang_shader_fragment_spv").*;

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

    var transfer_buffer = try ctx.createTransferBuffer(.upload, 1024 * 1024);
    defer transfer_buffer.deinit();

    var vertex_buffer = try ctx.createBuffer(.{}, .{ .size = 1024 });
    defer ctx.destroyBuffer(&vertex_buffer);
    std.debug.print("{}\n", .{vertex_buffer});

    var index_buffer = try ctx.createBuffer(.{}, .{ .size = 1024 });
    defer ctx.destroyBuffer(&index_buffer);
    std.debug.print("{}\n", .{index_buffer});

    var vertex_shader = try ctx.createShader(
        .vertex,
        std.mem.bytesAsSlice(u32, &shader_vertex_spv),
    );
    defer ctx.destroyShader(&vertex_shader);
    var fragment_shader = try ctx.createShader(
        .fragment,
        std.mem.bytesAsSlice(u32, &shader_fragment_spv),
    );
    defer ctx.destroyShader(&fragment_shader);

    // const color_target_views: [1]rhi.ImageViewCreateInfo = .{
    //     .{},
    // };
    var color_target = try ctx.createTexture(.{ .dedicated = .if_preferred }, .{
        .usage = .{
            .color_attachment = true,
            .sampled = true,
        },
        .image_type = .image_2d,
        .mip_levels = 1,
        .size = .{ 640, 480, 1 },
        .queue = .graphics,
        .format = .r8g8b8a8_srgb,
        // .views = &color_target_views,
    });
    color_target = color_target;
    std.debug.print("{}\n", .{color_target});

    var pipeline = try ctx.createGraphicsPipeline(.{
        .vertex_shader = &vertex_shader,
        .fragment_shader = &fragment_shader,
    }, .{
        .viewport = .{
            .x = 0,
            .y = 0,
            .width = 640,
            .height = 640,
            .min_depth = 0,
            .max_depth = 1,
        },
        .scissor = .{
            .x = 0,
            .y = 0,
            .width = 640,
            .height = 640,
        },
    });
    defer ctx.destroyGraphicsPipeline(&pipeline);

    // create an off-screen texture to render to

    // {
    //     const command_buffer = ctx.acquireCommandBuffer(.graphics);
    //     try command_buffer.uploadToBuffer(
    //         std.mem.sliceAsBytes(&[4][3]f32{
    //             .{ -1, -1, 0.5 },
    //             .{ 1, -1, 0.5 },
    //             .{ -1, 1, 0.5 },
    //             .{ 1, 1, 0.5 },
    //         }),
    //         &upload_buffer,
    //         &vertex_buffer,
    //         0,
    //     );
    //     try command_buffer.uploadToBuffer(
    //         std.mem.sliceAsBytes(&[6]u32{ 0, 2, 1, 2, 3, 1 }),
    //         &upload_buffer,
    //         &index_buffer,
    //         0,
    //     );
    //     try ctx.submitCommandBuffer(command_buffer);
    // }

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

        // lets just aim for a hello triangle as step one
        // just to see what needs to be abstracted
        frame_in_flight = (frame_in_flight + 1) % 2;
        const command_buffer = ctx.acquireCommandBuffer(.graphics);

        // bind our pipeline
        // bind the off-screen texture as the render target
        // bind the index buffer
        // push constant upload with the vertex buffer address
        // draw
        // present
        //   - queue ownership transfer of off-screen buffer

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
