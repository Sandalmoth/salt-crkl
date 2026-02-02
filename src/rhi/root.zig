const std = @import("std");
pub const vk = @import("vulkan");

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
    .timeline_semaphore = .true,
};
const device_features_1_3 = vk.PhysicalDeviceVulkan13Features{
    .dynamic_rendering = .true,
    .synchronization_2 = .true,
    .maintenance_4 = .true,
};

const frames_in_flight = 2;

const Platform = struct {
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () anyerror![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) anyerror!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) anyerror!vk.Extent2D,
    window: *anyopaque,
};

/// settings may be updated dynamically and will be automatically applied
const Settings = struct {
    swapchain_surface_formats: []const vk.SurfaceFormatKHR = &.{
        // ranking of preferred formats for the swapchain surfaces
        // if none are present, the first format from getPhysicalDeviceSurfaceFormats is used
        .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr },
        .{ .format = .r8g8b8a8_srgb, .color_space = .srgb_nonlinear_khr },
        .{ .format = .a8b8g8r8_srgb_pack32, .color_space = .srgb_nonlinear_khr },
    },
    swapchain_present_modes: []const vk.PresentModeKHR = &.{
        // ranking of preferred formats for the swapchain surfaces
        // if none are present, .fifo_khr is used
    },
};

pub const QueueType = enum {
    graphics,
    async_compute,
    transfer,
    present,
};

pub const CommandPool = struct {
    ctx: *const Context,
    pool: vk.CommandPool,

    buffers: std.ArrayList(vk.CommandBuffer),
    n_used: u32,

    pub fn init(ctx: *const Context, queue: QueueType) !CommandPool {
        return .{
            .ctx = ctx,
            .pool = try ctx.device.createCommandPool(&.{
                .flags = .{},
                .queue_family_index = ctx.queue_families.get(queue),
            }, null),
            .buffers = .empty,
            .n_used = 0,
        };
    }

    pub fn deinit(pool: *CommandPool) void {
        pool.ctx.device.destroyCommandPool(pool.pool, null);
        pool.buffers.deinit(pool.ctx.gpa);
        pool.* = undefined;
    }

    pub fn getTransientCommandBuffer(pool: *CommandPool) !vk.CommandBuffer {
        var command_buffer: vk.CommandBuffer = .null_handle;

        if (pool.n_used == pool.buffers.items.len) {
            try pool.buffers.ensureUnusedCapacity(pool.ctx.gpa, 1);
            try pool.ctx.device.allocateCommandBuffers(&.{
                .command_pool = pool.pool,
                .level = .primary,
                .command_buffer_count = 1,
            }, @ptrCast(&command_buffer));
            pool.buffers.appendAssumeCapacity(command_buffer);
            pool.n_used += 1;
        } else {
            command_buffer = pool.buffers.items[pool.n_used];
            pool.n_used += 1;
        }

        try pool.ctx.device.beginCommandBuffer(command_buffer, &.{
            .flags = .{ .one_time_submit_bit = true },
        });

        return command_buffer;
    }

    /// reset the command pool
    /// invalidates all allocated transient command buffers handles
    pub fn reset(pool: *CommandPool) void {
        pool.ctx.device.resetCommandPool(pool.pool, .{});
        pool.n_used = 0;
    }
};

