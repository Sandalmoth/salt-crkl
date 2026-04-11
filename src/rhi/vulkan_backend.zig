const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");

const log = std.log.scoped(.rhi_vulkan);

const MemoryPool = std.heap.MemoryPool;

const enable_debug = @import("builtin").mode == .Debug;
const enable_validation = @import("builtin").mode == .Debug;

pub const PlatformError = error{Platform};
pub const Platform = struct {
    // TODO not sure what the best function signatures are here
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () PlatformError![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) PlatformError!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) PlatformError!vk.Extent2D,
};

pub const Config = struct {
    name: [:0]const u8,
    preferred_physical_device: ?[]const u8 = null,
    upload_staging_size: usize = 512 * 1024 * 1024,
    download_staging_size: usize = 128 * 1024 * 1024,
};

pub fn init(gpa: std.mem.Allocator, platform: Platform, config: Config) !rhi.Context {
    const ctx = try gpa.create(Context);
    ctx.* = try .init(gpa, platform, config);
    return .{
        .ptr = ctx,
        .vtable = &Context.vtable,
    };
}

pub fn deinit(ctx: rhi.Context) void {
    const vkctx: *Context = @ptrCast(@alignCast(ctx.ptr));
    const gpa = vkctx.gpa;
    vkctx.deinit();
    gpa.destroy(vkctx);
}

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
    .depth_bias_clamp = .true,
    .fragment_stores_and_atomics = .true,
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

const Queue = enum { graphics, compute, transfer, present };

const Shader = struct {
    public: rhi.Shader,
    stage: vk.ShaderStageFlags,
    module: vk.ShaderModule,
};

const GraphicsPipeline = struct {};

const ComputePipeline = struct {};

const Buffer = struct {
    public: rhi.Buffer,
    buffer: vk.Buffer,
    // memory: union(enum) {
    //     slab: struct {
    //         allocation: Allocation,
    //         slab: *Allocator.Slab,
    //     },
    //     dedicated: vk.DeviceMemory,
    // },
};

const Texture = struct {
    public: rhi.Texture,
    image: vk.Image,
};

const Sampler = struct {
    public: rhi.Sampler,
};

const Swapchain = struct {
    public: rhi.Swapchain,
    window: rhi.Window,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    images: []vk.Image,
    views: []vk.ImageView,
    release_semaphores: []vk.Semaphore,
    // composition: rhi.SwapchainComposition,
    // present_mode: rhi.PresentMode,
    // next: ?*Swapchain,
};

// NOTE i think we should bake the passes into here with just separate vtables
const CommandBuffer = struct {
    const command_buffer_vtable: rhi.CommandBuffer.VTable = .{
        .bufferUpload = undefined,
        .bufferDownload = undefined,
        .textureUpload = undefined,
        .textureDownload = undefined,
        .bufferCopy = undefined,
        .textureCopy = undefined,
        .blit = undefined,
        .resolve = undefined,
        .beginRenderPass = undefined,
        .endRenderPass = undefined,
        .beginComputePass = undefined,
        .endComputePass = undefined,
        .present = present,
        .timestamp = undefined,
    };

    ctx: *Context,
    queue: Queue,
    pool: vk.CommandPool,

    prefix: vk.CommandBuffer,
    body: vk.CommandBuffer,
    suffix: vk.CommandBuffer,

    // command buffer captures errors by just becoming invalid
    // and errors on submit instead, allowing for a try-free api
    valid: bool,

    fn init(ctx: *Context, queue: Queue) !CommandBuffer {
        const pool = ctx.device.createCommandPool(&.{
            .flags = .{},
            .queue_family_index = ctx.queues.get(queue).family,
        }, null) catch return error.Unknown;
        errdefer ctx.device.destroyCommandPool(pool, null);
        var buffers: [3]vk.CommandBuffer = .{.null_handle} ** 3;
        ctx.device.allocateCommandBuffers(&.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 3,
        }, @ptrCast(&buffers[0])) catch return error.Unknown;
        errdefer ctx.device.freeCommandBuffers(pool, 3, @ptrCast(&buffers[0]));

        return .{
            .ctx = ctx,
            .queue = queue,
            .pool = pool,
            .prefix = buffers[0],
            .body = buffers[1],
            .suffix = buffers[2],
            .valid = false,
        };
    }

    fn deinit(command_buffer: *CommandBuffer) void {
        const buffers: [3]vk.CommandBuffer = .{
            command_buffer.prefix,
            command_buffer.body,
            command_buffer.suffix,
        };
        command_buffer.ctx.device.freeCommandBuffers(command_buffer.pool, 3, @ptrCast(&buffers[0]));
        command_buffer.ctx.device.destroyCommandPool(command_buffer.pool, null);
    }

    fn reset(command_buffer: *CommandBuffer) void {
        command_buffer.valid = false;
        command_buffer.ctx.device.resetCommandPool(command_buffer.pool, .{}) catch return;
        command_buffer.valid = true;
    }

    fn present(ptr: *anyopaque, rhi_swapchain: *const rhi.Swapchain) void {
        const command_buffer: *CommandBuffer = @ptrCast(@alignCast(ptr));
        if (!command_buffer.valid) return;
        std.debug.assert(command_buffer.ctx.present_queue_initialized);

        _ = rhi_swapchain;
        std.debug.print("we presentin\n", .{});
    }
};

