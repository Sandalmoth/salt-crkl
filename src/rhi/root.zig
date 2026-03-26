const std = @import("std");
pub const vk = @import("vulkan");

const OffsetAllocator = @import("OffsetAllocator.zig").Allocator;
const Allocation = @import("OffsetAllocator.zig").Allocation;

const log = std.log.scoped(.rhi);

const enable_debug = @import("builtin").mode == .Debug;

const api_version: u32 = @bitCast(vk.API_VERSION_1_3);

const layers = [_][*:0]const u8{};
const debug_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const instance_extensions = [_][*:0]const u8{
    "VK_KHR_surface",
};
const debug_instance_extensions = [_][*:0]const u8{};

const device_extensions = [_][*:0]const u8{
    "VK_KHR_swapchain",
};
const debug_device_extensions = [_][*:0]const u8{};

const device_features = vk.PhysicalDeviceFeatures{
    .multi_draw_indirect = .true,
    .draw_indirect_first_instance = .true,
    .shader_int_64 = .true,
    .texture_compression_bc = .true,
    .depth_bias_clamp = .true, // maybe we should remove this requirement?
};
const device_features_1_1 = vk.PhysicalDeviceVulkan11Features{
    .p_next = @ptrCast(@constCast(&device_features_1_2)),
    .shader_draw_parameters = .true,
};
const device_features_1_2 = vk.PhysicalDeviceVulkan12Features{
    .p_next = @ptrCast(@constCast(&device_features_1_3)),
    .buffer_device_address = .true,
    .descriptor_binding_partially_bound = .true,
    .descriptor_binding_sampled_image_update_after_bind = .true,
    .descriptor_binding_storage_image_update_after_bind = .true,
    .descriptor_binding_update_unused_while_pending = .true,
    .descriptor_indexing = .true,
    .runtime_descriptor_array = .true,
    .shader_sampled_image_array_non_uniform_indexing = .true,
    .shader_storage_image_array_non_uniform_indexing = .true,
    .timeline_semaphore = .true,
    .scalar_block_layout = .true,
};
const device_features_1_3 = vk.PhysicalDeviceVulkan13Features{
    .dynamic_rendering = .true,
    .synchronization_2 = .true,
};

const Platform = struct {
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () anyerror![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) anyerror!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) anyerror!vk.Extent2D,
    window: *anyopaque,
};

pub const SwapchainComposition = enum {
    sdr,

    fn getSwapchainSurfaceFormats(
        swapchain_composition: SwapchainComposition,
    ) []const vk.SurfaceFormatKHR {
        // ranking of preferred formats for the swapchain surfaces
        // if none are present, the first format from getPhysicalDeviceSurfaceFormats is used
        return switch (swapchain_composition) {
            .sdr => &.{
                .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr },
                .{ .format = .r8g8b8a8_srgb, .color_space = .srgb_nonlinear_khr },
                .{ .format = .a8b8g8r8_srgb_pack32, .color_space = .srgb_nonlinear_khr },
            },
        };
    }
};

pub const PresentMode = enum {
    fifo,

    fn vulkan(present_mode: PresentMode) vk.PresentModeKHR {
        return switch (present_mode) {
            .fifo => .fifo_khr,
        };
    }
};

pub const Format = enum {
    r8g8b8a8_unorm,
    r8g8b8a8_srgb,
    b8g8r8a8_unorm,
    b8g8r8a8_srgb,
    r16g16b16a16_sfloat,
    r32_uint,
    s8_uint,
    d16_unorm,
    d16_unorm_s8_uint,
    d24_unorm_s8_uint,
    d32_sfloat,
    d32_sfloat_s8_uint,

    fn vulkan(format: Format) vk.Format {
        return switch (format) {
            .r8g8b8a8_unorm => .r8g8b8a8_unorm,
            .r8g8b8a8_srgb => .r8g8b8a8_srgb,
            .b8g8r8a8_unorm => .b8g8r8a8_unorm,
            .b8g8r8a8_srgb => .b8g8r8a8_srgb,
            .r16g16b16a16_sfloat => .r16g16b16a16_sfloat,
            .r32_uint => .r32_uint,
            .s8_uint => .s8_uint,
            .d16_unorm => .d16_unorm,
            .d16_unorm_s8_uint => .d16_unorm_s8_uint,
            .d24_unorm_s8_uint => .d24_unorm_s8_uint,
            .d32_sfloat => .d32_sfloat,
            .d32_sfloat_s8_uint => .d32_sfloat_s8_uint,
        };
    }
};

pub const ImageLayout = enum {
    undefined,
    general,
    read_only,
    attachment,
    transfer_src,
    transfer_dst,
    depth_attachment_stencil_read_only,
    depth_read_only_stencil_attachment,

    fn vulkan(layout: ImageLayout) vk.ImageLayout {
        return switch (layout) {
            .undefined => .undefined,
            .general => .general,
            .read_only => .read_only_optimal,
            .attachment => .attachment_optimal,
            .transfer_src => .transfer_src_optimal,
            .transfer_dst => .transfer_dst_optimal,
            .depth_attachment_stencil_read_only => .depth_attachment_stencil_read_only_optimal,
            .depth_read_only_stencil_attachment => .depth_read_only_stencil_attachment_optimal,
        };
    }
};

const SampleCount = enum {
    @"1",
    @"2",
    @"4",
    @"8",
    @"16",
    @"32",
    @"64",

    fn vulkan(sample_count: SampleCount) vk.SampleCountFlags {
        return .{
            .@"1_bit" = sample_count == .@"1",
            .@"2_bit" = sample_count == .@"2",
            .@"4_bit" = sample_count == .@"4",
            .@"8_bit" = sample_count == .@"8",
            .@"16_bit" = sample_count == .@"16",
            .@"32_bit" = sample_count == .@"32",
            .@"64_bit" = sample_count == .@"64",
        };
    }
};

pub const BufferCreateInfo = struct {
    usage: packed struct(u32) {
        storage: bool = false,
        transfer_src: bool = false,
        transfer_dst: bool = false,
        index: bool = false,
        indirect: bool = false,
        _padding: u27 = 0,
    },
    size: usize,
};

pub const TextureCreateInfo = struct {
    usage: packed struct(u32) {
        storage: bool = false,
        sampled: bool = false,
        transfer_src: bool = false,
        transfer_dst: bool = false,
        color_attachment: bool = false,
        depth_stencil_attachment: bool = false,
        _padding: u26 = 0,
    },
    format: Format,
    image_type: enum {
        // more distinct than the vulkan image type
        // to allow us to make a useful default view
        image_1d,
        image_2d,
        image_3d,
        image_cube,
        image_2d_array,
        image_cube_array,

        fn vulkanImageType(image_type: @This()) vk.ImageType {
            return switch (image_type) {
                .image_1d => .@"1d",
                .image_2d => .@"2d",
                .image_3d => .@"3d",
                .image_cube => .@"2d",
                .image_2d_array => .@"2d",
                .image_cube_array => .@"2d",
            };
        }

        fn vulkanImageViewType(image_type: @This()) vk.ImageViewType {
            return switch (image_type) {
                .image_1d => .@"1d",
                .image_2d => .@"2d",
                .image_3d => .@"3d",
                .image_cube => .cube,
                .image_2d_array => .@"2d_array",
                .image_cube_array => .cube_array,
            };
        }
    },
    mip_levels: u32,
    size: [3]u32, // x, y, z or depth
    samples: SampleCount = .@"1",
    views: []const ImageViewCreateInfo = &.{},
};

pub const ImageViewCreateInfo = struct {
    view_type: ?enum {
        view_1d,
        view_2d,
        view_3d,
        view_cube,
        view_1d_array,
        view_2d_array,
        view_cube_array,
    } = null,
    format: ?Format = null,
    swizzle: struct {
        const Component = enum {
            zero,
            one,
            r,
            g,
            b,
            a,

            fn vulkan(component: Component) vk.ComponentSwizzle {
                return switch (component) {
                    .zero => .zero,
                    .one => .one,
                    .r => .r,
                    .g => .g,
                    .b => .b,
                    .a => .a,
                };
            }
        };
        r: Component = .r,
        g: Component = .g,
        b: Component = .b,
        a: Component = .a,

        fn vulkan(swizzle: @This()) vk.ComponentMapping {
            return .{
                .r = if (swizzle.r == .r) .identity else swizzle.r.vulkan(),
                .g = if (swizzle.g == .g) .identity else swizzle.g.vulkan(),
                .b = if (swizzle.b == .b) .identity else swizzle.b.vulkan(),
                .a = if (swizzle.a == .a) .identity else swizzle.a.vulkan(),
            };
        }
    } = .{},
    range: ?struct {
        base_mip_level: u32,
        level_count: u32,
        base_array_layer: u32,
        layer_count: u32,
        mask: ?enum { depth, stencil },
    } = null,
};

const Shader = struct {
    const ShaderType = enum { vertex, fragment, compute };
    stage: vk.ShaderStageFlags,
    module: vk.ShaderModule,
};

const Buffer = struct {
    memory: union(enum) {
        slab: struct {
            allocation: Allocation,
            slab: *Allocator.Slab,
        },
        dedicated: vk.DeviceMemory,
    },
    buffer: vk.Buffer,
    size: usize,
    buffer_device_address: u64,
};

const Texture = struct {
    memory: union(enum) {
        slab: struct {
            allocation: Allocation,
            slab: *Allocator.Slab,
        },
        dedicated: vk.DeviceMemory,
    },
    image: vk.Image,
    default_view: vk.ImageView,
    size: [3]u32,
    layout: vk.ImageLayout,
    format: Format,
    mip_levels: u32,
};

const Sampler = struct {};