pub const Context = struct {
    gpa: std.mem.Allocator,
    platform: Platform,
    settings: Settings,

    base: vk.BaseWrapper,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,

    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,

    queues: std.EnumArray(QueueType, vk.QueueProxy),
    queue_families: std.EnumArray(QueueType, u32),
    queue_semaphores: std.EnumArray(QueueType, vk.Semaphore),

    command_buffers: std.EnumArray(QueueType, CommandBuffer),
    active_command_buffer: ?QueueType,

    swapchain: Swapchain,
    old_swapchains: std.ArrayList(Swapchain),

    samplers: [1]vk.Sampler,
    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,

    allocator: Allocator,

    pub fn create(
        gpa: std.mem.Allocator,
        platform: Platform,
        settings: Settings,
        app_name: [:0]const u8,
    ) !*Context {
        const ctx = try gpa.create(Context);

        var arena_struct: std.heap.ArenaAllocator = .init(gpa);
        defer arena_struct.deinit();
        const arena = arena_struct.allocator();

        ctx.gpa = gpa;
        ctx.platform = platform;
        ctx.settings = settings;
        ctx.base = .load(platform.getInstanceProcAddress);

        try ctx.initInstance(arena, platform, app_name);
        errdefer ctx.deinitInstance();
        try ctx.createSurface(platform);
        errdefer ctx.destroySurface();
        const physical_device_candidate = try ctx.pickPhysicalDevice(arena);
        try ctx.initDevice(arena, physical_device_candidate);
        errdefer ctx.deinitDevice();
        ctx.old_swapchains = .empty;
        // QUESTION what if the window starts out minimized?
        // currently that means context creation fails
        ctx.swapchain = try .init(ctx, .null_handle);
        errdefer ctx.swapchain.deinit(ctx);

        try ctx.initPipelineLayout();
        errdefer ctx.deinitPipelineLayout();
        ctx.allocator = try .init(ctx, physical_device_candidate.memory_properties);

        ctx.command_buffers.set(.graphics, .init(ctx, .graphics));
        ctx.command_buffers.set(.async_compute, .init(ctx, .async_compute));
        ctx.command_buffers.set(.transfer, .init(ctx, .transfer));
        ctx.command_buffers.set(.present, .init(ctx, .present));
        ctx.active_command_buffer = null;

        return ctx;
    }

    pub fn destroy(ctx: *Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in vulkan_context deinit: {}", .{e});
        };

        ctx.deinitPipelineLayout();

        for (ctx.old_swapchains.items) |*swapchain| swapchain.deinit(ctx);
        ctx.old_swapchains.deinit(ctx.gpa);
        ctx.swapchain.deinit(ctx);
        ctx.deinitDevice();
        ctx.destroySurface();
        ctx.deinitInstance();

        ctx.gpa.destroy(ctx);
    }

    pub fn acquireCommandBuffer(ctx: *Context, queue_type: QueueType) *CommandBuffer {
        std.debug.assert(ctx.active_command_buffer == null);
        ctx.active_command_buffer = queue_type;
        return ctx.command_buffers.getPtr(queue_type);
    }

    pub fn submitCommandBuffer(ctx: *Context, command_buffer: *CommandBuffer) !void {
        std.debug.assert(ctx.active_command_buffer == command_buffer.queue_type);
        ctx.active_command_buffer = null;
        for (command_buffer.buffer.items) |command| {
            switch (command) {
                .begin_render_pass => {},
                .end_render_pass => {},
            }
        }
        command_buffer.buffer.clearRetainingCapacity();
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

            if (candidate.graphics_queue_family == null) {
                log.info("Did not pick {s}: No graphics queue", .{name});
                continue;
            }
            if (candidate.present_queue_family == null) {
                log.info("Did not pick {s}: No present queue", .{name});
                continue;
            }

            std.debug.assert(candidate.async_compute_queue_family != null);
            std.debug.assert(candidate.transfer_queue_family != null);

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
            "- Graphics queue family: {}",
            .{candidates.items[0].graphics_queue_family.?},
        );
        log.debug(
            "- Async compute queue family: {}",
            .{candidates.items[0].async_compute_queue_family.?},
        );
        log.debug("- Transfer queue family: {}", .{candidates.items[0].transfer_queue_family.?});
        log.debug("- Present queue family: {}", .{candidates.items[0].present_queue_family.?});
        return candidates.items[0];
    }

    fn initDevice(
        ctx: *Context,
        arena: std.mem.Allocator,
        candidate: PhysicalDeviceCandidate,
    ) !void {
        var queue_create_infos: std.AutoArrayHashMapUnmanaged(u32, vk.DeviceQueueCreateInfo) =
            .empty;
        try queue_create_infos.ensureTotalCapacity(arena, 4);
        const priority: f32 = 1.0;
        queue_create_infos.putAssumeCapacity(candidate.graphics_queue_family.?, .{
            .queue_family_index = candidate.graphics_queue_family.?,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&priority),
        });
        queue_create_infos.putAssumeCapacity(candidate.async_compute_queue_family.?, .{
            .queue_family_index = candidate.async_compute_queue_family.?,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&priority),
        });
        queue_create_infos.putAssumeCapacity(candidate.transfer_queue_family.?, .{
            .queue_family_index = candidate.transfer_queue_family.?,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&priority),
        });
        queue_create_infos.putAssumeCapacity(candidate.present_queue_family.?, .{
            .queue_family_index = candidate.present_queue_family.?,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&priority),
        });

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

        ctx.queue_families.set(.graphics, candidate.graphics_queue_family.?);
        ctx.queues.set(.graphics, .init(
            ctx.device.getDeviceQueue(candidate.graphics_queue_family.?, 0),
            ctx.device.wrapper,
        ));
        ctx.queue_families.set(.async_compute, candidate.async_compute_queue_family.?);
        ctx.queues.set(.async_compute, .init(
            ctx.device.getDeviceQueue(candidate.async_compute_queue_family.?, 0),
            ctx.device.wrapper,
        ));
        ctx.queue_families.set(.transfer, candidate.transfer_queue_family.?);
        ctx.queues.set(.transfer, .init(
            ctx.device.getDeviceQueue(candidate.transfer_queue_family.?, 0),
            ctx.device.wrapper,
        ));
        ctx.queue_families.set(.present, candidate.present_queue_family.?);
        ctx.queues.set(.present, .init(
            ctx.device.getDeviceQueue(candidate.graphics_queue_family.?, 0),
            ctx.device.wrapper,
        ));

        ctx.queue_semaphores.set(.graphics, try ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null));
        errdefer ctx.device.destroySemaphore(ctx.queue_semaphores.get(.graphics), null);
        ctx.queue_semaphores.set(.async_compute, try ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null));
        errdefer ctx.device.destroySemaphore(ctx.queue_semaphores.get(.async_compute), null);
        ctx.queue_semaphores.set(.transfer, try ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null));
        errdefer ctx.device.destroySemaphore(ctx.queue_semaphores.get(.transfer), null);
        ctx.queue_semaphores.set(.present, .null_handle);

        ctx.physical_device = candidate.device;
    }

    fn deinitDevice(ctx: *Context) void {
        ctx.device.destroySemaphore(ctx.queue_semaphores.get(.graphics), null);
        ctx.device.destroySemaphore(ctx.queue_semaphores.get(.async_compute), null);
        ctx.device.destroySemaphore(ctx.queue_semaphores.get(.transfer), null);
        ctx.device.destroyDevice(null);
        ctx.gpa.destroy(ctx.device.wrapper);
        ctx.physical_device = .null_handle;
    }

    fn initPipelineLayout(ctx: *Context) !void {
        ctx.samplers[0] = try ctx.device.createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
            .mipmap_mode = .nearest,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .mip_lod_bias = 0.0,
            .anisotropy_enable = .false,
            .max_anisotropy = 0.0,
            .compare_enable = .false,
            .compare_op = .never,
            .min_lod = 0.0,
            .max_lod = vk.LOD_CLAMP_NONE,
            .border_color = .float_transparent_black,
            .unnormalized_coordinates = .false,
        }, null);
        errdefer ctx.device.destroySampler(ctx.samplers[0], null);

        const bindings: [3]vk.DescriptorSetLayoutBinding = .{ .{
            .binding = 0,
            .descriptor_type = .sampled_image,
            .descriptor_count = 65536,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 1,
            .descriptor_type = .storage_image,
            .descriptor_count = 65536,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
        }, .{
            .binding = 2,
            .descriptor_type = .sampler,
            .descriptor_count = ctx.samplers.len,
            .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
            .p_immutable_samplers = @ptrCast(&ctx.samplers[0]),
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
        for (ctx.samplers) |sampler| ctx.device.destroySampler(sampler, null);
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

    graphics_queue_family: ?u32,
    async_compute_queue_family: ?u32,
    transfer_queue_family: ?u32,
    present_queue_family: ?u32,

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
            .graphics_queue_family = null,
            .async_compute_queue_family = null,
            .transfer_queue_family = null,
            .present_queue_family = null,
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

        // graphics queue must support graphics (and compute and transfer)
        // async compute should preferably be compute-only queue (and transfer)
        //   otherwise same as graphics
        // transfer should preferably be transfer-only queue,
        //   otherwise same as graphics
        // present queue should preferably be same as graphics
        const queue_families =
            try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(dev, arena);
        for (queue_families, 0..) |family, i| {
            if (family.queue_flags.graphics_bit) continue;
            if (family.queue_flags.compute_bit) continue;
            if (!family.queue_flags.transfer_bit) continue;
            candidate.transfer_queue_family = @intCast(i);
            break;
        }
        for (queue_families, 0..) |family, i| {
            if (family.queue_flags.graphics_bit) continue;
            if (!family.queue_flags.compute_bit) continue;
            candidate.async_compute_queue_family = @intCast(i);
            break;
        }
        for (queue_families, 0..) |family, i| {
            if (!family.queue_flags.graphics_bit) continue;
            if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                candidate.device,
                @intCast(i),
                surface,
            ) != .true) continue;
            candidate.graphics_queue_family = @intCast(i);
            candidate.present_queue_family = @intCast(i);
        }
        if (candidate.graphics_queue_family == null) {
            for (queue_families, 0..) |family, i| {
                if (!family.queue_flags.graphics_bit) continue;
                candidate.graphics_queue_family = @intCast(i);
            }
        }
        if (candidate.present_queue_family == null) {
            for (queue_families, 0..) |_, i| {
                if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                    candidate.device,
                    @intCast(i),
                    surface,
                ) != .true) continue;
                candidate.present_queue_family = @intCast(i);
            }
        }
        if (candidate.async_compute_queue_family == null) {
            candidate.async_compute_queue_family = candidate.graphics_queue_family;
        }
        if (candidate.transfer_queue_family == null) {
            candidate.transfer_queue_family = candidate.graphics_queue_family;
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
        const format = pickSwapchainFormat(ctx.settings, formats);
        log.debug("- format:       {} {}", .{ format.format, format.color_space });
        const present_mode = pickSwapchainPresentMode(ctx.settings, present_modes);
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
        var queue_families: std.AutoArrayHashMapUnmanaged(u32, void) = .empty;
        try queue_families.ensureTotalCapacity(arena, 2);
        queue_families.putAssumeCapacity(ctx.queue_families.get(.graphics), {});
        queue_families.putAssumeCapacity(ctx.queue_families.get(.present), {});
        if (queue_families.count() > 1) {
            create_info.image_sharing_mode = .concurrent;
            create_info.queue_family_index_count = @intCast(queue_families.count());
            create_info.p_queue_family_indices = queue_families.keys().ptr;
        }
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
            // NOTE do we want to create it signalled ?
            fences[i] = ctx.device.createFence(&.{
                .flags = .{ .signaled_bit = true },
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
        settings: Settings,
        formats: []vk.SurfaceFormatKHR,
    ) vk.SurfaceFormatKHR {
        std.debug.assert(formats.len > 0);

        for (settings.swapchain_surface_formats) |req| {
            for (formats) |ava| {
                if (std.meta.eql(req, ava)) return req;
            }
        }

        log.warn("None of the requested swapchain surface formats were found", .{});
        return formats[0];
    }

    fn pickSwapchainPresentMode(
        settings: Settings,
        modes: []vk.PresentModeKHR,
    ) vk.PresentModeKHR {
        for (settings.swapchain_present_modes) |req| {
            for (modes) |ava| {
                if (req == ava) return req;
            }
        }
        return vk.PresentModeKHR.fifo_khr; // guaranteed support, should be fine not to check
    }

    fn getSwapchainExtent(platform: Platform, capabilities: vk.SurfaceCapabilitiesKHR) !vk.Extent2D {
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
    physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

    fn init(
        ctx: *Context,
        physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
    ) !Allocator {
        // NOTE just some scrap code to see what allocations look like
        const testimg_extent = vk.Extent3D{ .width = 128, .height = 128, .depth = 1 };
        const testimg_image_create_info = vk.ImageCreateInfo{
            .image_type = .@"2d",
            // .format = .r8_unorm,
            .format = .bc1_rgba_srgb_block,
            .extent = testimg_extent,
            .usage = .{
                .transfer_dst_bit = true,
                .sampled_bit = true,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 1,
            .p_queue_family_indices = @ptrCast(&ctx.queue_families.get(.graphics)),
            .initial_layout = .undefined,
        };
        const testimg = try ctx.device.createImage(&testimg_image_create_info, null);
        defer ctx.device.destroyImage(testimg, null);
        const testimg_memreq = ctx.device.getImageMemoryRequirements(testimg);
        const testimg_alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = testimg_memreq.size,
            .memory_type_index = try findMemoryType(
                testimg_memreq.memory_type_bits,
                .{ .device_local_bit = true },
                physical_device_memory_properties,
            ),
        };
        std.debug.print("{}\n", .{testimg_memreq});
        std.debug.print("{}\n", .{testimg_alloc_info});
        const testimg_memory = try ctx.device.allocateMemory(&testimg_alloc_info, null);
        defer ctx.device.freeMemory(testimg_memory, null);

        return undefined;
    }

    fn findMemoryType(
        memory_type_bits: u32,
        property_flags: vk.MemoryPropertyFlags,
        physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
    ) !u32 {
        for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
            .memory_type_count], 0..) |memory_type, i|
        {
            // i don't really get this first check?
            // the index of the memory type holds some special meaning?
            // or is the memory type bits from the test memory requirements correlated to the device
            // such that it basically already knows what memory types it would work with?
            if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (property_flags.toInt() & memory_type.property_flags.toInt() !=
                property_flags.toInt()) continue;
            std.debug.print("{}\n", .{memory_type});
            return @intCast(i);
        }
        return error.MemoryTypeNotFound;
    }
};