const Context = struct {
    const vtable: rhi.Context.VTable = .{
        .createSwapchain = createSwapchain,
        .destroySwapchain = destroySwapchain,
        .setSwapchainComposition = undefined,
        .setSwapchainPresentMode = undefined,
        .waitAndAcquireSwapchainTexture = waitAndAcquireSwapchainTexture,
        .recreateSwapchain = recreateSwapchain,
        .createBuffer = undefined,
        .createTexture = undefined,
        .createSampler = undefined,
        .createShader = undefined,
        .createGroup = undefined,
        .createGraphicsPipeline = undefined,
        .createComputePipeline = undefined,
        .destroyBuffer = undefined,
        .destroyTexture = undefined,
        .destroySampler = undefined,
        .destroyShader = undefined,
        .destroyGroup = undefined,
        .destroyGraphicsPipeline = undefined,
        .destroyComputePipeline = undefined,
        .stagingAllocator = undefined,
        .acquireCommandBuffer = acquireCommandBuffer,
        .submit = submit,
        .waitQueue = undefined,
        .waitFence = undefined,
        .testQueue = undefined,
        .testFence = undefined,
        .setBufferGroup = undefined,
        .setTextureGroup = undefined,
        .readTimestamp = undefined,
    };

    const PhysicalQueue = struct {
        queue: vk.QueueProxy,
        family: u32,
        semaphore: vk.Semaphore,
        value: u64,
    };

    gpa: std.mem.Allocator,
    platform: Platform,
    config: Config,

    base: vk.BaseWrapper,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,

    physical_device: vk.PhysicalDevice,
    physical_device_properties: vk.PhysicalDeviceProperties,
    physical_device_descriptor_indexing_properties: vk.PhysicalDeviceDescriptorIndexingProperties,
    physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set: vk.DescriptorSet,
    texture_view_slots: SlotPool,
    sampler_slots: SlotPool,

    // pools are for resources that are recreated, not reused
    swapchain_pool: MemoryPool(Swapchain),
    shader_pool: MemoryPool(Shader),
    graphics_pipeline_pool: MemoryPool(GraphicsPipeline),
    compute_pipeline_pool: MemoryPool(ComputePipeline),
    buffer_pool: MemoryPool(Buffer),
    texture_pool: MemoryPool(Texture),
    sampler_pool: MemoryPool(Sampler),

    // depots are for resources that are reused once available
    command_buffer_depots: std.EnumArray(Queue, Depot(*CommandBuffer)),
    image_acquire_semaphore_depot: Depot(vk.Semaphore),

    buffer_allocator: BufferAllocator,
    texture_allocator: TextureAllocator,
    upload_allocator: UploadAllocator,
    download_allocator: DownloadAllocator,

    queues: std.EnumArray(Queue, *PhysicalQueue),
    present_queue_initialized: bool,

    fn init(gpa: std.mem.Allocator, platform: Platform, config: Config) !Context {
        var arena_impl: std.heap.ArenaAllocator = .init(gpa);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        var ctx: Context = undefined;

        ctx.gpa = gpa;
        ctx.platform = platform;
        ctx.config = config;
        ctx.base = .load(platform.getInstanceProcAddress);

        try ctx.initInstance(arena, platform, config.name);
        errdefer ctx.deinitInstance();
        const physical_device_candidate = try ctx.pickPhysicalDevice(arena);
        try ctx.initDevice(arena, physical_device_candidate);
        errdefer ctx.deinitDevice();
        try ctx.initPipelineLayout();
        errdefer ctx.deinitPipelineLayout();

        ctx.shader_pool = .init(gpa);
        ctx.graphics_pipeline_pool = .init(gpa);
        ctx.compute_pipeline_pool = .init(gpa);
        ctx.buffer_pool = .init(gpa);
        ctx.texture_pool = .init(gpa);
        ctx.sampler_pool = .init(gpa);
        ctx.swapchain_pool = .init(gpa);

        ctx.command_buffer_depots = .initFill(.init(gpa));
        ctx.image_acquire_semaphore_depot = .init(gpa);

        // TODO init allocators

        return ctx;
    }

    fn deinit(ctx: *Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in deinit: {}", .{e});
        };

        ctx.swapchain_pool.deinit();
        ctx.shader_pool.deinit();
        ctx.graphics_pipeline_pool.deinit();
        ctx.compute_pipeline_pool.deinit();
        ctx.buffer_pool.deinit();
        ctx.texture_pool.deinit();
        ctx.sampler_pool.deinit();

        for ([_]Queue{ .graphics, .compute, .transfer, .present }) |queue| {
            const depot = ctx.command_buffer_depots.getPtr(queue);
            var it = depot.heap.iterator();
            while (it.next()) |item| {
                item.data.deinit();
                ctx.gpa.destroy(item.data);
            }
            depot.deinit();
        }

        var physical_queues: [4]?*PhysicalQueue = .{null} ** 4;
        outer: for ([_]Queue{ .graphics, .compute, .transfer }, 0..) |queue, j| {
            for (0..4) |i| if (physical_queues[i] == ctx.queues.get(queue)) continue :outer;
            physical_queues[j] = ctx.queues.get(queue);
        }
        if (ctx.present_queue_initialized) {
            for (0..4) |i| {
                if (physical_queues[i] == ctx.queues.get(.present)) break;
            } else {
                physical_queues[3] = ctx.queues.get(.present);
            }
        }
        for (physical_queues[0..4]) |q| {
            const queue = q orelse continue;
            ctx.device.destroySemaphore(queue.semaphore, null);
            ctx.gpa.destroy(queue);
        }

        ctx.deinitPipelineLayout();
        ctx.deinitDevice();
        ctx.deinitInstance();

        ctx.* = undefined;
    }

    fn createSwapchain(
        ptr: *anyopaque,
        window: rhi.Window,
    ) rhi.Context.Error!*const rhi.Swapchain {
        const ctx: *Context = @ptrCast(@alignCast(ptr));
        const swapchain: *Swapchain = try ctx.swapchain_pool.create();

        const surface = try ctx.platform.createWindowSurface(ctx.instance.handle, window);
        errdefer ctx.instance.destroySurfaceKHR(surface, null);

        if (!ctx.present_queue_initialized) {
            // first time we create a swapchain we need to find the present queue
            // ideally it should be the same as the graphics queue but could be different
            // it's done here because it requires a surface

            if ((ctx.instance.getPhysicalDeviceSurfaceSupportKHR(
                ctx.physical_device,
                ctx.queues.get(.graphics).family,
                surface,
            ) catch return error.Unknown) == .true) {
                ctx.queues.set(.present, ctx.queues.get(.graphics));
                ctx.present_queue_initialized = true;
            } else {
                // TODO search through all the queues to find one that can present
                log.warn("Graphics queue does not present, separate queue not yet implemented", .{});
                return error.Unsupported;
            }
        }

        // TODO init
        swapchain.* = Swapchain{
            // .next = null,
            .public = .{ .info = .{
                .composition = .sdr,
                .present_mode = .fifo,
                .size = .{ 0, 0, 0 },
            } },
            .surface = surface,
            .window = window,
            .swapchain = .null_handle,
            .images = &.{},
            .views = &.{},
            .release_semaphores = &.{},
        };
        return &swapchain.public;
    }

    fn destroySwapchain(ptr: *anyopaque, rhi_swapchain: *const rhi.Swapchain) void {
        const ctx: *Context = @ptrCast(@alignCast(ptr));
        const swapchain: *Swapchain = @alignCast(@constCast(
            @fieldParentPtr("public", rhi_swapchain),
        ));

        std.debug.assert(ctx.present_queue_initialized);

        if (swapchain.swapchain != .null_handle) {
            std.debug.print("{}\n", .{swapchain});
            const count = swapchain.images.len;
            for (0..count) |i| {
                ctx.device.destroySemaphore(swapchain.release_semaphores[i], null);
                ctx.device.destroyImageView(swapchain.views[i], null);
            }
            ctx.device.destroySwapchainKHR(swapchain.swapchain, null);
            ctx.gpa.free(swapchain.release_semaphores);
            ctx.gpa.free(swapchain.views);
            ctx.gpa.free(swapchain.images);
        }

        ctx.instance.destroySurfaceKHR(swapchain.surface, null);

        ctx.swapchain_pool.destroy(swapchain);
    }

    fn recreateSwapchain(
        ptr: *anyopaque,
        rhi_swapchain: *const rhi.Swapchain,
    ) rhi.Context.Error!void {
        const ctx: *Context = @ptrCast(@alignCast(ptr));
        const swapchain: *Swapchain = @alignCast(@constCast(
            @fieldParentPtr("public", rhi_swapchain),
        ));

        std.debug.assert(ctx.present_queue_initialized);

        ctx.device.deviceWaitIdle() catch return error.Unknown;

        var arena_impl = std.heap.ArenaAllocator.init(ctx.gpa);
        defer _ = arena_impl.deinit();
        const arena = arena_impl.allocator();

        // FIXME convert errors instead of passing unknown

        const capabilities = ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            ctx.physical_device,
            swapchain.surface,
        ) catch return error.Unknown;
        const formats = ctx.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
            ctx.physical_device,
            swapchain.surface,
            arena,
        ) catch return error.Unknown;
        const present_modes = ctx.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
            ctx.physical_device,
            swapchain.surface,
            arena,
        ) catch return error.Unknown;

        log.debug("(re)creating swapchain", .{});
        const format = pickSwapchainFormat(.sdr, formats) orelse formats[0];
        log.debug("- format:       {} {}", .{ format.format, format.color_space });
        const present_mode = pickSwapchainPresentMode(.fifo, present_modes) orelse .fifo_khr;
        log.debug("- present_mode: {}", .{present_mode});
        const extent = try getSwapchainExtent(ctx.platform, capabilities, swapchain.window);
        log.debug("- extent:       {}", .{extent});
        const count = getSwapchainImageCount(capabilities);
        log.debug("- image count:  {}", .{count});

        swapchain.public.info.size = .{ extent.width, extent.height, 1 };

        const old_swapchain = swapchain.swapchain;

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = swapchain.surface,
            .min_image_count = count,
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,
                .transfer_dst_bit = capabilities.supported_usage_flags.transfer_dst_bit,
            },
            .image_sharing_mode = .exclusive,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = old_swapchain,
        };
        // std.debug.print("{}\n", .{create_info});
        swapchain.swapchain = ctx.device.createSwapchainKHR(
            &create_info,
            null,
        ) catch return error.Unknown;
        errdefer ctx.device.destroySwapchainKHR(swapchain.swapchain, null);

        if (old_swapchain != .null_handle) {
            for (0..count) |i| {
                ctx.device.destroySemaphore(swapchain.release_semaphores[i], null);
                ctx.device.destroyImageView(swapchain.views[i], null);
            }
            ctx.device.destroySwapchainKHR(old_swapchain, null);
            ctx.gpa.free(swapchain.release_semaphores);
            ctx.gpa.free(swapchain.views);
            ctx.gpa.free(swapchain.images);
        }

        swapchain.images = ctx.device.getSwapchainImagesAllocKHR(
            swapchain.swapchain,
            ctx.gpa,
        ) catch return error.Unknown;
        errdefer ctx.gpa.free(swapchain.images);
        std.debug.assert(swapchain.images.len == count);

        swapchain.views = try ctx.gpa.alloc(vk.ImageView, count);
        errdefer ctx.gpa.free(swapchain.views);
        for (swapchain.images, 0..) |image, i| {
            const view_create_info = vk.ImageViewCreateInfo{
                .image = image,
                .view_type = .@"2d",
                .format = format.format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };
            swapchain.views[i] = ctx.device.createImageView(&view_create_info, null) catch {
                // cleanup pattern
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroyImageView(swapchain.views[j - 1], null);
                return error.Unknown;
            };
        }

        swapchain.release_semaphores = try ctx.gpa.alloc(vk.Semaphore, count);
        errdefer ctx.gpa.free(swapchain.release_semaphores);
        for (0..count) |i| {
            swapchain.release_semaphores[i] = ctx.device.createSemaphore(&.{}, null) catch {
                var j = i;
                while (j > 0) : (j -= 1) ctx.device.destroySemaphore(swapchain.release_semaphores[j - 1], null);
                return error.Unknown;
            };
        }

        // FIXME FIXME if we fail at any point here we'll get a very hard to recover state
        // we should probably first put the swapchain struct in some safe state
        // and then only overwrite it if everything succeeds
    }

    fn waitAndAcquireSwapchainTexture(
        ptr: *anyopaque,
        rhi_swapchain: *const rhi.Swapchain,
    ) rhi.Context.Error!*const rhi.Texture {
        const ctx: *Context = @ptrCast(@alignCast(ptr));
        const swapchain: *Swapchain = @alignCast(@constCast(
            @fieldParentPtr("public", rhi_swapchain),
        ));

        std.debug.assert(ctx.present_queue_initialized);

        if (swapchain.swapchain == .null_handle) return error.OutOfDate;

        std.debug.print("waiting for texture\n", .{});
        return undefined;
    }

    fn acquireCommandBuffer(
        ptr: *anyopaque,
        rhi_queue: rhi.Queue,
    ) rhi.Context.Error!rhi.CommandBuffer {
        const ctx: *Context = @ptrCast(@alignCast(ptr));
        const queue: Queue = switch (rhi_queue) {
            .graphics => .graphics,
            .compute => .compute,
            .transfer => .transfer,
        };

        const semaphore_value = ctx.device.getSemaphoreCounterValue(
            ctx.queues.get(queue).semaphore,
        ) catch return error.Unknown;
        const command_buffer = ctx.command_buffer_depots.getPtr(queue).pop(semaphore_value) orelse blk: {
            const command_buffer = try ctx.gpa.create(CommandBuffer);
            errdefer ctx.gpa.destroy(command_buffer);
            command_buffer.* = try .init(ctx, queue);
            break :blk command_buffer;
        };
        command_buffer.reset();

        std.debug.print("yo\n", .{});
        return .{
            .ptr = command_buffer,
            .vtable = &CommandBuffer.command_buffer_vtable,
        };
    }

    fn submit(
        ptr: *anyopaque,
        rhi_command_buffers: []const rhi.CommandBuffer,
    ) rhi.Context.Error!rhi.Fence {
        const ctx: *Context = @ptrCast(@alignCast(ptr));

        std.debug.print("dawg\n", .{});

        for (rhi_command_buffers) |rhi_command_buffer| {
            // FIXME use real semaphore value
            const command_buffer: *CommandBuffer = @ptrCast(@alignCast(rhi_command_buffer.ptr));
            try (ctx.command_buffer_depots.getPtr(command_buffer.queue)).push(command_buffer, 0);
        }

        return undefined;
    }

    fn initInstance(
        ctx: *Context,
        arena: std.mem.Allocator,
        platform: Platform,
        app_name: [:0]const u8,
    ) !void {
        const all_layers = if (enable_validation) layers ++ debug_layers else layers;
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
        outer: for (if (enable_validation)
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
    fn pickPhysicalDevice(
        ctx: *Context,
        arena: std.mem.Allocator,
    ) !PhysicalDeviceCandidate {
        const devices = try ctx.instance.enumeratePhysicalDevicesAlloc(arena);
        var candidates: std.ArrayList(PhysicalDeviceCandidate) =
            try .initCapacity(arena, devices.len);
        for (devices) |dev| {
            const candidate: PhysicalDeviceCandidate =
                try .init(arena, ctx.instance, dev);
            const name = std.mem.sliceTo(&candidate.properties.device_name, 0);

            if (!try candidate.checkExtensionSupport(arena, ctx.instance)) {
                log.info("Did not pick {s}: Unsupported device extensions", .{name});
                continue;
            }

            if (!try candidate.checkFeatureSupport()) {
                log.info("Did not pick {s}: Unsupported device extensions", .{name});
                continue;
            }

            if (!candidate.queue_families.contains(.graphics)) {
                log.info("Did not pick {s}: No graphics queue", .{name});
                continue;
            }

            std.debug.assert(candidate.queue_families.contains(.graphics));
            std.debug.assert(candidate.queue_families.contains(.compute));
            std.debug.assert(candidate.queue_families.contains(.transfer));

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
            "- graphics queue family: {}",
            .{
                candidates.items[0].queue_families.getAssertContains(.graphics),
            },
        );
        log.debug(
            "- compute queue family: {}",
            .{
                candidates.items[0].queue_families.getAssertContains(.compute),
            },
        );
        log.debug(
            "- transfer queue family: {}",
            .{
                candidates.items[0].queue_families.getAssertContains(.transfer),
            },
        );
        return candidates.items[0];
    }

    fn initDevice(
        ctx: *Context,
        arena: std.mem.Allocator,
        candidate: PhysicalDeviceCandidate,
    ) !void {
        var queue_create_infos: std.AutoArrayHashMapUnmanaged(u32, vk.DeviceQueueCreateInfo) =
            .empty;
        try queue_create_infos.ensureTotalCapacity(arena, 3);
        const priority: f32 = 1.0;
        for ([3]Queue{ .graphics, .compute, .transfer }) |queue| {
            const queue_family_index = candidate.queue_families.getAssertContains(queue);
            queue_create_infos.putAssumeCapacity(queue_family_index, .{
                .queue_family_index = queue_family_index,
                .queue_count = 1,
                .p_queue_priorities = @ptrCast(&priority),
            });
        }
        const create_info = vk.DeviceCreateInfo{
            .queue_create_info_count = @intCast(queue_create_infos.count()),
            .p_queue_create_infos = queue_create_infos.values().ptr,
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

        // for each unique queue, create the physical queue
        for (queue_create_infos.keys()) |queue_family_index| {
            const physical_queue = try ctx.gpa.create(PhysicalQueue);
            physical_queue.family = queue_family_index;
            physical_queue.queue = .init(
                ctx.device.getDeviceQueue(queue_family_index, 0),
                ctx.device.wrapper,
            );
            physical_queue.value = 0;
            physical_queue.semaphore = try ctx.device.createSemaphore(&.{
                .p_next = &vk.SemaphoreTypeCreateInfo{
                    .semaphore_type = .timeline,
                    .initial_value = 0,
                },
            }, null);

            // then assign it to all queues that share that family
            for ([3]Queue{ .graphics, .compute, .transfer }) |queue| {
                if (candidate.queue_families.getAssertContains(queue) == queue_family_index) {
                    ctx.queues.set(queue, physical_queue);
                }
            }
        }
        // present gets done when we create the first swapchain
        ctx.present_queue_initialized = false;

        ctx.physical_device = candidate.device;
        ctx.physical_device_properties = candidate.properties;
        ctx.physical_device_descriptor_indexing_properties = candidate.descriptor_indexing_properties;
        ctx.physical_device_memory_properties = candidate.memory_properties;
    }

    fn deinitDevice(ctx: *Context) void {
        ctx.device.destroyDevice(null);
        ctx.gpa.destroy(ctx.device.wrapper);
        ctx.physical_device = .null_handle;
    }

    fn initPipelineLayout(ctx: *Context) !void {
        // TODO we should maybe check the limits just in case and limit further if broken
        // however, these are within the minimum required, so safe if the driver is compliant
        const bindings: [3]vk.DescriptorSetLayoutBinding = .{ .{
            .binding = 0,
            .descriptor_type = .sampled_image,
            .descriptor_count = 128 * 1024,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 1,
            .descriptor_type = .storage_image,
            .descriptor_count = 128 * 1024,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 2,
            .descriptor_type = .sampler,
            .descriptor_count = 1024,
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
        }, .{
            .update_after_bind_bit = true,
            .update_unused_while_pending_bit = true,
            .partially_bound_bit = true,
        } };

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

        const pool_sizes = [3]vk.DescriptorPoolSize{
            .{ .type = .sampled_image, .descriptor_count = 128 * 1024 },
            .{ .type = .storage_image, .descriptor_count = 128 * 1024 },
            .{ .type = .sampler, .descriptor_count = 1024 },
        };
        ctx.descriptor_pool = try ctx.device.createDescriptorPool(&.{
            .flags = .{ .update_after_bind_bit = true },
            .max_sets = 1,
            .pool_size_count = @intCast(pool_sizes.len),
            .p_pool_sizes = &pool_sizes,
        }, null);
        errdefer ctx.device.destroyDescriptorPool(ctx.descriptor_pool, null);

        ctx.descriptor_set = .null_handle;
        try ctx.device.allocateDescriptorSets(&.{
            .descriptor_pool = ctx.descriptor_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(&ctx.descriptor_set_layout),
        }, @ptrCast(&ctx.descriptor_set));

        ctx.texture_view_slots = try .init(ctx.gpa, 128 * 1024);
        ctx.sampler_slots = try .init(ctx.gpa, 1024);
    }

    fn deinitPipelineLayout(ctx: *Context) void {
        ctx.sampler_slots.deinit(ctx.gpa);
        ctx.texture_view_slots.deinit(ctx.gpa);
        // NOTE freeing the pool frees the set
        ctx.device.destroyDescriptorPool(ctx.descriptor_pool, null);
        ctx.device.destroyPipelineLayout(ctx.pipeline_layout, null);
        ctx.device.destroyDescriptorSetLayout(ctx.descriptor_set_layout, null);
    }
};

fn pickSwapchainFormat(
    swapchain_composition: rhi.SwapchainComposition,
    available_formats: []vk.SurfaceFormatKHR,
) ?vk.SurfaceFormatKHR {
    std.debug.assert(available_formats.len > 0);

    const requested_formats: []const vk.SurfaceFormatKHR = switch (swapchain_composition) {
        .sdr => &.{
            .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr },
            .{ .format = .r8g8b8a8_srgb, .color_space = .srgb_nonlinear_khr },
        },
    };

    for (requested_formats) |req| {
        for (available_formats) |ava| {
            if (std.meta.eql(req, ava)) return req;
        }
    }

    log.warn("None of the requested swapchain surface formats were found", .{});
    return null;
}

fn pickSwapchainPresentMode(
    present_mode: rhi.PresentMode,
    available_modes: []vk.PresentModeKHR,
) ?vk.PresentModeKHR {
    const requested_mode: vk.PresentModeKHR = switch (present_mode) {
        .fifo => .fifo_khr,
        .mailbox => .mailbox_khr,
    };

    for (available_modes) |ava| {
        if (requested_mode == ava) return requested_mode;
    }
    return null;
}

fn getSwapchainExtent(
    platform: Platform,
    capabilities: vk.SurfaceCapabilitiesKHR,
    window: rhi.Window,
) !vk.Extent2D {
    if (capabilities.current_extent.width != 0xFFFFFFFF and
        capabilities.current_extent.height != 0xFFFFFFFF)
    {
        return capabilities.current_extent;
    }
    var extent = try platform.getFramebufferSize(window);
    if (extent.width == 0 and extent.height == 0) return error.Minimized;
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
    var count = @max(capabilities.min_image_count, 2); // avoid having any extras, minimize delays
    if (capabilities.max_image_count > 0) count = @min(count, capabilities.max_image_count);
    return count;
}

const PhysicalDeviceCandidate = struct {
    device: vk.PhysicalDevice,

    properties: vk.PhysicalDeviceProperties,
    descriptor_indexing_properties: vk.PhysicalDeviceDescriptorIndexingProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    features: vk.PhysicalDeviceFeatures,
    features_1_1: vk.PhysicalDeviceVulkan11Features,
    features_1_2: vk.PhysicalDeviceVulkan12Features,
    features_1_3: vk.PhysicalDeviceVulkan13Features,

    queue_families: std.EnumMap(Queue, u32),

    fn init(
        arena: std.mem.Allocator,
        instance: vk.InstanceProxy,
        dev: vk.PhysicalDevice,
    ) !PhysicalDeviceCandidate {
        var candidate = PhysicalDeviceCandidate{
            .device = dev,
            .properties = undefined,
            .descriptor_indexing_properties = undefined,
            .memory_properties = instance.getPhysicalDeviceMemoryProperties(dev),
            .features = undefined,
            .features_1_1 = .{},
            .features_1_2 = .{},
            .features_1_3 = .{},
            .queue_families = .{},
        };

        var descriptor_indexing_properties: vk.PhysicalDeviceDescriptorIndexingProperties = undefined;
        descriptor_indexing_properties.s_type = .physical_device_descriptor_indexing_properties;
        descriptor_indexing_properties.p_next = null;
        var properties2: vk.PhysicalDeviceProperties2 = .{
            .p_next = &descriptor_indexing_properties,
            .properties = undefined,
        };
        instance.getPhysicalDeviceProperties2(dev, &properties2);
        candidate.properties = properties2.properties;
        candidate.descriptor_indexing_properties = descriptor_indexing_properties;

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

        // graphics queue must support graphics (and compute and transfer)
        // compute should preferably be compute-only queue (and transfer)
        //   otherwise same as graphics
        // transfer should preferably be transfer-only queue,
        //   otherwise same as compute
        // present queue should preferably be same as graphics but cannot be selected
        // until after we have created the swapchain (should be pretty safe i think)
        const queue_families =
            try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(dev, arena);
        for (queue_families, 0..) |family, i| {
            if (family.queue_flags.graphics_bit) continue;
            if (family.queue_flags.compute_bit) continue;
            if (!family.queue_flags.transfer_bit) continue;
            candidate.queue_families.put(.transfer, @intCast(i));
            break;
        }
        for (queue_families, 0..) |family, i| {
            if (family.queue_flags.graphics_bit) continue;
            if (!family.queue_flags.compute_bit) continue;
            candidate.queue_families.put(.compute, @intCast(i));
            break;
        }
        for (queue_families, 0..) |family, i| {
            if (!family.queue_flags.graphics_bit) continue;
            candidate.queue_families.put(.graphics, @intCast(i));
            break;
        }

        if (candidate.queue_families.get(.compute)) |compute_queue_family| {
            if (!candidate.queue_families.contains(.transfer)) {
                candidate.queue_families.put(.transfer, compute_queue_family);
            }
        }

        if (candidate.queue_families.get(.graphics)) |graphics_queue_family| {
            if (!candidate.queue_families.contains(.compute)) {
                candidate.queue_families.put(.compute, graphics_queue_family);
            }
            if (!candidate.queue_families.contains(.transfer)) {
                candidate.queue_families.put(.transfer, graphics_queue_family);
            }
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

        for (if (enable_validation)
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

const BufferAllocator = struct {};

const TextureAllocator = struct {};

const UploadAllocator = struct {};

const DownloadAllocator = struct {};

fn Depot(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            data: T,
            semaphore_value: u64,

            fn order(_: void, a: Node, b: Node) std.math.Order {
                return std.math.order(a.semaphore_value, b.semaphore_value);
            }
        };

        heap: std.PriorityQueue(Node, void, Node.order),

        fn init(gpa: std.mem.Allocator) Self {
            return .{
                .heap = .init(gpa, {}),
            };
        }

        fn deinit(depot: *Self) void {
            depot.heap.deinit();
            depot.* = undefined;
        }

        fn push(depot: *Self, data: T, semaphore_value: u64) !void {
            try depot.heap.add(.{ .data = data, .semaphore_value = semaphore_value });
        }

        fn pop(depot: *Self, semaphore_value: u64) ?T {
            const top = depot.heap.peek() orelse return null;
            if (top.semaphore_value > semaphore_value) return null;
            return depot.heap.remove().data;
        }
    };
}

const SlotPool = struct {
    top: u32,
    slots: []u32,

    fn init(gpa: std.mem.Allocator, capacity: u32) !SlotPool {
        const slots = try gpa.alloc(u32, capacity);
        for (0..capacity) |i| slots[i] = @intCast(i);
        return .{ .top = capacity, .slots = slots };
    }

    fn deinit(pool: *SlotPool, gpa: std.mem.Allocator) void {
        if (pool.top != @as(u32, @intCast(pool.slots.len))) log.debug(
            "SlotPool not empty on deinit expected {} actual {}",
            .{ pool.slots.len, pool.top },
        );
        gpa.free(pool.slots);
        pool.* = undefined;
    }

    fn acquire(pool: *SlotPool) !u32 {
        if (pool.top == 0) return error.OutOfSlots;
        pool.top -= 1;
        return pool.slots[pool.top];
    }

    fn release(pool: *SlotPool, slot: u32) void {
        std.debug.assert(pool.top < @as(u32, @intCast(pool.slots.len)));
        pool.slots[pool.top] = slot;
        pool.top += 1;
    }
};