pub const Context = struct {
    gpa: std.mem.Allocator,
    platform: Platform,

    base: vk.BaseWrapper,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,

    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    physical_device_properties: vk.PhysicalDeviceProperties,
    physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

    queue: vk.QueueProxy,
    queue_family: u32,
    queue_semaphore: vk.Semaphore,
    queue_semaphore_value: u64,

    swapchain: Swapchain,
    old_swapchains: std.ArrayList(Swapchain),

    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,

    swapchain_composition: SwapchainComposition,
    present_mode: PresentMode = .fifo,

    allocator: Allocator,

    shader_pool: std.heap.MemoryPool(Shader),
    graphics_pipeline_pool: std.heap.MemoryPool(GraphicsPipeline),
    compute_pipeline_pool: std.heap.MemoryPool(ComputePipeline),
    transfer_buffer_pool: std.heap.MemoryPool(TransferBuffer),
    sampler_pool: std.heap.MemoryPool(Sampler),
    texture_pool: std.heap.MemoryPool(Texture),
    buffer_pool: std.heap.MemoryPool(Buffer),
    command_buffer_pool: std.heap.MemoryPool(CommandBuffer),

    command_buffers: std.ArrayList(struct {
        pool: vk.CommandPool,
        buffer: vk.CommandBuffer,
        semaphore_value: u64,
    }),
    pending_memory_barriers: std.ArrayList(vk.MemoryBarrier2),
    pending_image_barriers: std.ArrayList(vk.ImageMemoryBarrier2),

    image_acquire_semaphores: std.ArrayList(struct {
        semaphore: vk.Semaphore,
        semaphore_value: u64,
    }),

    pub fn create(
        gpa: std.mem.Allocator,
        platform: Platform,
        app_name: [:0]const u8,
    ) !*Context {
        const ctx = try gpa.create(Context);

        var arena_struct: std.heap.ArenaAllocator = .init(gpa);
        defer arena_struct.deinit();
        const arena = arena_struct.allocator();

        ctx.gpa = gpa;
        ctx.platform = platform;
        ctx.base = .load(platform.getInstanceProcAddress);

        try ctx.initInstance(arena, platform, app_name);
        errdefer ctx.deinitInstance();
        try ctx.createSurface(platform);
        errdefer ctx.destroySurface();
        const physical_device_candidate = try ctx.pickPhysicalDevice(arena);
        try ctx.initDevice(physical_device_candidate);
        errdefer ctx.deinitDevice();
        ctx.old_swapchains = .empty;
        // QUESTION what if the window starts out minimized?
        // currently that means context creation fails
        ctx.swapchain = try .init(ctx, .null_handle);
        errdefer ctx.swapchain.deinit(ctx);

        try ctx.initPipelineLayout();
        errdefer ctx.deinitPipelineLayout();
        ctx.allocator = try .init(ctx);
        errdefer ctx.allocator.deinit();

        ctx.shader_pool = .init(std.heap.page_allocator);
        ctx.graphics_pipeline_pool = .init(std.heap.page_allocator);
        ctx.compute_pipeline_pool = .init(std.heap.page_allocator);
        ctx.transfer_buffer_pool = .init(std.heap.page_allocator);
        ctx.sampler_pool = .init(std.heap.page_allocator);
        ctx.texture_pool = .init(std.heap.page_allocator);
        ctx.buffer_pool = .init(std.heap.page_allocator);
        ctx.command_buffer_pool = .init(std.heap.page_allocator);

        ctx.command_buffers = .empty;
        ctx.pending_memory_barriers = .empty;
        ctx.pending_image_barriers = .empty;
        ctx.image_acquire_semaphores = .empty;

        // ctx.staging_allocs.getPtr(.upload).* = try .init(ctx, .upload, 256 * 1024 * 1024, 3);
        // ctx.staging_allocs.getPtr(.download).* = try .init(ctx, .download, 256 * 1024 * 1024, 1);

        return ctx;
    }

    pub fn destroy(ctx: *Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in vulkan_context deinit: {}", .{e});
        };

        // ctx.staging_allocs.getPtr(.upload).deinit();
        // ctx.staging_allocs.getPtr(.download).deinit();

        if (ctx.pending_memory_barriers.items.len > 0) {
            log.debug("pending memory barriers not empty on destroy", .{});
        }
        ctx.pending_memory_barriers.deinit(ctx.gpa);
        if (ctx.pending_image_barriers.items.len > 0) {
            log.debug("pending image barriers not empty on destroy", .{});
        }
        ctx.pending_image_barriers.deinit(ctx.gpa);

        ctx.shader_pool.deinit();
        ctx.graphics_pipeline_pool.deinit();
        ctx.compute_pipeline_pool.deinit();
        ctx.transfer_buffer_pool.deinit();
        ctx.sampler_pool.deinit();
        ctx.texture_pool.deinit();
        ctx.buffer_pool.deinit();
        ctx.command_buffer_pool.deinit();

        for (ctx.command_buffers.items) |command_buffer| {
            ctx.device.freeCommandBuffers(
                command_buffer.pool,
                1,
                @ptrCast(&command_buffer.buffer),
            );
            ctx.device.destroyCommandPool(command_buffer.pool, null);
        }
        ctx.command_buffers.deinit(ctx.gpa);

        for (ctx.image_acquire_semaphores.items) |semaphore| {
            ctx.device.destroySemaphore(semaphore.semaphore, null);
        }
        ctx.image_acquire_semaphores.deinit(ctx.gpa);

        ctx.allocator.deinit();

        ctx.deinitPipelineLayout();

        for (ctx.old_swapchains.items) |*swapchain| swapchain.deinit(ctx);
        ctx.old_swapchains.deinit(ctx.gpa);
        ctx.swapchain.deinit(ctx);
        ctx.deinitDevice();
        ctx.destroySurface();
        ctx.deinitInstance();

        ctx.gpa.destroy(ctx);
    }

    pub fn acquireCommandBuffer(ctx: *Context, arena: std.mem.Allocator) !*CommandBuffer {
        const cmdbuf = try ctx.command_buffer_pool.create();
        cmdbuf.* = .init(arena);
        return cmdbuf;
    }

    pub fn submitCommandBuffer(ctx: *Context, command_buffer: *CommandBuffer) !u64 {
        const semaphore_value = try ctx.device.getSemaphoreCounterValue(ctx.queue_semaphore);
        const cmdbuf = blk: {
            for (ctx.command_buffers.items) |*x| {
                if (x.semaphore_value > semaphore_value) continue;
                try ctx.device.resetCommandPool(x.pool, .{});
                x.semaphore_value = ctx.queue_semaphore_value + 1;
                break :blk x.buffer;
            }

            const pool = try ctx.device.createCommandPool(&.{
                .flags = .{},
                .queue_family_index = ctx.queue_family,
            }, null);
            errdefer ctx.device.destroyCommandPool(pool, null);
            var buffer: vk.CommandBuffer = .null_handle;
            try ctx.device.allocateCommandBuffers(&.{
                .command_pool = pool,
                .level = .primary,
                .command_buffer_count = 1,
            }, @ptrCast(&buffer));
            errdefer ctx.device.freeCommandBuffers(pool, 1, @ptrCast(&buffer));
            try ctx.command_buffers.append(ctx.gpa, .{
                .pool = pool,
                .buffer = buffer,
                .semaphore_value = ctx.queue_semaphore_value + 1,
            });
            break :blk buffer;
        };
        try ctx.device.beginCommandBuffer(cmdbuf, &.{ .flags = .{ .one_time_submit_bit = true } });

        var it = command_buffer.commands.iterator(0);
        while (it.next()) |command| {
            switch (command.*) {
                .buffer_upload => |cmd| {
                    // touches memory so needs to potentially flush all pending barriers
                    ctx.device.cmdPipelineBarrier2(cmdbuf, &.{
                        .memory_barrier_count = @intCast(ctx.pending_memory_barriers.items.len),
                        .p_memory_barriers = ctx.pending_memory_barriers.items.ptr,
                        .image_memory_barrier_count = @intCast(ctx.pending_image_barriers.items.len),
                        .p_image_memory_barriers = ctx.pending_image_barriers.items.ptr,
                    });
                    ctx.pending_memory_barriers.clearRetainingCapacity();
                    ctx.pending_image_barriers.clearRetainingCapacity();

                    // NOTE we could accumulate regions per buffer combination and batch
                    const region: vk.BufferCopy = .{
                        .src_offset = cmd.src_offset,
                        .dst_offset = cmd.dst_offset,
                        .size = cmd.size,
                    };
                    ctx.device.cmdCopyBuffer(
                        cmdbuf,
                        cmd.src_buffer,
                        cmd.dst_buffer,
                        1,
                        @ptrCast(&region),
                    );
                },
                .barrier => |cmd| {
                    try ctx.pending_memory_barriers.ensureUnusedCapacity(ctx.gpa, 1);
                    try ctx.pending_image_barriers.ensureUnusedCapacity(
                        ctx.gpa,
                        cmd.transitions.len,
                    );
                    const access = cmd.vulkanAccessFlags();
                    const barrier: vk.MemoryBarrier2 = .{
                        .src_stage_mask = cmd.vulkanStageFlags(.src),
                        .src_access_mask = access,
                        .dst_stage_mask = cmd.vulkanStageFlags(.dst),
                        .dst_access_mask = access,
                    };
                    ctx.pending_memory_barriers.appendAssumeCapacity(barrier);
                    for (cmd.transitions) |transition| {
                        ctx.pending_image_barriers.appendAssumeCapacity(.{
                            .src_stage_mask = barrier.src_stage_mask,
                            .src_access_mask = barrier.src_access_mask,
                            .dst_stage_mask = barrier.dst_stage_mask,
                            .dst_access_mask = barrier.dst_access_mask,
                            .old_layout = if (transition.preserve_contents)
                                transition.texture.layout
                            else
                                .undefined,
                            .new_layout = transition.layout.vulkan(),
                            .src_queue_family_index = ctx.queue_family,
                            .dst_queue_family_index = ctx.queue_family,
                            .image = transition.texture.image,
                            .subresource_range = .{
                                .base_mip_level = 0,
                                .level_count = transition.texture.mip_levels,
                                .base_array_layer = 0,
                                .layer_count = transition.texture.size[2], // FIXME probably validation error for 3d texture?
                                .aspect_mask = switch (transition.texture.format) {
                                    .s8_uint => .{ .stencil_bit = true },
                                    .d16_unorm,
                                    .d16_unorm_s8_uint,
                                    .d24_unorm_s8_uint,
                                    .d32_sfloat,
                                    .d32_sfloat_s8_uint,
                                    => .{ .depth_bit = true },
                                    else => .{ .color_bit = true },
                                },
                            },
                        });
                        // TODO we should error if the same image is transitioned twice in one barrier maybe?
                        // or we could just do whatever is the last one but merge the stages/accesses?
                        transition.texture.layout = transition.layout.vulkan();
                    }
                },
                .begin_render_pass => |cmd| {
                    // flush barriers, transitions need to happen before binding
                    ctx.device.cmdPipelineBarrier2(cmdbuf, &.{
                        .memory_barrier_count = @intCast(ctx.pending_memory_barriers.items.len),
                        .p_memory_barriers = ctx.pending_memory_barriers.items.ptr,
                        .image_memory_barrier_count = @intCast(ctx.pending_image_barriers.items.len),
                        .p_image_memory_barriers = ctx.pending_image_barriers.items.ptr,
                    });
                    ctx.pending_memory_barriers.clearRetainingCapacity();
                    ctx.pending_image_barriers.clearRetainingCapacity();

                    const color_attachment_infos: []vk.RenderingAttachmentInfo = if (cmd.color_attachments.len > 0)
                        try command_buffer.arena.alloc(vk.RenderingAttachmentInfo, cmd.color_attachments.len)
                    else
                        &.{};

                    const depth_attachment_info: ?*vk.RenderingAttachmentInfo = if (cmd.depth_attachment != null)
                        try command_buffer.arena.create(vk.RenderingAttachmentInfo)
                    else
                        null;
                    const stencil_attachment_info: ?*vk.RenderingAttachmentInfo = if (cmd.stencil_attachment != null)
                        try command_buffer.arena.create(vk.RenderingAttachmentInfo)
                    else
                        null;

                    for (cmd.color_attachments, 0..) |attachment, i| {
                        color_attachment_infos[i] = .{
                            .image_view = attachment.texture.default_view,
                            .image_layout = attachment.texture.layout,
                            .resolve_mode = .{},
                            .resolve_image_layout = .undefined,
                            .load_op = attachment.load_op.vulkan(),
                            .store_op = attachment.store_op.vulkan(),
                            .clear_value = attachment.clear_value.vulkan(),
                        };
                    }
                    if (cmd.depth_attachment) |attachment| {
                        _ = attachment;
                    }
                    if (cmd.stencil_attachment) |attachment| {
                        _ = attachment;
                    }

                    ctx.device.cmdBeginRendering(cmdbuf, &.{
                        .color_attachment_count = @intCast(color_attachment_infos.len),
                        .p_color_attachments = color_attachment_infos.ptr,
                        .p_depth_attachment = depth_attachment_info,
                        .p_stencil_attachment = stencil_attachment_info,
                        .layer_count = 1,
                        .view_mask = 0,
                        .render_area = .{
                            .offset = .{ .x = 0, .y = 0 },
                            .extent = cmd.render_area_extent,
                        },
                    });
                    // set all the dynamic state
                    // TODO we should probably store the state in the command buffer and
                    // only update the diff
                    const dynamic_state = cmd.pipeline.dynamic_state;
                    ctx.device.cmdBindPipeline(cmdbuf, .graphics, cmd.pipeline.pipeline);
                    ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(
                        &dynamic_state.viewport.vulkan(),
                    ));
                    ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(
                        &dynamic_state.scissor.vulkan(),
                    ));
                    ctx.device.cmdSetPrimitiveTopology(
                        cmdbuf,
                        dynamic_state.input_assembly.primitive_topology.vulkan(),
                    );
                    ctx.device.cmdSetPrimitiveRestartEnable(
                        cmdbuf,
                        if (dynamic_state.input_assembly.enable_primitive_restart) .true else .false,
                    );
                    ctx.device.cmdSetRasterizerDiscardEnable(
                        cmdbuf,
                        if (dynamic_state.rasterization.enable_rasterizer_discard) .true else .false,
                    );
                    ctx.device.cmdSetCullMode(
                        cmdbuf,
                        dynamic_state.rasterization.cull_mode.vulkan(),
                    );
                    ctx.device.cmdSetFrontFace(
                        cmdbuf,
                        dynamic_state.rasterization.front_face.vulkan(),
                    );
                    if (dynamic_state.rasterization.depth_bias) |depth_bias| {
                        ctx.device.cmdSetDepthBiasEnable(cmdbuf, .true);
                        ctx.device.cmdSetDepthBias(
                            cmdbuf,
                            depth_bias.constant_factor,
                            depth_bias.clamp,
                            depth_bias.slope_factor,
                        );
                    } else {
                        ctx.device.cmdSetDepthBiasEnable(cmdbuf, .false);
                    }
                    if (dynamic_state.depth_stencil.depth_test) |compare_op| {
                        ctx.device.cmdSetDepthTestEnable(cmdbuf, .true);
                        ctx.device.cmdSetDepthCompareOp(cmdbuf, compare_op.vulkan());
                    } else {
                        ctx.device.cmdSetDepthTestEnable(cmdbuf, .false);
                    }
                    ctx.device.cmdSetDepthWriteEnable(
                        cmdbuf,
                        if (dynamic_state.depth_stencil.enable_depth_write) .true else .false,
                    );
                    if (dynamic_state.depth_stencil.stencil_test) |stencil_test| {
                        ctx.device.cmdSetStencilTestEnable(cmdbuf, .true);
                        const front_op_state = stencil_test.front.vulkan();
                        const back_op_state = stencil_test.back.vulkan();
                        ctx.device.cmdSetStencilOp(
                            cmdbuf,
                            .{ .front_bit = true },
                            front_op_state.fail_op,
                            front_op_state.pass_op,
                            front_op_state.depth_fail_op,
                            front_op_state.compare_op,
                        );
                        ctx.device.cmdSetStencilCompareMask(
                            cmdbuf,
                            .{ .front_bit = true },
                            front_op_state.compare_mask,
                        );
                        ctx.device.cmdSetStencilWriteMask(
                            cmdbuf,
                            .{ .front_bit = true },
                            front_op_state.write_mask,
                        );
                        ctx.device.cmdSetStencilReference(
                            cmdbuf,
                            .{ .front_bit = true },
                            front_op_state.reference,
                        );
                        ctx.device.cmdSetStencilOp(
                            cmdbuf,
                            .{ .back_bit = true },
                            back_op_state.fail_op,
                            back_op_state.pass_op,
                            back_op_state.depth_fail_op,
                            back_op_state.compare_op,
                        );
                        ctx.device.cmdSetStencilCompareMask(
                            cmdbuf,
                            .{ .back_bit = true },
                            back_op_state.compare_mask,
                        );
                        ctx.device.cmdSetStencilWriteMask(
                            cmdbuf,
                            .{ .back_bit = true },
                            back_op_state.write_mask,
                        );
                        ctx.device.cmdSetStencilReference(
                            cmdbuf,
                            .{ .back_bit = true },
                            back_op_state.reference,
                        );
                    } else {
                        ctx.device.cmdSetStencilTestEnable(cmdbuf, .false);
                    }
                },
                .end_render_pass => {
                    ctx.device.cmdEndRendering(cmdbuf);
                },
                .bind_index_buffer => |cmd| {
                    ctx.device.cmdBindIndexBuffer(cmdbuf, cmd.buffer, cmd.offset, .uint32);
                },
                .draw_indexed_instanced => |cmd| {
                    ctx.device.cmdDrawIndexed(
                        cmdbuf,
                        cmd.index_count,
                        cmd.instance_count,
                        cmd.first_index,
                        cmd.vertex_offset,
                        cmd.first_instance,
                    );
                },
                .push_constant => |cmd| {
                    ctx.device.cmdPushConstants(
                        cmdbuf,
                        ctx.pipeline_layout,
                        .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
                        0,
                        cmd.size,
                        cmd.data,
                    );
                },
            }
        }

        // always synchronize host at the end, s.t. when the semaphore is hit we can copy data out
        // OPTIMIZE remove this if there were no operations downloading data
        // OPTIMIZE keep track of possible writers and make the barrier more specific
        const host_memory_barrier: vk.MemoryBarrier2 = .{
            .src_stage_mask = .{ .all_commands_bit = true },
            .src_access_mask = .{ .memory_write_bit = true },
            .dst_stage_mask = .{ .host_bit = true },
            .dst_access_mask = .{ .host_read_bit = true },
        };
        ctx.device.cmdPipelineBarrier2(cmdbuf, &.{
            .p_memory_barriers = @ptrCast(&host_memory_barrier),
            .memory_barrier_count = 1,
        });

        try ctx.device.endCommandBuffer(cmdbuf);

        const timeline_semaphore_info: vk.TimelineSemaphoreSubmitInfo = .{
            .p_wait_semaphore_values = @ptrCast(&ctx.queue_semaphore_value),
            .p_signal_semaphore_values = @ptrCast(&(ctx.queue_semaphore_value + 1)),
            .signal_semaphore_value_count = 1,
            .wait_semaphore_value_count = 1,
        };
        const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .top_of_pipe_bit = true };
        const submit_info: vk.SubmitInfo = .{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmdbuf),
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&ctx.queue_semaphore),
            .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&ctx.queue_semaphore),
            .p_next = &timeline_semaphore_info,
        };
        try ctx.queue.submit(
            1,
            @ptrCast(&submit_info),
            .null_handle,
        );

        ctx.command_buffer_pool.destroy(command_buffer);
        ctx.queue_semaphore_value += 1;

        return ctx.queue_semaphore_value;
    }
    //     std.debug.assert(ctx.active_command_buffer == command_buffer.queue_type);
    //     ctx.active_command_buffer = null;

    //     const cmdbuf = try command_buffer.getVulkanCommandBuffer();
    //     try ctx.device.beginCommandBuffer(cmdbuf, &.{
    //         .flags = .{ .one_time_submit_bit = true },
    //     });

    //     std.debug.print("{} ", .{command_buffer.pool_free_command_buffers[0].items.len});
    //     std.debug.print("{} ", .{command_buffer.pool_used_command_buffers[0].items.len});
    //     std.debug.print("{} ", .{command_buffer.pool_free_command_buffers[1].items.len});
    //     std.debug.print("{}\n", .{command_buffer.pool_used_command_buffers[1].items.len});

    //     // this is basically like a vm parsing bytecode
    //     // meaning we could apply compiler theory to simplify it i think
    //     // hell yeah

    //     const hazards = ctx.queue_hazards.getPtr(command_buffer.queue_type);

    //     for (command_buffer.buffer.items) |command| {
    //         switch (command) {
    //             .begin_render_pass => |cmd| {
    //                 // command.begin_render_pass.pipeline
    //                 ctx.device.cmdBeginRendering(cmdbuf, &.{
    //                     .color_attachment_count = @intCast(cmd.color_attachments.len),
    //                     .p_color_attachments = cmd.color_attachments.ptr,
    //                     .p_depth_attachment = cmd.depth_attachment,
    //                     .p_stencil_attachment = cmd.depth_attachment,
    //                     .layer_count = 1,
    //                     .view_mask = 0,
    //                     .render_area = .{
    //                         .offset = .{ .x = 0, .y = 0 },
    //                         .extent = cmd.render_area_extent,
    //                     },
    //                 });
    //             },
    //             .end_render_pass => {
    //                 ctx.device.cmdEndRendering(cmdbuf);
    //             },
    //             .upload_to_buffer => {
    //                 // touches memory so needs to potentially flush all pending barriers

    //                 // NOTE we could accumulate regions per buffer combination and batch
    //                 const region: vk.BufferCopy = .{
    //                     .src_offset = command.upload_to_buffer.src_offset,
    //                     .dst_offset = command.upload_to_buffer.dst_offset,
    //                     .size = command.upload_to_buffer.size,
    //                 };
    //                 ctx.device.cmdCopyBuffer(
    //                     cmdbuf,
    //                     command.upload_to_buffer.src_buffer,
    //                     command.upload_to_buffer.dst_buffer,
    //                     1,
    //                     @ptrCast(&region),
    //                 );
    //             },
    //             .transition => |cmd| {
    //                 std.debug.assert(cmd.texture.queue == cmd.dst_queue); // TODO

    //             },
    //             .barrier => |cmd| {
    //                 hazards
    //                     ._ = cmd;
    //             },
    //         }
    //     }

    //     // def generate_barrier(currentState, requiredStages, requiredAccesses):
    //     //     # 1. Determine if we are doing a Write
    //     //     isWrite = (requiredAccesses & VK_ACCESS_2_WRITE_BIT_MASK) != 0

    //     //     # 2. Check for hazards
    //     //     # We need a barrier if:
    //     //     # - There are pending writes (RAW or WAW)
    //     //     # - We are writing and there were previous reads (WAR)
    //     //     hasHazard = (currentState.pendingWriteAccesses != 0) or \
    //     //                 (isWrite and currentState.lastUsedStages != 0)

    //     //     if hasHazard:
    //     //         barrier = VkDependencyInfo(
    //     //             VkMemoryBarrier2(
    //     //                 srcStageMask  = currentState.lastUsedStages | currentState.pendingWriteStages,
    //     //                 srcAccessMask = currentState.pendingWriteAccesses,
    //     //                 dstStageMask  = requiredStages,
    //     //                 dstAccessMask = requiredAccesses
    //     //             )
    //     //         )

    //     //         # 3. Update State after a Barrier
    //     //         # Once a barrier is placed, the "pending" writes are now visible.
    //     //         currentState.pendingWriteStages = requiredStages if isWrite else 0
    //     //         currentState.pendingWriteAccesses = requiredAccesses if isWrite else 0
    //     //         currentState.lastUsedStages = requiredStages
    //     //         return barrier

    //     //     else:
    //     //         # No barrier needed, but update state for future WAR hazards
    //     //         currentState.lastUsedStages |= requiredStages
    //     //         if isWrite:
    //     //             currentState.pendingWriteAccesses |= requiredAccesses
    //     //             currentState.pendingWriteStages |= requiredStages
    //     //         return None

    //     command_buffer.buffer.clearRetainingCapacity();

    //     // always synchronize host at the end, s.t. when the semaphore is hit we can copy data out
    //     // i guess we could remove this if there were no operations downloading data
    //     const host_memory_barrier: vk.MemoryBarrier2 = .{
    //         .src_stage_mask = hazards.active_write_stages,
    //         .src_access_mask = hazards.active_write_accesses,
    //         .dst_stage_mask = .{ .host_bit = true },
    //         .dst_access_mask = .{ .host_read_bit = true },
    //     };
    //     ctx.device.cmdPipelineBarrier2(cmdbuf, &.{
    //         .p_memory_barriers = @ptrCast(&host_memory_barrier),
    //         .memory_barrier_count = 1,
    //     });

    //     try ctx.device.endCommandBuffer(cmdbuf);

    //     const semval = ctx.queue_semaphore_values.get(.graphics);
    //     ctx.queue_semaphore_values.set(.graphics, semval + 1);
    //     const timeline_semaphore_info: vk.TimelineSemaphoreSubmitInfo = .{
    //         .p_wait_semaphore_values = @ptrCast(&semval),
    //         .p_signal_semaphore_values = @ptrCast(&(semval + 1)),
    //         .signal_semaphore_value_count = 1,
    //         .wait_semaphore_value_count = 1,
    //     };
    //     const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .top_of_pipe_bit = true };
    //     const submit_info: vk.SubmitInfo = .{
    //         .command_buffer_count = 1,
    //         .p_command_buffers = @ptrCast(&cmdbuf),
    //         .wait_semaphore_count = 1,
    //         .p_wait_semaphores = @ptrCast(ctx.queue_semaphores.getPtr(command_buffer.queue_type)),
    //         .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
    //         .signal_semaphore_count = 1,
    //         .p_signal_semaphores = @ptrCast(ctx.queue_semaphores.getPtr(command_buffer.queue_type)),
    //         .p_next = &timeline_semaphore_info,
    //     };
    //     try ctx.queues.get(command_buffer.queue_type).submit(
    //         1,
    //         @ptrCast(&submit_info),
    //         .null_handle,
    //     );
    // }

    pub fn createBuffer(
        ctx: *Context,
        buffer_create_info: BufferCreateInfo,
    ) !*Buffer {
        const buffer = try ctx.buffer_pool.create();
        errdefer ctx.buffer_pool.destroy(buffer);
        buffer.* = try ctx.allocator.createBuffer(buffer_create_info);
        return buffer;
    }

    pub fn destroyBuffer(ctx: *Context, buffer: *Buffer) void {
        switch (buffer.memory) {
            .slab => |memory| {
                ctx.device.destroyBuffer(buffer.buffer, null);
                memory.slab.allocator.free(memory.allocation);
            },
            .dedicated => |memory| {
                ctx.device.destroyBuffer(buffer.buffer, null);
                ctx.device.freeMemory(memory, null);
            },
        }
        ctx.buffer_pool.destroy(buffer);
    }

    pub fn createTexture(
        ctx: *Context,
        texture_create_info: TextureCreateInfo,
    ) !*Texture {
        const texture = try ctx.texture_pool.create();
        errdefer ctx.texture_pool.destroy(texture);
        texture.* = try ctx.allocator.createTexture(texture_create_info);
        return texture;
    }

    pub fn destroyTexture(ctx: *Context, texture: *Texture) void {
        switch (texture.memory) {
            .slab => |memory| {
                ctx.device.destroyImageView(texture.default_view, null);
                ctx.device.destroyImage(texture.image, null);
                memory.slab.allocator.free(memory.allocation);
            },
            .dedicated => |memory| {
                ctx.device.destroyImageView(texture.default_view, null);
                ctx.device.destroyImage(texture.image, null);
                ctx.device.freeMemory(memory, null);
            },
        }
        ctx.texture_pool.destroy(texture);
    }

    pub fn createTransferBuffer(
        ctx: *Context,
        usage: TransferBuffer.Usage,
        size: usize,
    ) !*TransferBuffer {
        const buffer = try ctx.transfer_buffer_pool.create();
        errdefer ctx.transfer_buffer_pool.destroy(buffer);
        buffer.* = try .init(ctx, usage, size);
        return buffer;
    }

    pub fn destroyTransferBuffer(ctx: *Context, buffer: *TransferBuffer) void {
        buffer.deinit();
        ctx.transfer_buffer_pool.destroy(buffer);
    }

    pub fn createGraphicsPipeline(
        ctx: *Context,
        static_state: GraphicsPipeline.StaticState,
        dynamic_state: GraphicsPipeline.DynamicState,
    ) !*GraphicsPipeline {
        const pipeline = try ctx.graphics_pipeline_pool.create();
        errdefer ctx.graphics_pipeline_pool.destroy(pipeline);
        pipeline.* = try .init(ctx, static_state, dynamic_state);
        return pipeline;
    }

    pub fn destroyGraphicsPipeline(ctx: *Context, pipeline: *GraphicsPipeline) void {
        pipeline.deinit();
        ctx.graphics_pipeline_pool.destroy(pipeline);
    }

    pub fn createShader(
        ctx: *Context,
        shader_type: Shader.ShaderType,
        spv: []const u32,
    ) !*Shader {
        const shader = try ctx.shader_pool.create();
        errdefer ctx.shader_pool.destroy(shader);
        shader.* = .{
            .module = try ctx.device.createShaderModule(&.{
                .code_size = spv.len * 4,
                .p_code = @ptrCast(&spv[0]),
            }, null),
            .stage = switch (shader_type) {
                .vertex => .{ .vertex_bit = true },
                .fragment => .{ .fragment_bit = true },
                .compute => .{ .compute_bit = true },
            },
        };
        return shader;
    }

    pub fn destroyShader(
        ctx: *Context,
        shader: *Shader,
    ) void {
        ctx.device.destroyShaderModule(shader.module, null);
        ctx.shader_pool.destroy(shader);
    }

    pub fn wait(ctx: *Context, semaphore_value: u64) !void {
        _ = try ctx.device.waitSemaphores(&.{
            .semaphore_count = 1,
            .p_semaphores = @ptrCast(&ctx.queue_semaphore),
            .p_values = @ptrCast(&semaphore_value),
        }, 1_000_000_000);
    }

    fn initInstance(
        ctx: *Context,
        arena: std.mem.Allocator,
        platform: Platform,
        app_name: [:0]const u8,
    ) !void {
        const all_layers = if (enable_debug) layers ++ debug_layers else layers;
        const available_layers = try ctx.base.enumerateInstanceLayerPropertiesAlloc(arena);
        for (all_layers) |req| {
            const req_name = std.mem.sliceTo(req, 0);
            var supported = false;
            for (available_layers) |ava| {
                const ava_name = std.mem.sliceTo(&ava.layer_name, 0);
                if (!std.mem.eql(u8, req_name, ava_name)) continue;
                supported = true;
                break;
            }
            if (!supported) {
                log.err("Unsupported layer: {s}", .{req_name});
                return error.UnsupportedLayer;
            }
        }

        const platform_extensions = try platform.getRequiredInstanceExtensions();
        var all_extensions: std.ArrayList([*:0]const u8) = .empty;
        try all_extensions.appendSlice(arena, platform_extensions);
        outer: for (if (enable_debug)
            instance_extensions ++ debug_instance_extensions
        else
            instance_extensions) |ext1|
        {
            for (all_extensions.items) |ext2| if (std.mem.eql(
                u8,
                std.mem.sliceTo(ext1, 0),
                std.mem.sliceTo(ext2, 0),
            )) continue :outer;
            try all_extensions.append(arena, ext1);
        }
        const available_exts = try ctx.base.enumerateInstanceExtensionPropertiesAlloc(null, arena);
        for (all_extensions.items) |req| {
            const req_name = std.mem.sliceTo(req, 0);
            var supported = false;
            for (available_exts) |ava| {
                const ava_name = std.mem.sliceTo(&ava.extension_name, 0);
                if (!std.mem.eql(u8, req_name, ava_name)) continue;
                supported = true;
                break;
            }
            if (!supported) {
                log.err("Unsupported instance extension: {s}", .{req_name});
                return error.UnsupportedInstanceExtension;
            }
        }

        const available_versions = try ctx.base.enumerateInstanceVersion();
        if (available_versions < api_version) {
            log.err("Unsupported instance version: {}", .{api_version});
            return error.UnsupportedInstanceVersion;
        }

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = 0,
            .p_engine_name = app_name,
            .engine_version = 0,
            .api_version = api_version,
        };
        const create_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(all_layers.len),
            .pp_enabled_layer_names = &all_layers,
            .enabled_extension_count = @intCast(all_extensions.items.len),
            .pp_enabled_extension_names = all_extensions.items.ptr,
        };
        const instance_handle = try ctx.base.createInstance(&create_info, null);
        const vki = try ctx.gpa.create(vk.InstanceWrapper);
        errdefer ctx.gpa.destroy(vki);
        vki.* = .load(instance_handle, ctx.base.dispatch.vkGetInstanceProcAddr.?);
        ctx.instance = .init(instance_handle, vki);
    }

    fn deinitInstance(ctx: *Context) void {
        ctx.instance.destroyInstance(null);
        ctx.gpa.destroy(ctx.instance.wrapper);
    }

    fn createSurface(ctx: *Context, platform: Platform) !void {
        ctx.surface = try platform.createWindowSurface(ctx.instance.handle, platform.window);
    }

    fn destroySurface(ctx: *Context) void {
        ctx.instance.destroySurfaceKHR(ctx.surface, null);
        ctx.surface = .null_handle;
    }

    fn pickPhysicalDevice(ctx: *Context, arena: std.mem.Allocator) !PhysicalDeviceCandidate {
        const devices = try ctx.instance.enumeratePhysicalDevicesAlloc(arena);
        var candidates: std.ArrayList(PhysicalDeviceCandidate) =
            try .initCapacity(arena, devices.len);
        for (devices) |dev| {
            const candidate: PhysicalDeviceCandidate =
                try .init(arena, ctx.instance, ctx.surface, dev);
            const name = std.mem.sliceTo(&candidate.properties.device_name, 0);

            if (!try candidate.checkExtensionSupport(arena, ctx.instance)) {
                log.info("Did not pick {s}: Unsupported device extensions", .{name});
                continue;
            }

            if (!try candidate.checkFeatureSupport()) {
                log.info("Did not pick {s}: Unsupported device extensions", .{name});
                continue;
            }

            if (candidate.queue_family == null) {
                log.info("Did not pick {s}: No viable queue", .{name});
                continue;
            }

            candidates.appendAssumeCapacity(candidate);
        }

        if (candidates.items.len == 0) {
            log.err("No compatible physical device", .{});
            return error.NoCompatiblePhysicalDevice;
        }
        std.sort.insertion(
            PhysicalDeviceCandidate,
            candidates.items,
            {},
            PhysicalDeviceCandidate.cmp,
        );
        log.info(
            "Selected physical device: {s}",
            .{std.mem.sliceTo(&candidates.items[0].properties.device_name, 0)},
        );
        log.debug(
            "- queue family: {}",
            .{candidates.items[0].queue_family.?},
        );
        return candidates.items[0];
    }

    fn initDevice(
        ctx: *Context,
        candidate: PhysicalDeviceCandidate,
    ) !void {
        const queue_priority: f32 = 1.0;
        var queue_create_info: vk.DeviceQueueCreateInfo = .{
            .queue_family_index = candidate.queue_family.?,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&queue_priority),
        };

        const create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = 1,
            .p_queue_create_infos = @ptrCast(&queue_create_info),
            .p_enabled_features = &device_features,
            .enabled_extension_count = @intCast(device_extensions.len),
            .pp_enabled_extension_names = @ptrCast(&device_extensions),
            .p_next = &device_features_1_1,
        };

        const device_handle = try ctx.instance.createDevice(candidate.device, &create_info, null);
        const vkd = try ctx.gpa.create(vk.DeviceWrapper);
        errdefer ctx.gpa.destroy(vkd);
        vkd.* = .load(device_handle, ctx.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        ctx.device = .init(device_handle, vkd);

        ctx.queue_family = candidate.queue_family.?;
        ctx.queue = .init(
            ctx.device.getDeviceQueue(candidate.queue_family.?, 0),
            ctx.device.wrapper,
        );

        ctx.queue_semaphore_value = 0;
        ctx.queue_semaphore = try ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null);
        errdefer ctx.device.destroySemaphore(ctx.queue_semaphore, null);

        ctx.physical_device = candidate.device;
        ctx.physical_device_properties = candidate.properties;
        ctx.physical_device_memory_properties = candidate.memory_properties;
    }

    fn deinitDevice(ctx: *Context) void {
        ctx.device.destroySemaphore(ctx.queue_semaphore, null);
        ctx.device.destroyDevice(null);
        ctx.gpa.destroy(ctx.device.wrapper);
        ctx.physical_device = .null_handle;
    }

    fn initPipelineLayout(ctx: *Context) !void {
        const bindings: [3]vk.DescriptorSetLayoutBinding = .{ .{
            .binding = 0,
            .descriptor_type = .sampled_image,
            .descriptor_count = 1048576,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 1,
            .descriptor_type = .storage_image,
            .descriptor_count = 1048576,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 2,
            .descriptor_type = .sampler,
            .descriptor_count = 1048576,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        } };
        const binding_flags: [3]vk.DescriptorBindingFlags = .{ .{
            .update_after_bind_bit = true,
            .update_unused_while_pending_bit = true,
            .partially_bound_bit = true,
        }, .{
            .update_after_bind_bit = true,
            .update_unused_while_pending_bit = true,
            .partially_bound_bit = true,
        }, .{} };

        ctx.descriptor_set_layout = try ctx.device.createDescriptorSetLayout(&.{
            .binding_count = 3,
            .flags = .{ .update_after_bind_pool_bit = true },
            .p_bindings = @ptrCast(&bindings[0]),
            .p_next = &vk.DescriptorSetLayoutBindingFlagsCreateInfo{
                .binding_count = 3,
                .p_binding_flags = @ptrCast(&binding_flags[0]),
            },
        }, null);
        errdefer ctx.device.destroyDescriptorSetLayout(ctx.descriptor_set_layout, null);
        ctx.pipeline_layout = try ctx.device.createPipelineLayout(&.{
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&ctx.descriptor_set_layout),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&vk.PushConstantRange{
                .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
                .offset = 0,
                .size = 128,
            }),
        }, null);
        errdefer ctx.device.destroyPipelineLayout(ctx.pipeline_layout, null);
    }

    fn deinitPipelineLayout(ctx: *Context) void {
        ctx.device.destroyPipelineLayout(ctx.pipeline_layout, null);
        ctx.device.destroyDescriptorSetLayout(ctx.descriptor_set_layout, null);
    }
};

