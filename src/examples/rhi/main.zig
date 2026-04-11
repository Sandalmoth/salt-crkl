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

    // var arena_struct: std.heap.ArenaAllocator = .init(gpa);
    // defer _ = arena_struct.deinit();
    // const arena = arena_struct.allocator();

    try sdl.init(sdl.c.SDL_INIT_VIDEO);
    defer sdl.quit();

    const window = try sdl.createWindow(
        "example_rhi",
        640,
        480,
        sdl.c.SDL_WINDOW_RESIZABLE | sdl.c.SDL_WINDOW_VULKAN,
    );
    defer sdl.destroyWindow(window);

    const ctx = try rhi.Vulkan.init(gpa, .{
        .getInstanceProcAddress = &getInstanceProcAddress,
        .getRequiredInstanceExtensions = &getRequiredInstanceExtensions,
        .createWindowSurface = &createWindowSurface,
        .getFramebufferSize = &getFramebufferSize,
    }, .{
        .name = "example_rhi",
    });
    defer rhi.Vulkan.deinit(ctx);

    const swapchain = try ctx.createSwapchain(window);
    defer ctx.destroySwapchain(swapchain);

    try ctx.recreateSwapchain(swapchain);

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.c.SDL_EVENT_QUIT) break :main_loop;
            if (event.type == sdl.c.SDL_EVENT_KEY_DOWN) switch (event.key.key) {
                sdl.c.SDLK_ESCAPE => break :main_loop,
                else => {},
            };
        }

        std.Thread.sleep(10_000_000);

        const swapchain_image = ctx.waitAndAcquireSwapchainTexture(swapchain) catch |e| switch (e) {
            error.OutOfDate => {
                std.debug.print("hit out of date\n", .{});
                try ctx.recreateSwapchain(swapchain); // TODO handle minimized
                continue :main_loop;
            },
            else => return e,
        };
        _ = swapchain_image;
        const command_buffer = try ctx.acquireCommandBuffer(.graphics);
        command_buffer.present(swapchain);
        _ = try ctx.submit(&.{command_buffer});
    }

    // const ctx: *rhi.Context = try .create(gpa, .{
    //     .getInstanceProcAddress = &getInstanceProcAddress,
    //     .getRequiredInstanceExtensions = &getRequiredInstanceExtensions,
    //     .createWindowSurface = &createWindowSurface,
    //     .getFramebufferSize = &getFramebufferSize,
    //     .window = window,
    // }, "example_rhi");
    // defer ctx.destroy();

    // const vertex_buffer = try ctx.createBuffer(.{
    //     .usage = .{
    //         .transfer_dst = true,
    //     },
    //     .size = 1024,
    // });
    // defer ctx.destroyBuffer(vertex_buffer);
    // std.debug.print("{}\n", .{vertex_buffer});

    // const index_buffer = try ctx.createBuffer(.{
    //     .usage = .{
    //         .transfer_dst = true,
    //         .index = true,
    //     },
    //     .size = 1024,
    // });
    // defer ctx.destroyBuffer(index_buffer);
    // std.debug.print("{}\n", .{index_buffer});

    // const vertex_shader = try ctx.createShader(
    //     .vertex,
    //     std.mem.bytesAsSlice(u32, &shader_vertex_spv),
    // );
    // defer ctx.destroyShader(vertex_shader);
    // const fragment_shader = try ctx.createShader(
    //     .fragment,
    //     std.mem.bytesAsSlice(u32, &shader_fragment_spv),
    // );
    // defer ctx.destroyShader(fragment_shader);

    // const color_target = try ctx.createTexture(.{
    //     .usage = .{
    //         .color_attachment = true,
    //         .sampled = true,
    //         .transfer_src = true,
    //     },
    //     .image_type = .image_2d,
    //     .mip_levels = 1,
    //     .size = .{ 640, 480, 1 },
    //     .format = .r8g8b8a8_srgb,
    // });
    // defer ctx.destroyTexture(color_target);
    // std.debug.print("{}\n", .{color_target});

    // const pipeline = try ctx.createGraphicsPipeline(.{
    //     .vertex_shader = vertex_shader,
    //     .fragment_shader = fragment_shader,
    //     .color_attachments = &.{.{
    //         .format = .r8g8b8a8_srgb,
    //     }},
    // }, .{
    //     .viewport = .{
    //         .x = 0,
    //         .y = 0,
    //         .width = 640,
    //         .height = 480,
    //         .min_depth = 0,
    //         .max_depth = 1,
    //     },
    //     .scissor = .{
    //         .x = 0,
    //         .y = 0,
    //         .width = 640,
    //         .height = 480,
    //     },
    //     .rasterization = .{ .cull_mode = .{ .back = false, .front = false } },
    //     .depth_stencil = .{ .depth_test = null, .enable_depth_write = false },
    // });
    // defer ctx.destroyGraphicsPipeline(pipeline);

    // const upload_buffer = try ctx.createTransferBuffer(.upload, 1024 * 1024);
    // defer ctx.destroyTransferBuffer(upload_buffer);
    // const upload_allocator = upload_buffer.allocator();

    // const vertex_staging = try upload_allocator.alloc([3]f32, 4);
    // vertex_staging[0..4].* = .{
    //     .{ -0.9, -0.9, 0.5 },
    //     .{ 0.9, -0.9, 0.5 },
    //     .{ -0.9, 0.9, 0.5 },
    //     .{ 0.9, 0.9, 0.5 },
    // };
    // const index_staging = try upload_allocator.alloc(u32, 6);
    // index_staging[0..6].* = .{ 0, 2, 1, 2, 3, 1 };

    // for (0..32) |i| {
    //     const bytes = upload_buffer.mapped_memory[i * 4 .. (i + 1) * 4];
    //     std.debug.print("{}\t{any}\n", .{ i, bytes });
    // }

    // {
    //     const command_buffer = try ctx.acquireCommandBuffer(arena);
    //     try command_buffer.uploadToBuffer(upload_buffer, vertex_staging, vertex_buffer, 0);
    //     try command_buffer.uploadToBuffer(upload_buffer, index_staging, index_buffer, 0);
    //     try command_buffer.barrier(
    //         .{ .transfer = true },
    //         .{ .vertex = true },
    //         .{ .storage = true },
    //         &.{},
    //     );
    //     _ = try ctx.submitCommandBuffer(command_buffer);
    // }

    // var prev_submit: u64 = 0;
    // var last_submit: u64 = 0;

    // main_loop: while (true) {
    //     _ = arena_struct.reset(.retain_capacity);

    //     var event: sdl.Event = undefined;
    //     while (sdl.pollEvent(&event)) {
    //         if (event.type == sdl.c.SDL_EVENT_QUIT) break :main_loop;
    //         if (event.type == sdl.c.SDL_EVENT_KEY_DOWN) switch (event.key.key) {
    //             sdl.c.SDLK_ESCAPE => break :main_loop,
    //             else => {},
    //         };
    //     }

    //     // std.Thread.sleep(100_000_000);

    //     // lets just aim for a hello triangle as step one
    //     // just to see what needs to be abstracted
    //     const command_buffer = try ctx.acquireCommandBuffer(arena);

    //     try command_buffer.barrier(
    //         .{ .fragment = true },
    //         .{ .fragment = true },
    //         .{ .attachment = true },
    //         &.{.{ .texture = color_target, .layout = .attachment, .preserve_contents = false }},
    //     );
    //     try command_buffer.beginRenderPass(pipeline, &.{
    //         .{
    //             .texture = color_target,
    //             .load_op = .clear,
    //             .store_op = .store,
    //             .clear_value = .{ .color = .{ .float = .{ 0, 1.0, 0, 1.0 } } }, // FIXME UGLY!
    //         },
    //     }, null, null);
    //     try command_buffer.bindIndexBuffer(index_buffer, 0);
    //     try command_buffer.pushConstant(u64, vertex_buffer.buffer_device_address);
    //     try command_buffer.drawIndexedInstanced(6, 1, 0, 0, 0);
    //     try command_buffer.endRenderPass();

    //     const swapchain = try command_buffer.acquireSwapchain(ctx);
    //     try command_buffer.barrier(
    //         .{ .fragment = true },
    //         .{ .transfer = true },
    //         .{ .attachment = true, .storage = true },
    //         &.{.{ .texture = color_target, .layout = .transfer_src, .preserve_contents = true }},
    //     );
    //     try command_buffer.barrier(
    //         .{ .transfer = true },
    //         .{ .transfer = true },
    //         .{ .storage = true },
    //         &.{.{ .texture = swapchain, .layout = .transfer_dst, .preserve_contents = false }},
    //     );
    //     try command_buffer.blit(color_target, .{
    //         .bounds = .{
    //             .{ 0, 0, 0 },
    //             .{
    //                 @intCast(color_target.size[0]),
    //                 @intCast(color_target.size[1]),
    //                 @intCast(color_target.size[2]),
    //             },
    //         },
    //         .mip_level = 0,
    //     }, swapchain, .{
    //         .bounds = .{
    //             .{ 0, 0, 0 },
    //             .{
    //                 @intCast(swapchain.size[0]),
    //                 @intCast(swapchain.size[1]),
    //                 @intCast(swapchain.size[2]),
    //             },
    //         },
    //         .mip_level = 0,
    //     });

    //     // [x] bind our pipeline
    //     // [x] bind the off-screen texture as the render target
    //     // [x] bind the index buffer
    //     // [x] push constant upload with the vertex buffer address
    //     // [x] draw
    //     // [ ] present
    //     //   - queue ownership transfer of off-screen buffer?

    //     try ctx.wait(prev_submit);
    //     prev_submit = last_submit;
    //     last_submit = try ctx.submitCommandBuffer(command_buffer);
    // }

    // try ctx.wait(last_submit);
}