const DynamicSubAllocator = struct {
    const granularity = 4 * 1024;
    const nil = std.math.maxInt(u32);

    const Meta = struct {
        seed: u32,
        size: u32,
        left: u32,
        right: u32,
    };

    slab_capacity: u64,
    slab_alignment: u64,
    metadata: []Meta,
    bins: [36]u32,

    fn init(gpa: std.mem.Allocator, capacity: u64, alignment: u64) !DynamicSubAllocator {
        std.debug.assert(capacity % granularity == 0);
        std.debug.assert(capacity <= granularity * std.math.maxInt(u32));
        var alloc: DynamicSubAllocator = .{
            .slab_capacity = capacity,
            .slab_alignment = alignment,
            .metadata = try gpa.alloc(Meta, capacity / granularity),
            .bins = .{nil} ** 36,
        };
        alloc.metadata[0] = .{
            .size = capacity / granularity,
            .next = 0,
            .prev = 0,
        };
        alloc.bins[binIndex(capacity)] = 0;
        return alloc;
    }

    fn binIndex(size: u64) u32 {
        const log2: u32 = @intCast(std.math.log2_int(u64, size));
        return if (log2 < 12) 0 else log2 - 12;
    }
};

const ArenaSubAllocator = struct {};

const Command = union(enum) {
    begin_render_pass: struct {},
    end_render_pass: struct {},
};

// TODO
// a nicer structure would be where you acquire a pool
// then you can fetch buffers from that which can be used on separate threads
// then you submit the buffers to the pool
// and then you submit the pool for execution
// the data should be packed instead of stored as an array of unions

pub const CommandBuffer = struct {
    ctx: *Context,
    queue_type: QueueType,
    buffer: std.ArrayList(Command),

    fn init(ctx: *Context, queue_type: QueueType) CommandBuffer {
        return .{ .ctx = ctx, .queue_type = queue_type, .buffer = .empty };
    }

    pub fn beginRenderPass(buffer: *CommandBuffer) !void {
        try buffer.buffer.append(buffer.ctx.gpa, .{
            .begin_render_pass = .{},
        });
    }

    pub fn endRenderPass(buffer: *CommandBuffer) !void {
        try buffer.buffer.append(buffer.ctx.gpa, .{
            .end_render_pass = .{},
        });
    }
};

const GraphicsPipeline = struct {};

const ComputePipeline = struct {};

const Buffer = struct {};

const Texture = struct {};