const PhysicalDeviceCandidate = struct {
    device: vk.PhysicalDevice,

    properties: vk.PhysicalDeviceProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    features: vk.PhysicalDeviceFeatures,
    features_1_1: vk.PhysicalDeviceVulkan11Features,
    features_1_2: vk.PhysicalDeviceVulkan12Features,
    features_1_3: vk.PhysicalDeviceVulkan13Features,

    queue_family: ?u32,

    fn init(
        arena: std.mem.Allocator,
        instance: vk.InstanceProxy,
        surface: vk.SurfaceKHR,
        dev: vk.PhysicalDevice,
    ) !PhysicalDeviceCandidate {
        var candidate = PhysicalDeviceCandidate{
            .device = dev,
            .properties = undefined,
            .memory_properties = instance.getPhysicalDeviceMemoryProperties(dev),
            .features = undefined,
            .features_1_1 = .{},
            .features_1_2 = .{},
            .features_1_3 = .{},
            .queue_family = null,
        };

        var properties2: vk.PhysicalDeviceProperties2 = .{ .properties = undefined };
        instance.getPhysicalDeviceProperties2(dev, &properties2);
        candidate.properties = properties2.properties;

        candidate.features_1_2.p_next = &candidate.features_1_3;
        candidate.features_1_1.p_next = &candidate.features_1_2;
        var features2: vk.PhysicalDeviceFeatures2 = .{
            .p_next = &candidate.features_1_1,
            .features = undefined,
        };
        instance.getPhysicalDeviceFeatures2(candidate.device, &features2);
        candidate.features = features2.features;
        candidate.features_1_1.p_next = null;
        candidate.features_1_2.p_next = null;
        candidate.features_1_3.p_next = null;

        // identify an everything queue (graphics supports compute and transfer implicitly)
        const queue_families =
            try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(dev, arena);
        for (queue_families, 0..) |family, i| {
            if (!family.queue_flags.graphics_bit) continue;
            if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                candidate.device,
                @intCast(i),
                surface,
            ) != .true) continue;
            candidate.queue_family = @intCast(i);
            break;
        }

        return candidate;
    }

    fn checkExtensionSupport(
        candidate: *const PhysicalDeviceCandidate,
        arena: std.mem.Allocator,
        instance: vk.InstanceProxy,
    ) !bool {
        const available_exts = try instance.enumerateDeviceExtensionPropertiesAlloc(
            candidate.device,
            null,
            arena,
        );

        for (if (enable_debug)
            device_extensions ++ debug_device_extensions
        else
            device_extensions) |req|
        {
            const req_name = std.mem.sliceTo(req, 0);
            var supported = false;

            for (available_exts) |ava| {
                const ava_name = std.mem.sliceTo(&ava.extension_name, 0);
                if (!std.mem.eql(u8, req_name, ava_name)) continue;
                supported = true;
                break;
            }

            if (!supported) {
                log.err("Unsupported instance extension: {s}", .{req_name});
                return false;
            }
        }
        return true;
    }

    fn checkFeatureSupport(candidate: *const PhysicalDeviceCandidate) !bool {
        inline for (std.meta.fields(vk.PhysicalDeviceFeatures)) |field| {
            if (field.type != vk.Bool32) continue;
            if (@field(device_features, field.name) == .false) continue;
            if (@field(candidate.features, field.name) == .false) return false;
        }
        inline for (std.meta.fields(vk.PhysicalDeviceVulkan11Features)) |field| {
            if (field.type != vk.Bool32) continue;
            if (@field(device_features_1_1, field.name) == .false) continue;
            if (@field(candidate.features_1_1, field.name) == .false) return false;
        }
        inline for (std.meta.fields(vk.PhysicalDeviceVulkan12Features)) |field| {
            if (field.type != vk.Bool32) continue;
            if (@field(device_features_1_2, field.name) == .false) continue;
            if (@field(candidate.features_1_2, field.name) == .false) return false;
        }
        inline for (std.meta.fields(vk.PhysicalDeviceVulkan13Features)) |field| {
            if (field.type != vk.Bool32) continue;
            if (@field(device_features_1_3, field.name) == .false) continue;
            if (@field(candidate.features_1_3, field.name) == .false) return false;
        }
        return true;
    }

    /// pick the discrete gpu with the most memory
    fn cmp(ctx: void, a: PhysicalDeviceCandidate, b: PhysicalDeviceCandidate) bool {
        _ = ctx;
        if (cmpDeviceType(a, b)) |result| return result;
        if (cmpMemory(a, b)) |result| return result;

        return true;
    }

    fn cmpDeviceType(a: PhysicalDeviceCandidate, b: PhysicalDeviceCandidate) ?bool {
        const dta: i32 = switch (a.properties.device_type) {
            .discrete_gpu => 2,
            .integrated_gpu, .virtual_gpu => 1,
            else => 0,
        };
        const dtb: i32 = switch (b.properties.device_type) {
            .discrete_gpu => 2,
            .integrated_gpu, .virtual_gpu => 1,
            else => 0,
        };
        if (dtb == dta) return null;
        return dta > dtb;
    }

    fn cmpMemory(a: PhysicalDeviceCandidate, b: PhysicalDeviceCandidate) ?bool {
        var ha: i64 = 0;
        for (a.memory_properties.memory_heaps[0..a.memory_properties.memory_heap_count]) |heap| {
            if (!heap.flags.device_local_bit) continue;
            ha += @intCast(heap.size);
        }
        var hb: i64 = 0;
        for (b.memory_properties.memory_heaps[0..b.memory_properties.memory_heap_count]) |heap| {
            if (!heap.flags.device_local_bit) continue;
            hb += @intCast(heap.size);
        }
        if (ha == hb) return null;
        return hb > ha;
    }
};