fn getInstanceProcAddress(
    instance: rhi.Vulkan.vk.Instance,
    procname: [*:0]const u8,
) rhi.Vulkan.vk.PfnVoidFunction {
    const raw = sdl.c.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse {
        std.log.err("SDL_Vulkan_GetVkGetInstanceProcAddr: {s}", .{sdl.getError()});
        @panic("unrecoverable");
    };
    return @as(rhi.Vulkan.vk.PfnGetInstanceProcAddr, @ptrCast(raw))(instance, procname);
}

fn getRequiredInstanceExtensions() ![]const [*:0]const u8 {
    var n: u32 = 0;
    const exts = sdl.c.SDL_Vulkan_GetInstanceExtensions(&n);
    if (exts == null) {
        std.log.err("SDL_Vulkan_GetInstanceExtensions: {s}", .{sdl.getError()});
        return error.Platform;
    }
    if (n == 0) return &.{};
    return @ptrCast(exts[0..n]);
}

fn createWindowSurface(instance: rhi.Vulkan.vk.Instance, window: *anyopaque) !rhi.Vulkan.vk.SurfaceKHR {
    const instance_ptr: ?*sdl.c.struct_VkInstance_T = @ptrFromInt(@intFromEnum(instance));
    var surface_ptr: ?*sdl.c.struct_VkSurfaceKHR_T = null;
    if (!sdl.c.SDL_Vulkan_CreateSurface(@ptrCast(window), instance_ptr, null, &surface_ptr)) {
        std.log.err("SDL_Vulkan_CreateSurface: {s}", .{sdl.getError()});
        return error.Platform;
    }
    return @enumFromInt(@intFromPtr(surface_ptr));
}

fn getFramebufferSize(window: *anyopaque) !rhi.Vulkan.vk.Extent2D {
    // NOTE this is called when (re)creating the swapchain
    // and SDL_GetWindowSizeInPixels needs to be on main thread in some cases
    // so, for the platform interface we might need to put some threading restrictions?
    var width: c_int = undefined;
    var height: c_int = undefined;
    if (!sdl.c.SDL_GetWindowSizeInPixels(@ptrCast(window), &width, &height)) {
        std.log.err("SDL_GetWindowSizeInPixels: {s}", .{sdl.getError()});
        return error.Platform;
    }
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
    };
}