const Swapchain = struct {
    swapchain: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    views: []vk.ImageView,
    acquire_semaphores: []vk.Semaphore,
    release_semaphores: []vk.Semaphore,
    fences: []vk.Fence,

    fn init(ctx: *const Context, old_swapchain: vk.SwapchainKHR) !Swapchain {
        var arena_struct = std.heap.ArenaAllocator.init(ctx.gpa);
        defer _ = arena_struct.deinit();
        const arena = arena_struct.allocator();

        const capabilities = try ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            ctx.physical_device,
            ctx.surface,
        );
        const formats = try ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
            ctx.physical_device,
            ctx.surface,
            arena,
        );
        const present_modes = try ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
            ctx.physical_device,
            ctx.surface,
            arena,
        );

        log.debug("Creating swapchain", .{});
        const format = pickSwapchainFormat(
            ctx.swapchain_composition.getSwapchainSurfaceFormats(),
            formats,
        );
        log.debug("- format:       {} {}", .{ format.format, format.color_space });
        const present_mode = pickSwapchainPresentMode(&.{ctx.present_mode.vulkan()}, present_modes);
        log.debug("- present_mode: {}", .{present_mode});
        const extent = try getSwapchainExtent(ctx.platform, capabilities);
        log.debug("- extent:       {}", .{extent});
        const count = getSwapchainImageCount(capabilities);
        log.debug("- image count:  {}", .{count});

        if (extent.width == 0 and extent.height == 0) return error.minimized;

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = ctx.surface,
            .min_image_count = count,
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,
                .transfer_dst_bit = capabilities.supported_usage_flags.transfer_dst_bit,
            },
            .image_sharing_mode = .exclusive, // see below, might get set to concurrent
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = old_swapchain,
        };
        const swapchain = try ctx.device.createSwapchainKHR(&create_info, null);
        errdefer ctx.device.destroySwapchainKHR(swapchain, null);
        const swapchain_format = format;
        const swapchain_extent = extent;
        const swapchain_images = try ctx.device.getSwapchainImagesAllocKHR(swapchain, ctx.gpa);
        errdefer ctx.gpa.free(swapchain_images);

        const swapchain_views = try ctx.gpa.alloc(vk.ImageView, swapchain_images.len);
        errdefer ctx.gpa.free(swapchain_views);
        for (swapchain_images, 0..) |image, i| {
            const view_create_info = vk.ImageViewCreateInfo{
                .image = image,
                .view_type = .@"2d",
                .format = swapchain_format.format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };
            swapchain_views[i] = ctx.device.createImageView(&view_create_info, null) catch |e| {
                // cleanup pattern
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroyImageView(swapchain_views[j - 1], null);
                return e;
            };
        }

        const acquire_semaphores = try ctx.gpa.alloc(vk.Semaphore, swapchain_images.len);
        errdefer ctx.gpa.free(acquire_semaphores);
        for (0..swapchain_images.len) |i| {
            acquire_semaphores[i] = ctx.device.createSemaphore(&.{}, null) catch |e| {
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroySemaphore(acquire_semaphores[j - 1], null);
                return e;
            };
        }

        const release_semaphores = try ctx.gpa.alloc(vk.Semaphore, swapchain_images.len);
        errdefer ctx.gpa.free(release_semaphores);
        for (0..swapchain_images.len) |i| {
            release_semaphores[i] = ctx.device.createSemaphore(&.{}, null) catch |e| {
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroySemaphore(release_semaphores[j - 1], null);
                return e;
            };
        }

        const fences = try ctx.gpa.alloc(vk.Fence, swapchain_images.len);
        errdefer ctx.gpa.free(fences);
        for (0..swapchain_images.len) |i| {
            fences[i] = ctx.device.createFence(&.{
                .flags = .{ .signaled_bit = true }, // create signalled so we can use it right away
            }, null) catch |e| {
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroyFence(fences[j - 1], null);
                return e;
            };
        }

        return .{
            .swapchain = swapchain,
            .format = swapchain_format,
            .extent = swapchain_extent,
            .images = swapchain_images,
            .views = swapchain_views,
            .acquire_semaphores = acquire_semaphores,
            .release_semaphores = release_semaphores,
            .fences = fences,
        };
    }

    fn deinit(swapchain: *Swapchain, ctx: *const Context) void {
        // NOTE think about if we need to wait for all fences and semaphores
        for (swapchain.fences) |fence| ctx.device.destroyFence(fence, null);
        for (swapchain.acquire_semaphores) |semaphore| ctx.device.destroySemaphore(semaphore, null);
        for (swapchain.release_semaphores) |semaphore| ctx.device.destroySemaphore(semaphore, null);
        for (swapchain.views) |view| ctx.device.destroyImageView(view, null);
        ctx.gpa.free(swapchain.fences);
        ctx.gpa.free(swapchain.acquire_semaphores);
        ctx.gpa.free(swapchain.release_semaphores);
        ctx.gpa.free(swapchain.views);
        ctx.gpa.free(swapchain.images);
        ctx.device.destroySwapchainKHR(swapchain.swapchain, null);
        swapchain.* = undefined;
    }

    fn pickSwapchainFormat(
        requested_formats: []const vk.SurfaceFormatKHR,
        available_formats: []vk.SurfaceFormatKHR,
    ) vk.SurfaceFormatKHR {
        std.debug.assert(available_formats.len > 0);

        for (requested_formats) |req| {
            for (available_formats) |ava| {
                if (std.meta.eql(req, ava)) return req;
            }
        }

        log.warn("None of the requested swapchain surface formats were found", .{});
        return available_formats[0];
    }

    fn pickSwapchainPresentMode(
        requested_modes: []const vk.PresentModeKHR,
        available_modes: []vk.PresentModeKHR,
    ) vk.PresentModeKHR {
        for (requested_modes) |req| {
            for (available_modes) |ava| {
                if (req == ava) return req;
            }
        }
        return vk.PresentModeKHR.fifo_khr; // guaranteed support, should be fine not to check
    }

    fn getSwapchainExtent(
        platform: Platform,
        capabilities: vk.SurfaceCapabilitiesKHR,
    ) !vk.Extent2D {
        var extent = try platform.getFramebufferSize(platform.window);
        extent.width = std.math.clamp(
            extent.width,
            capabilities.min_image_extent.width,
            capabilities.max_image_extent.width,
        );
        extent.height = std.math.clamp(
            extent.height,
            capabilities.min_image_extent.height,
            capabilities.max_image_extent.height,
        );
        return extent;
    }

    fn getSwapchainImageCount(capabilities: vk.SurfaceCapabilitiesKHR) u32 {
        var count = capabilities.min_image_count + 1;
        if (capabilities.max_image_count > 0) count = @min(count, capabilities.max_image_count);
        return count;
    }
};

const Allocator = struct {
    const Slab = struct {
        const slab_size = 256 * 1024 * 1024;
        const granularity = 4096;

        memory_type_index: u32,
        flags: vk.MemoryAllocateFlags,

        allocator: OffsetAllocator,
        memory: vk.DeviceMemory,
        mapped_memory: ?[]u8,
    };

    ctx: *Context,
    slabs: std.ArrayList(Slab),

    fn init(ctx: *Context) !Allocator {
        return .{
            .ctx = ctx,
            .slabs = .empty,
        };
    }

    fn deinit(allocator: *Allocator) void {
        for (allocator.slabs.items) |*slab| {
            allocator.ctx.device.freeMemory(slab.memory, null);
            slab.allocator.deinit(allocator.ctx.gpa);
        }
        allocator.slabs.deinit(allocator.ctx.gpa);
        allocator.* = undefined;
    }

    fn createBuffer(
        allocator: *Allocator,
        buffer_create_info: BufferCreateInfo,
    ) !Buffer {
        const buffer_info = vk.BufferCreateInfo{
            .size = buffer_create_info.size,
            .usage = .{
                .transfer_src_bit = buffer_create_info.usage.transfer_src,
                .transfer_dst_bit = buffer_create_info.usage.transfer_dst,
                .storage_buffer_bit = buffer_create_info.usage.storage,
                .index_buffer_bit = buffer_create_info.usage.index,
                .indirect_buffer_bit = buffer_create_info.usage.indirect,
                .shader_device_address_bit = true,
            },
            .sharing_mode = .exclusive,
            .p_queue_family_indices = @ptrCast(&allocator.ctx.queue_family),
            .queue_family_index_count = 1,
        };
        const buffer = try allocator.ctx.device.createBuffer(&buffer_info, null);
        errdefer allocator.ctx.device.destroyBuffer(buffer, null);

        var dedicated_memreq: vk.MemoryDedicatedRequirements = .{
            .prefers_dedicated_allocation = .false,
            .requires_dedicated_allocation = .false,
        };
        var buffer_memreq: vk.MemoryRequirements2 = .{
            .p_next = &dedicated_memreq,
            .memory_requirements = undefined,
        };
        allocator.ctx.device.getBufferMemoryRequirements2(&.{
            .buffer = buffer,
        }, &buffer_memreq);

        std.debug.print("{}\n", .{buffer_memreq});
        std.debug.print("{}\n", .{dedicated_memreq});

        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999;

        const memory_types = allocator.ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = allocator.ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (buffer_memreq.memory_requirements.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local_bit) score += 2;
            if (memory_type.property_flags.host_visible_bit) score -= 1;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }

        if (dedicated_memreq.requires_dedicated_allocation == .true or
            buffer_memreq.memory_requirements.size > Slab.slab_size / 2)
        {
            // dedicated allocation
            const dedicated_info: vk.MemoryDedicatedAllocateInfo = .{
                .buffer = buffer,
            };
            const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
                .flags = .{ .device_address_bit = true },
                .device_mask = 0,
                .p_next = &dedicated_info,
            };
            const memory = try allocator.ctx.device.allocateMemory(&.{
                .allocation_size = buffer_memreq.memory_requirements.size,
                .memory_type_index = memory_type_index,
                .p_next = &alloc_flags,
            }, null);
            errdefer allocator.ctx.device.freeMemory(memory, null);
            try allocator.ctx.device.bindBufferMemory(buffer, memory, 0);

            const address = allocator.ctx.device.getBufferDeviceAddress(&.{
                .buffer = buffer,
            });

            return .{
                .memory = .{ .dedicated = memory },
                .buffer = buffer,
                .size = buffer_create_info.size,
                .buffer_device_address = address,
            };
        }

        // suballocate
        std.debug.assert(buffer_memreq.memory_requirements.alignment <= Slab.granularity);
        const suballoc = try allocator.alloc(
            memory_type_index,
            memory_types[memory_type_index].property_flags,
            .{ .device_address_bit = true },
            // buffer_create_info.size,
            buffer_memreq.memory_requirements.size,
        );

        try allocator.ctx.device.bindBufferMemory(
            buffer,
            suballoc.slab.memory,
            suballoc.allocation.offset,
        );

        const address = allocator.ctx.device.getBufferDeviceAddress(&.{
            .buffer = buffer,
        });

        return .{
            .memory = .{ .slab = .{
                .allocation = suballoc.allocation,
                .slab = suballoc.slab,
            } },
            .buffer = buffer,
            .size = buffer_create_info.size,
            .buffer_device_address = address,
        };
    }

    fn alloc(
        allocator: *Allocator,
        memory_type_index: u32,
        memory_property_flags: vk.MemoryPropertyFlags,
        flags: vk.MemoryAllocateFlags,
        size: u64,
    ) !struct {
        allocation: Allocation,
        slab: *Slab,
    } {
        const granule_size: u32 = @intCast(size / Slab.granularity);

        // ideally there should be some allocation policy where we try to match flags
        // and we try to allocate into the most full slab first (i think?)
        for (allocator.slabs.items) |*slab| {
            if (slab.memory_type_index != memory_type_index) continue;
            if (slab.flags.toInt() & flags.toInt() != flags.toInt()) continue;

            // slab is usable
            const allocation = slab.allocator.allocate(granule_size) catch continue;
            return .{
                .allocation = allocation,
                .slab = slab,
            };
        }

        // no allocation possible with extant slabs, make a new one
        const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
            .flags = flags,
            .device_mask = 0,
        };
        const memory = try allocator.ctx.device.allocateMemory(&.{
            .allocation_size = Slab.slab_size,
            .memory_type_index = memory_type_index,
            .p_next = &alloc_flags,
        }, null);
        errdefer allocator.ctx.device.freeMemory(memory, null);

        const slab = try allocator.slabs.addOne(allocator.ctx.gpa);
        errdefer _ = allocator.slabs.pop();
        slab.* = .{
            .memory_type_index = memory_type_index,
            .flags = flags,
            .memory = memory,
            .allocator = try .init(
                allocator.ctx.gpa,
                Slab.slab_size / Slab.granularity,
                Slab.slab_size / Slab.granularity,
            ),
            .mapped_memory = null,
        };

        if (memory_property_flags.host_visible_bit and
            memory_property_flags.host_coherent_bit)
            slab.mapped_memory = blk: {
                const ptr: [*]u8 = @ptrCast(allocator.ctx.device.mapMemory(
                    memory,
                    0,
                    Slab.slab_size,
                    .{},
                ) catch break :blk null);
                break :blk ptr[0..Slab.slab_size];
            };

        const allocation = try slab.allocator.allocate(granule_size);
        return .{
            .slab = slab,
            .allocation = allocation,
        };
    }

    fn createTexture(
        allocator: *Allocator,
        texture_create_info: TextureCreateInfo,
    ) !Texture {
        const multiformat: bool = blk: {
            const base_format = texture_create_info.format;
            for (texture_create_info.views) |view| {
                if (view.format) |format| {
                    if (format != base_format) break :blk true;
                }
            }
            break :blk false;
        };

        const arrayview: bool = blk: {
            if (texture_create_info.image_type != .image_3d) break :blk false;
            for (texture_create_info.views) |view| {
                if (view.view_type == .view_2d_array) break :blk true;
            }
            break :blk false;
        };

        const image_info: vk.ImageCreateInfo = .{
            .flags = .{
                .mutable_format_bit = multiformat,
                .cube_compatible_bit = texture_create_info.image_type == .image_cube or
                    texture_create_info.image_type == .image_cube_array,
                .@"2d_array_compatible_bit" = arrayview,
            },
            .image_type = texture_create_info.image_type.vulkanImageType(),
            .format = texture_create_info.format.vulkan(),
            .extent = .{
                .width = texture_create_info.size[0],
                .height = texture_create_info.size[1],
                .depth = if (texture_create_info.image_type == .image_3d)
                    texture_create_info.size[2]
                else
                    1,
            },
            .mip_levels = texture_create_info.mip_levels,
            .array_layers = if (texture_create_info.image_type == .image_3d)
                1
            else
                texture_create_info.size[2],
            .samples = texture_create_info.samples.vulkan(),
            .tiling = .optimal,
            .usage = .{
                .storage_bit = texture_create_info.usage.storage,
                .sampled_bit = texture_create_info.usage.sampled,
                .transfer_src_bit = texture_create_info.usage.transfer_src,
                .transfer_dst_bit = texture_create_info.usage.transfer_dst,
                .color_attachment_bit = texture_create_info.usage.color_attachment,
                .depth_stencil_attachment_bit = texture_create_info.usage.depth_stencil_attachment,
            },
            .sharing_mode = .exclusive,
            .p_queue_family_indices = @ptrCast(&allocator.ctx.queue_family),
            .queue_family_index_count = 1,
            .initial_layout = .undefined,
        };
        const image = try allocator.ctx.device.createImage(&image_info, null);
        errdefer allocator.ctx.device.destroyImage(image, null);

        var dedicated_memreq: vk.MemoryDedicatedRequirements = .{
            .prefers_dedicated_allocation = .false,
            .requires_dedicated_allocation = .false,
        };
        var image_memreq: vk.MemoryRequirements2 = .{
            .p_next = &dedicated_memreq,
            .memory_requirements = undefined,
        };
        allocator.ctx.device.getImageMemoryRequirements2(&.{
            .image = image,
        }, &image_memreq);

        std.debug.print("{}\n", .{image_memreq});
        std.debug.print("{}\n", .{dedicated_memreq});

        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999;

        const memory_types = allocator.ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = allocator.ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (image_memreq.memory_requirements.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local_bit) score += 1;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }

        var texture: Texture = undefined;
        texture.image = image;

        if (dedicated_memreq.requires_dedicated_allocation == .true or
            (dedicated_memreq.prefers_dedicated_allocation == .true and
                (texture_create_info.usage.color_attachment == true or
                    texture_create_info.usage.depth_stencil_attachment == true)) or
            image_memreq.memory_requirements.size > Slab.slab_size / 2)
        {
            // dedicated allocation
            const dedicated_info: vk.MemoryDedicatedAllocateInfo = .{
                .image = image,
            };
            const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
                .device_mask = 0,
                .p_next = &dedicated_info,
            };
            const memory = try allocator.ctx.device.allocateMemory(&.{
                .allocation_size = image_memreq.memory_requirements.size,
                .memory_type_index = memory_type_index,
                .p_next = &alloc_flags,
            }, null);
            errdefer allocator.ctx.device.freeMemory(memory, null);
            try allocator.ctx.device.bindImageMemory(image, memory, 0);

            texture.memory = .{ .dedicated = memory };
        } else {
            // suballocate
            const suballoc = try allocator.alloc(
                memory_type_index,
                memory_types[memory_type_index].property_flags,
                .{ .device_address_bit = true },
                if (image_memreq.memory_requirements.alignment <= Slab.granularity)
                    image_memreq.memory_requirements.size
                else
                    image_memreq.memory_requirements.size + image_memreq.memory_requirements.alignment,
            );

            try allocator.ctx.device.bindImageMemory(
                image,
                suballoc.slab.memory,
                std.mem.alignForward(
                    u32,
                    suballoc.allocation.offset,
                    @intCast(image_memreq.memory_requirements.alignment),
                ),
            );

            texture.memory = .{ .slab = .{
                .allocation = suballoc.allocation,
                .slab = suballoc.slab,
            } };
        }

        const default_view_info: vk.ImageViewCreateInfo = .{
            .image = image,
            .view_type = texture_create_info.image_type.vulkanImageViewType(),
            .format = texture_create_info.format.vulkan(),
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .base_mip_level = 0,
                .level_count = texture_create_info.mip_levels,
                .base_array_layer = 0,
                .layer_count = texture_create_info.size[2],
                .aspect_mask = switch (texture_create_info.format) {
                    .s8_uint => .{ .stencil_bit = true },
                    .d16_unorm,
                    .d16_unorm_s8_uint,
                    .d24_unorm_s8_uint,
                    .d32_sfloat,
                    .d32_sfloat_s8_uint,
                    => .{ .depth_bit = true },
                    else => .{ .color_bit = true },
                },
            },
        };
        const default_view = try allocator.ctx.device.createImageView(&default_view_info, null);
        errdefer allocator.ctx.device.destroyImageView(default_view, null);

        // TODO create the other views

        texture.default_view = default_view;
        texture.size = texture_create_info.size;
        texture.layout = .undefined;
        texture.format = texture_create_info.format;
        texture.mip_levels = texture_create_info.mip_levels;

        return texture;
    }
};

const GraphicsPipeline = struct {
    const StaticState = struct {
        const PolygonMode = enum {
            fill,
            line,
            point,

            fn vulkan(polygon_mode: PolygonMode) vk.PolygonMode {
                return switch (polygon_mode) {
                    .fill => .fill,
                    .line => .line,
                    .point => .point,
                };
            }
        };
        const MultisampleState = struct {
            sample_count: SampleCount = .@"1",
            enable_alpha_to_coverage: bool = false,
        };
        const ColorAttachment = struct {
            const ColorWriteMask = struct {
                r: bool = true,
                g: bool = true,
                b: bool = true,
                a: bool = true,

                fn vulkan(mask: ColorWriteMask) vk.ColorComponentFlags {
                    return .{
                        .r_bit = mask.r,
                        .g_bit = mask.g,
                        .b_bit = mask.b,
                        .a_bit = mask.a,
                    };
                }
            };

            const BlendState = struct {
                const BlendFactor = enum {
                    zero,
                    one,
                    src_color,
                    one_minus_src_color,
                    dst_color,
                    one_minus_dst_color,
                    src_alpha,
                    one_minus_src_alpha,
                    dst_alpha,
                    one_minus_dst_alpha,
                    constant_color,
                    one_minus_constant_color,
                    constant_alpha,
                    one_minus_constant_alpha,
                    src_alpha_saturate,

                    fn vulkan(blend_factor: BlendFactor) vk.BlendFactor {
                        return switch (blend_factor) {
                            .zero => .zero,
                            .one => .one,
                            .src_color => .src_color,
                            .one_minus_src_color => .one_minus_src_color,
                            .dst_color => .dst_color,
                            .one_minus_dst_color => .one_minus_dst_color,
                            .src_alpha => .src_alpha,
                            .one_minus_src_alpha => .one_minus_src_alpha,
                            .dst_alpha => .dst_alpha,
                            .one_minus_dst_alpha => .one_minus_dst_alpha,
                            .constant_color => .constant_color,
                            .one_minus_constant_color => .one_minus_constant_color,
                            .constant_alpha => .constant_alpha,
                            .one_minus_constant_alpha => .one_minus_constant_alpha,
                            .src_alpha_saturate => .src_alpha_saturate,
                        };
                    }
                };

                const BlendOp = enum {
                    add,
                    subtract,
                    reverse_subtract,
                    min,
                    max,

                    fn vulkan(blend_op: BlendOp) vk.BlendOp {
                        return switch (blend_op) {
                            .add => .add,
                            .subtract => .subtract,
                            .reverse_subtract => .reverse_subtract,
                            .min => .min,
                            .max => .max,
                        };
                    }
                };

                src_color_blend_factor: BlendFactor,
                dst_color_blend_factor: BlendFactor,
                color_blend_op: BlendOp,
                src_alpha_blend_factor: BlendFactor,
                dst_alpha_blend_factor: BlendFactor,
                alpha_blend_op: BlendOp,
            };

            format: Format,
            color_write_mask: ColorWriteMask = .{},
            blend_state: ?BlendState = null,
        };

        vertex_shader: *const Shader,
        fragment_shader: *const Shader,
        polygon_mode: PolygonMode = .fill,
        multisample: MultisampleState = .{},
        color_attachments: []const ColorAttachment = &.{},
        depth_attachment_format: ?Format = null,
        stencil_attachment_format: ?Format = null,
    };

    const DynamicState = struct {
        const Viewport = extern struct {
            x: f32 = 0.0,
            y: f32 = 0.0,
            width: f32,
            height: f32,
            min_depth: f32,
            max_depth: f32,

            fn vulkan(viewport: Viewport) vk.Viewport {
                return .{
                    .x = viewport.x,
                    .y = viewport.y,
                    .width = viewport.width,
                    .height = viewport.height,
                    .min_depth = viewport.min_depth,
                    .max_depth = viewport.max_depth,
                };
            }
        };
        const Scissor = extern struct {
            x: i32 = 0,
            y: i32 = 0,
            width: u32,
            height: u32,

            fn vulkan(scissor: Scissor) vk.Rect2D {
                return .{
                    .offset = .{ .x = scissor.x, .y = scissor.y },
                    .extent = .{ .width = scissor.width, .height = scissor.height },
                };
            }
        };
        const InputAssemblyState = struct {
            const PrimitiveTopology = enum {
                point_list,
                line_list,
                line_strip,
                triangle_list,
                triangle_strip,
                triangle_fan,

                fn vulkan(primitive_topology: PrimitiveTopology) vk.PrimitiveTopology {
                    return switch (primitive_topology) {
                        .point_list => .point_list,
                        .line_list => .line_list,
                        .line_strip => .line_strip,
                        .triangle_list => .triangle_list,
                        .triangle_strip => .triangle_strip,
                        .triangle_fan => .triangle_fan,
                    };
                }
            };
            primitive_topology: PrimitiveTopology = .triangle_list,
            enable_primitive_restart: bool = false,
        };
        const RasterizationState = struct {
            const CullMode = struct {
                front: bool = false,
                back: bool = true,

                fn vulkan(cull_mode: CullMode) vk.CullModeFlags {
                    return .{
                        .front_bit = cull_mode.front,
                        .back_bit = cull_mode.back,
                    };
                }
            };
            const FrontFace = enum {
                counter_clockwise,
                clockwise,

                fn vulkan(front_face: FrontFace) vk.FrontFace {
                    return switch (front_face) {
                        .counter_clockwise => .counter_clockwise,
                        .clockwise => .clockwise,
                    };
                }
            };
            const DepthBias = struct {
                constant_factor: f32,
                clamp: f32,
                slope_factor: f32,
            };

            enable_rasterizer_discard: bool = false,
            cull_mode: CullMode = .{},
            front_face: FrontFace = .counter_clockwise,
            depth_bias: ?DepthBias = null,
        };
        const DepthStencilState = struct {
            const CompareOp = enum {
                never,
                less,
                equal,
                less_or_equal,
                greater,
                not_equal,
                greater_or_equal,
                always,

                fn vulkan(compare_op: CompareOp) vk.CompareOp {
                    return switch (compare_op) {
                        .never => .never,
                        .less => .less,
                        .equal => .equal,
                        .less_or_equal => .less_or_equal,
                        .greater => .greater,
                        .not_equal => .not_equal,
                        .greater_or_equal => .greater_or_equal,
                        .always => .always,
                    };
                }
            };
            const StencilState = struct {
                const StencilOp = enum {
                    keep,
                    zero,
                    replace,
                    increment_and_clamp,
                    decrement_and_clamp,
                    invert,
                    increment_and_wrap,
                    decrement_and_wrap,

                    fn vulkan(stencil_op: StencilOp) vk.StencilOp {
                        return switch (stencil_op) {
                            .keep => .keep,
                            .zero => .zero,
                            .replace => .replace,
                            .increment_and_clamp => .increment_and_clamp,
                            .decrement_and_clamp => .decrement_and_clamp,
                            .invert => .invert,
                            .increment_and_wrap => .increment_and_wrap,
                            .decrement_and_wrap => .decrement_and_wrap,
                        };
                    }
                };
                const StencilOpState = struct {
                    fail_op: StencilOp,
                    pass_op: StencilOp,
                    depth_fail_op: StencilOp,
                    compare_op: CompareOp,
                    compare_mask: u32 = 0xFFFFFFFF,
                    write_mask: u32 = 0xFFFFFFFF,
                    reference: u32 = 0x00000000,

                    fn vulkan(stencil_op_state: StencilOpState) vk.StencilOpState {
                        return .{
                            .fail_op = stencil_op_state.fail_op.vulkan(),
                            .pass_op = stencil_op_state.pass_op.vulkan(),
                            .depth_fail_op = stencil_op_state.depth_fail_op.vulkan(),
                            .compare_op = stencil_op_state.compare_op.vulkan(),
                            .compare_mask = stencil_op_state.compare_mask,
                            .write_mask = stencil_op_state.write_mask,
                            .reference = stencil_op_state.reference,
                        };
                    }
                };

                front: StencilOpState,
                back: StencilOpState,
            };

            depth_test: ?CompareOp = .greater,
            enable_depth_write: bool = true,
            stencil_test: ?StencilState = null,
        };

        viewport: Viewport,
        scissor: Scissor,
        input_assembly: InputAssemblyState = .{},
        rasterization: RasterizationState = .{},
        depth_stencil: DepthStencilState = .{},
        blend_constants: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    ctx: *Context,
    dynamic_state: DynamicState,
    pipeline: vk.Pipeline,

    fn init(
        ctx: *Context,
        static_state: StaticState,
        dynamic_state: DynamicState,
    ) !GraphicsPipeline {
        const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ .{
            .stage = static_state.vertex_shader.stage,
            .module = static_state.vertex_shader.module,
            .p_name = "main",
        }, .{
            .stage = static_state.fragment_shader.stage,
            .module = static_state.fragment_shader.module,
            .p_name = "main",
        } };

        const dynamic_states = [_]vk.DynamicState{
            .viewport,
            .scissor,
            .depth_bias,
            .blend_constants,
            .depth_bounds,
            .stencil_compare_mask,
            .stencil_write_mask,
            .stencil_reference,
            .cull_mode,
            .front_face,
            .primitive_topology,
            .depth_test_enable,
            .depth_write_enable,
            .depth_compare_op,
            .depth_bounds_test_enable,
            .stencil_test_enable,
            .stencil_op,
            .rasterizer_discard_enable,
            .depth_bias_enable,
            .primitive_restart_enable,
        };

        // TODO probably better to have a reusable arena in Context
        var arena_impl: std.heap.ArenaAllocator = .init(ctx.gpa);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        const color_attachment_formats = try arena.alloc(
            vk.Format,
            static_state.color_attachments.len,
        );
        const color_blend_attachments = try arena.alloc(
            vk.PipelineColorBlendAttachmentState,
            static_state.color_attachments.len,
        );
        for (static_state.color_attachments, 0..) |color_attachment, i| {
            color_attachment_formats[i] = color_attachment.format.vulkan();
            var cba = std.mem.zeroes(vk.PipelineColorBlendAttachmentState);
            cba.color_write_mask = color_attachment.color_write_mask.vulkan();
            if (color_attachment.blend_state) |blend_state| {
                cba.blend_enable = .true;
                cba.src_color_blend_factor = blend_state.src_color_blend_factor.vulkan();
                cba.dst_color_blend_factor = blend_state.dst_color_blend_factor.vulkan();
                cba.color_blend_op = blend_state.color_blend_op.vulkan();
                cba.src_alpha_blend_factor = blend_state.src_alpha_blend_factor.vulkan();
                cba.dst_alpha_blend_factor = blend_state.dst_alpha_blend_factor.vulkan();
                cba.alpha_blend_op = blend_state.alpha_blend_op.vulkan();
            }
            color_blend_attachments[i] = cba;
        }

        const dynamic_rendering: vk.PipelineRenderingCreateInfo = .{
            .color_attachment_count = @intCast(color_attachment_formats.len),
            .p_color_attachment_formats = if (color_attachment_formats.len > 0) @ptrCast(&color_attachment_formats[0]) else null,
            .depth_attachment_format = if (static_state.depth_attachment_format) |format| format.vulkan() else .undefined,
            .stencil_attachment_format = if (static_state.stencil_attachment_format) |format| format.vulkan() else .undefined,
            .view_mask = 0, // multiview is not supported
        };

        const create_info: vk.GraphicsPipelineCreateInfo = .{
            .stage_count = @intCast(shader_stages.len),
            .p_stages = @ptrCast(&shader_stages[0]),
            .p_vertex_input_state = &.{}, // vertex buffers are not supported
            .p_input_assembly_state = &.{
                .topology = dynamic_state.input_assembly.primitive_topology.vulkan(),
                .primitive_restart_enable = if (dynamic_state.input_assembly.enable_primitive_restart) .true else .false,
            },
            .p_viewport_state = &.{
                .viewport_count = 1, // multiple viewports are not supported
                .p_viewports = @ptrCast(&.{
                    .x = dynamic_state.viewport.x,
                    .y = dynamic_state.viewport.y,
                    .width = dynamic_state.viewport.width,
                    .height = dynamic_state.viewport.height,
                    .min_depth = dynamic_state.viewport.min_depth,
                    .max_depth = dynamic_state.viewport.max_depth,
                }),
                .scissor_count = 1, // multiple viewports are not supported
                .p_scissors = @ptrCast(&.{
                    .offset = .{
                        .x = dynamic_state.scissor.x,
                        .y = dynamic_state.scissor.y,
                    },
                    .extent = .{
                        .width = dynamic_state.scissor.width,
                        .height = dynamic_state.scissor.height,
                    },
                }),
            },
            .p_rasterization_state = &.{
                .depth_clamp_enable = .false, // depth clamp not supported
                .rasterizer_discard_enable = if (dynamic_state.rasterization.enable_rasterizer_discard) .true else .false,
                .polygon_mode = static_state.polygon_mode.vulkan(),
                .line_width = 1.0,
                .cull_mode = dynamic_state.rasterization.cull_mode.vulkan(),
                .front_face = dynamic_state.rasterization.front_face.vulkan(),
                .depth_bias_enable = if (dynamic_state.rasterization.depth_bias != null) .true else .false,
                .depth_bias_constant_factor = if (dynamic_state.rasterization.depth_bias) |depth_bias| depth_bias.constant_factor else 0.0,
                .depth_bias_clamp = if (dynamic_state.rasterization.depth_bias) |depth_bias| depth_bias.clamp else 0.0,
                .depth_bias_slope_factor = if (dynamic_state.rasterization.depth_bias) |depth_bias| depth_bias.slope_factor else 0.0,
            },
            .p_multisample_state = &.{
                .rasterization_samples = static_state.multisample.sample_count.vulkan(),
                .sample_shading_enable = .false, // sample shading not supported
                .min_sample_shading = 1.0, // sample shading not supported
                .p_sample_mask = null, // sample mask not supported
                .alpha_to_coverage_enable = if (static_state.multisample.enable_alpha_to_coverage) .true else .false,
                .alpha_to_one_enable = .false, // alpha to one not supported
            },
            .p_depth_stencil_state = &.{
                .depth_test_enable = if (dynamic_state.depth_stencil.depth_test != null) .true else .false,
                .depth_write_enable = if (dynamic_state.depth_stencil.enable_depth_write) .true else .false,
                .depth_compare_op = if (dynamic_state.depth_stencil.depth_test) |compare_op| compare_op.vulkan() else .never,
                .depth_bounds_test_enable = .false, // depth boudns not supported
                .stencil_test_enable = if (dynamic_state.depth_stencil.stencil_test != null) .true else .false,
                .front = if (dynamic_state.depth_stencil.stencil_test) |stencil_test| stencil_test.front.vulkan() else std.mem.zeroes(vk.StencilOpState),
                .back = if (dynamic_state.depth_stencil.stencil_test) |stencil_test| stencil_test.back.vulkan() else std.mem.zeroes(vk.StencilOpState),
                .min_depth_bounds = 0.0, // depth boudns not supported
                .max_depth_bounds = 0.0, // depth boudns not supported
            },
            .p_color_blend_state = &.{
                .logic_op_enable = .false, // logic op is not supported
                .logic_op = .clear, // logic op is not supported
                .attachment_count = @intCast(color_blend_attachments.len),
                .p_attachments = if (color_blend_attachments.len > 0) @ptrCast(&color_blend_attachments[0]) else null,
                .blend_constants = dynamic_state.blend_constants,
            },
            .p_dynamic_state = &.{
                .dynamic_state_count = @intCast(dynamic_states.len),
                .p_dynamic_states = &dynamic_states,
            },
            .layout = ctx.pipeline_layout,
            .render_pass = .null_handle, // dynamic rendering
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
            .p_next = &dynamic_rendering,
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try ctx.device.createGraphicsPipelines(
            .null_handle,
            1,
            @ptrCast(&create_info),
            null,
            @ptrCast(&pipeline),
        );

        return .{
            .ctx = ctx,
            .dynamic_state = dynamic_state,
            .pipeline = pipeline,
        };
    }

    fn deinit(pipeline: *GraphicsPipeline) void {
        pipeline.ctx.device.destroyPipeline(pipeline.pipeline, null);
        pipeline.* = undefined;
    }
};

const ComputePipeline = struct {};

const TransferBuffer = struct {
    const Usage = enum { upload, download };

    ctx: *Context,

    memory: vk.DeviceMemory,
    buffer: vk.Buffer,
    mapped_memory: []u8,

    suballoc: std.heap.FixedBufferAllocator,

    fn init(ctx: *Context, usage: Usage, size: usize) !TransferBuffer {
        const buffer_info = vk.BufferCreateInfo{
            .size = size,
            .usage = .{
                .transfer_src_bit = usage == .upload,
                .transfer_dst_bit = usage == .download,
            },
            .sharing_mode = .exclusive,
            .p_queue_family_indices = @ptrCast(&ctx.queue_family),
            .queue_family_index_count = 1,
        };
        const buffer = try ctx.device.createBuffer(&buffer_info, null);
        errdefer ctx.device.destroyBuffer(buffer, null);

        const optimal_alignment = ctx.physical_device_properties.limits
            .optimal_buffer_copy_offset_alignment;
        var buffer_memreq = ctx.device.getBufferMemoryRequirements(buffer);
        buffer_memreq.alignment = @max(buffer_memreq.alignment, optimal_alignment);

        var memory_type_index: ?u32 = null;
        var best_score: i32 = -999;

        for (ctx.physical_device_memory_properties.memory_types[0..ctx.physical_device_memory_properties
            .memory_type_count], 0..) |memory_type, i|
        {
            // hard requirements
            if (buffer_memreq.memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (!memory_type.property_flags.host_visible_bit) continue;
            if (!memory_type.property_flags.host_coherent_bit) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local_bit) score -= 1;
            if (usage == .download and memory_type.property_flags.host_cached_bit) score += 2;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }

        // vulkan spec
        // There must be at least one memory type with both the
        // VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT and VK_MEMORY_PROPERTY_HOST_COHERENT_BIT bits
        // set in its propertyFlags
        // so this should always work
        std.debug.assert(memory_type_index != null);

        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = buffer_memreq.size,
            .memory_type_index = memory_type_index.?,
        };
        const memory = try ctx.device.allocateMemory(&alloc_info, null);
        errdefer ctx.device.freeMemory(memory, null);

        try ctx.device.bindBufferMemory(buffer, memory, 0);
        const buffer_ptr: [*]u8 = @ptrCast((try ctx.device.mapMemory(memory, 0, size, .{})).?);

        return .{
            .ctx = ctx,
            .memory = memory,
            .buffer = buffer,
            .mapped_memory = buffer_ptr[0..size],
            .suballoc = .init(buffer_ptr[0..size]),
        };
    }

    fn deinit(buffer: *TransferBuffer) void {
        buffer.ctx.device.destroyBuffer(buffer.buffer, null);
        buffer.ctx.device.freeMemory(buffer.memory, null);
        buffer.* = undefined;
    }

    pub fn allocator(buffer: *TransferBuffer) std.mem.Allocator {
        return buffer.suballoc.allocator();
    }

    pub fn reset(buffer: *TransferBuffer) void {
        buffer.suballoc.reset();
    }
};

const RenderingAttachment = struct {
    const LoadOp = enum {
        load,
        clear,
        dont_care,

        fn vulkan(load_op: LoadOp) vk.AttachmentLoadOp {
            return switch (load_op) {
                .load => .load,
                .clear => .clear,
                .dont_care => .dont_care,
            };
        }
    };
    const StoreOp = enum {
        store,
        dont_care,
        none,

        fn vulkan(store_op: StoreOp) vk.AttachmentStoreOp {
            return switch (store_op) {
                .store => .store,
                .dont_care => .dont_care,
                .none => .none,
            };
        }
    };
    const ClearValue = union(enum) {
        // probably more elegant to just let all these be optional, and assert that only one is set
        color: union(enum) {
            float: [4]f32,
            int: [4]i32,
            uint: [4]u32,
        },
        depth_stencil: struct {
            depth: f32,
            stencil: u32,
        },

        pub fn float(r: f32, g: f32, b: f32, a: f32) ClearValue {
            return .{ .color = .{ .float = .{ r, g, b, a } } };
        }
        pub fn int(r: i32, g: i32, b: i32, a: i32) ClearValue {
            return .{ .color = .{ .int = .{ r, g, b, a } } };
        }
        pub fn uint(r: u32, g: u32, b: u32, a: u32) ClearValue {
            return .{ .color = .{ .uint = .{ r, g, b, a } } };
        }
        pub fn depthStencil(depth: f32, stencil: u32) ClearValue {
            return .{ .depth_stencil = .{ .depth = depth, .stencil = stencil } };
        }

        fn vulkan(clear_value: ClearValue) vk.ClearValue {
            return switch (clear_value) {
                .color => |color| switch (color) {
                    .float => .{ .color = .{ .float_32 = color.float } },
                    .int => .{ .color = .{ .int_32 = color.int } },
                    .uint => .{ .color = .{ .uint_32 = color.uint } },
                },
                .depth_stencil => |depth_stencil| .{ .depth_stencil = .{
                    .depth = depth_stencil.depth,
                    .stencil = depth_stencil.stencil,
                } },
            };
        }
    };

    texture: *Texture,
    load_op: LoadOp,
    store_op: StoreOp,
    clear_value: ClearValue,
};

const StageFlags = struct {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,
    transfer: bool = false,
};

const AccessFlags = struct {
    storage: bool = false,
    attachment: bool = false,
    indirect: bool = false,
};

const LayoutTransition = struct {
    texture: *Texture,
    layout: ImageLayout,
    preserve_contents: bool,
};

const Command = union(enum) {
    buffer_upload: struct {
        size: u32,
        src_offset: u32,
        src_buffer: vk.Buffer,
        dst_buffer: vk.Buffer,
        dst_offset: u32,
    },
    barrier: struct {
        src_stages: StageFlags,
        dst_stages: StageFlags,
        access: AccessFlags,
        transitions: []const LayoutTransition = &.{},

        fn vulkanStageFlags(barrier: @This(), which: enum { src, dst }) vk.PipelineStageFlags2 {
            const stage_flags = switch (which) {
                .src => barrier.src_stages,
                .dst => barrier.dst_stages,
            };
            const access_flags = barrier.access;
            const vertex = stage_flags.vertex;
            const fragment = stage_flags.fragment;
            const compute = stage_flags.compute;
            const transfer = stage_flags.transfer;
            return .{
                .draw_indirect_bit = access_flags.indirect,
                .vertex_shader_bit = vertex,
                .fragment_shader_bit = fragment,
                .early_fragment_tests_bit = fragment,
                .late_fragment_tests_bit = fragment,
                .color_attachment_output_bit = fragment,
                .compute_shader_bit = compute,
                .all_transfer_bit = transfer,
                .index_input_bit = vertex,
            };
        }
        fn vulkanAccessFlags(barrier: @This()) vk.AccessFlags2 {
            const src_stage_flags = barrier.src_stages;
            const dst_stage_flags = barrier.dst_stages;
            const access_flags = barrier.access;
            const vertex = src_stage_flags.vertex or dst_stage_flags.vertex;
            const fragment = src_stage_flags.fragment or dst_stage_flags.fragment;
            const compute = src_stage_flags.compute or dst_stage_flags.compute;
            const transfer = src_stage_flags.transfer or dst_stage_flags.transfer;
            return .{
                .indirect_command_read_bit = access_flags.indirect,
                .index_read_bit = vertex and access_flags.storage,
                .shader_read_bit = (vertex or fragment or compute) and access_flags.storage,
                .shader_write_bit = (vertex or fragment or compute) and access_flags.storage,
                .color_attachment_read_bit = fragment and access_flags.attachment,
                .color_attachment_write_bit = fragment and access_flags.attachment,
                .depth_stencil_attachment_read_bit = fragment and access_flags.attachment,
                .depth_stencil_attachment_write_bit = fragment and access_flags.attachment,
                .transfer_read_bit = transfer and access_flags.storage,
                .transfer_write_bit = transfer and access_flags.storage,
            };
        }
    },
    begin_render_pass: struct {
        pipeline: *GraphicsPipeline,
        // color_attachments: []const vk.RenderingAttachmentInfo,
        // depth_attachment: ?*const vk.RenderingAttachmentInfo,
        // stencil_attachment: ?*const vk.RenderingAttachmentInfo,
        color_attachments: []const RenderingAttachment,
        depth_attachment: ?*const RenderingAttachment,
        stencil_attachment: ?*const RenderingAttachment,
        render_area_extent: vk.Extent2D,
    },
    end_render_pass: struct {},
    bind_index_buffer: struct {
        buffer: vk.Buffer,
        offset: u64,
    },
    draw_indexed_instanced: struct {
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    },
    push_constant: struct {
        size: u32,
        data: *const anyopaque,
    },
};

const CommandBuffer = struct {
    arena: std.mem.Allocator,
    commands: std.SegmentedList(Command, 64),

    fn init(arena: std.mem.Allocator) CommandBuffer {
        return .{
            .arena = arena,
            .commands = .{},
        };
    }

    pub fn barrier(
        buffer: *CommandBuffer,
        src_stage_flags: StageFlags,
        dst_stage_flags: StageFlags,
        access_flags: AccessFlags,
        transitions: []const LayoutTransition,
    ) !void {
        try buffer.commands.append(buffer.arena, .{ .barrier = .{
            .src_stages = src_stage_flags,
            .dst_stages = dst_stage_flags,
            .access = access_flags,
            .transitions = transitions,
        } });
    }

    pub fn uploadToBuffer(
        buffer: *CommandBuffer,
        src_buffer: *TransferBuffer,
        src_data: anytype,
        dst_buffer: *Buffer,
        dst_offset: u32,
    ) !void {
        const info = @typeInfo(@TypeOf(src_data));
        const addr: usize = switch (info.pointer.size) {
            .slice => @intFromPtr(src_data.ptr),
            else => @intFromPtr(src_data),
        };
        const len: usize = switch (info.pointer.size) {
            .slice => @sizeOf(info.pointer.child) * src_data.len,
            else => @sizeOf(info.pointer.child),
        };
        try buffer.commands.append(buffer.arena, .{ .buffer_upload = .{
            .size = @intCast(len),
            .src_offset = @intCast(addr - @intFromPtr(src_buffer.mapped_memory.ptr)),
            .src_buffer = src_buffer.buffer,
            .dst_offset = dst_offset,
            .dst_buffer = dst_buffer.buffer,
        } });
    }

    pub fn beginRenderPass(
        buffer: *CommandBuffer,
        pipeline: *GraphicsPipeline,
        color_attachments: []const RenderingAttachment,
        depth_attachment: ?*const RenderingAttachment,
        stencil_attachment: ?*const RenderingAttachment,
    ) !void {
        const size = if (depth_attachment) |info|
            info.texture.size
        else if (stencil_attachment) |info|
            info.texture.size
        else
            color_attachments[0].texture.size;

        try buffer.commands.append(buffer.arena, .{
            .begin_render_pass = .{
                .pipeline = pipeline,
                .color_attachments = color_attachments,
                .depth_attachment = depth_attachment,
                .stencil_attachment = stencil_attachment,
                .render_area_extent = .{ .width = size[0], .height = size[1] },
            },
        });
    }

    pub fn endRenderPass(buffer: *CommandBuffer) !void {
        try buffer.commands.append(buffer.arena, .{ .end_render_pass = .{} });
    }

    pub fn bindIndexBuffer(buffer: *CommandBuffer, index_buffer: *Buffer, offset: u64) !void {
        try buffer.commands.append(
            buffer.arena,
            .{ .bind_index_buffer = .{ .buffer = index_buffer.buffer, .offset = offset } },
        );
    }

    pub fn drawIndexedInstanced(
        buffer: *CommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) !void {
        try buffer.commands.append(buffer.arena, .{ .draw_indexed_instanced = .{
            .index_count = index_count,
            .instance_count = instance_count,
            .first_index = first_index,
            .vertex_offset = vertex_offset,
            .first_instance = first_instance,
        } });
    }

    pub fn pushConstant(buffer: *CommandBuffer, comptime T: type, value: T) !void {
        const data = try buffer.arena.create(T);
        data.* = value;
        try buffer.commands.append(buffer.arena, .{ .push_constant = .{
            .size = @intCast(@sizeOf(T)),
            .data = data,
        } });
    }
};
