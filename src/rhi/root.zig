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

pub const Context = struct {
    gpa: std.mem.Allocator,
    platform: Platform,
    settings: Settings,

    base: vk.BaseWrapper,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,

    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    physical_device_properties: vk.PhysicalDeviceProperties,
    physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

    queues: std.EnumArray(QueueType, vk.QueueProxy),
    queue_families: std.EnumArray(QueueType, u32),
    queue_semaphores: std.EnumArray(QueueType, vk.Semaphore),
    queue_semaphore_values: std.EnumArray(QueueType, u64),

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
        ctx.allocator = try .init(ctx);
        errdefer ctx.allocator.deinit();

        ctx.command_buffers.set(.graphics, try .init(ctx, .graphics));
        errdefer ctx.command_buffers.getPtr(.graphics).deinit();
        ctx.command_buffers.set(.async_compute, try .init(ctx, .async_compute));
        errdefer ctx.command_buffers.getPtr(.async_compute).deinit();
        ctx.command_buffers.set(.transfer, try .init(ctx, .transfer));
        errdefer ctx.command_buffers.getPtr(.transfer).deinit();
        ctx.command_buffers.set(.present, try .init(ctx, .present));
        errdefer ctx.command_buffers.getPtr(.present).deinit();
        ctx.active_command_buffer = null;

        return ctx;
    }

    pub fn destroy(ctx: *Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in vulkan_context deinit: {}", .{e});
        };

        ctx.command_buffers.getPtr(.graphics).deinit();
        ctx.command_buffers.getPtr(.async_compute).deinit();
        ctx.command_buffers.getPtr(.transfer).deinit();
        ctx.command_buffers.getPtr(.present).deinit();

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

    pub fn acquireCommandBuffer(ctx: *Context, queue_type: QueueType) *CommandBuffer {
        std.debug.assert(ctx.active_command_buffer == null);
        ctx.active_command_buffer = queue_type;
        return ctx.command_buffers.getPtr(queue_type);
    }

    pub fn submitCommandBuffer(ctx: *Context, command_buffer: *CommandBuffer) !void {
        std.debug.assert(ctx.active_command_buffer == command_buffer.queue_type);
        ctx.active_command_buffer = null;

        // FIXME add implicit pool of command buffers and check semaphores?
        // or some other strategy to make sure we can safely reset them
        try ctx.device.resetCommandPool(command_buffer.command_pool, .{});
        const cmd = command_buffer.command_buffer;
        try ctx.device.beginCommandBuffer(cmd, &.{
            .flags = .{ .one_time_submit_bit = true },
        });

        // this is basically like a vm parsing bytecode
        // meaning we could apply compiler theory to simplify it i think
        // hell yeah

        for (command_buffer.buffer.items) |command| {
            switch (command) {
                .begin_render_pass => {},
                .end_render_pass => {},
                .upload_to_buffer => {
                    // NOTE we could accumulate regions per buffer combination and batch
                    const region: vk.BufferCopy = .{
                        .src_offset = command.upload_to_buffer.src_offset,
                        .dst_offset = command.upload_to_buffer.dst_offset,
                        .size = command.upload_to_buffer.size,
                    };
                    ctx.device.cmdCopyBuffer(
                        cmd,
                        command.upload_to_buffer.src_buffer,
                        command.upload_to_buffer.dst_buffer,
                        1,
                        @ptrCast(&region),
                    );
                },
            }
        }
        command_buffer.buffer.clearRetainingCapacity();
        try ctx.device.endCommandBuffer(cmd);

        const semval = ctx.queue_semaphore_values.get(.graphics);
        ctx.queue_semaphore_values.set(.graphics, semval + 1);
        const timeline_semaphore_info: vk.TimelineSemaphoreSubmitInfo = .{
            .p_wait_semaphore_values = @ptrCast(&semval),
            .p_signal_semaphore_values = @ptrCast(&(semval + 1)),
            .signal_semaphore_value_count = 1,
            .wait_semaphore_value_count = 1,
        };
        const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .top_of_pipe_bit = true };
        const submit_info: vk.SubmitInfo = .{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmd),
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(ctx.queue_semaphores.getPtr(command_buffer.queue_type)),
            .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(ctx.queue_semaphores.getPtr(command_buffer.queue_type)),
            .p_next = &timeline_semaphore_info,
        };
        try ctx.queues.get(command_buffer.queue_type).submit(
            1,
            @ptrCast(&submit_info),
            .null_handle,
        );
    }

    pub fn createBuffer(ctx: *Context, size: u32) !Buffer {
        return ctx.allocator.createBuffer(size);
    }

    pub fn createUploadBuffer(ctx: *Context, size: u32) !UploadBuffer {
        return ctx.allocator.createUploadBuffer(size);
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

        ctx.queue_semaphore_values = .initFill(0);
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
        ctx.physical_device_properties = candidate.properties;
        ctx.physical_device_memory_properties = candidate.memory_properties;
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
    ctx: *Context,
    buffer_slabs: std.ArrayList(BufferSlab),
    upload_slabs: std.ArrayList(UploadSlab),
    // image_slabs: std.MultiArrayList(struct { mask: u32, slab: MemorySlab }),

    fn init(ctx: *Context) !Allocator {
        return .{
            .ctx = ctx,
            .buffer_slabs = .empty,
            .upload_slabs = .empty,
            // .image_slabs = .{},
        };
    }

    fn deinit(alloc: *Allocator) void {
        for (alloc.buffer_slabs.items) |*slab| slab.deinit();
        alloc.buffer_slabs.deinit(alloc.ctx.gpa);
        for (alloc.upload_slabs.items) |*slab| slab.deinit();
        alloc.upload_slabs.deinit(alloc.ctx.gpa);
    }

    fn createBuffer(alloc: *Allocator, size: u32) !Buffer {
        std.debug.assert(size <= BufferSlab.slab_size);
        // we only have one kind of buffer, so this is very straightforward
        for (alloc.buffer_slabs.items) |*slab| return slab.alloc(size) catch continue;
        // no slab with enough space, make a new one
        const slab = try alloc.buffer_slabs.addOne(alloc.ctx.gpa);
        errdefer _ = alloc.buffer_slabs.pop();
        slab.* = try .init(alloc.ctx);
        return slab.alloc(size) catch unreachable;
    }

    fn createUploadBuffer(alloc: *Allocator, size: u32) !UploadBuffer {
        std.debug.assert(size <= UploadSlab.slab_size);
        for (alloc.upload_slabs.items) |*slab| return slab.alloc(size) catch continue;
        const slab = try alloc.upload_slabs.addOne(alloc.ctx.gpa);
        errdefer _ = alloc.upload_slabs.pop();
        slab.* = try .init(alloc.ctx);
        return slab.alloc(size) catch unreachable;
    }
};

pub const AllocationPool = struct {};

const BufferSlab = struct {
    const slab_size = 256 * 1024 * 1024;

    ctx: *Context,
    buffer: vk.Buffer,
    buffer_device_address: u64,
    buffer_ptr: ?*anyopaque,
    memory: vk.DeviceMemory,
    host_visible: bool,
    host_coherent: bool,
    allocator: OffsetAllocator, // allocator for 256 byte blocks

    fn init(ctx: *Context) !BufferSlab {
        const queue_family_indices: FixedSet(3, u32) = .init(&.{
            ctx.queue_families.get(.graphics),
            ctx.queue_families.get(.async_compute),
            ctx.queue_families.get(.transfer),
        });
        const buffer_info = vk.BufferCreateInfo{
            .size = slab_size,
            .usage = .{
                .transfer_src_bit = true,
                .transfer_dst_bit = true,
                .storage_buffer_bit = true,
                .index_buffer_bit = true,
                .indirect_buffer_bit = true,
                .shader_device_address_bit = true,
            },
            .sharing_mode = .concurrent,
            .p_queue_family_indices = @ptrCast(queue_family_indices.items().ptr),
            .queue_family_index_count = @intCast(queue_family_indices.items().len),
        };
        const buffer = try ctx.device.createBuffer(&buffer_info, null);
        errdefer ctx.device.destroyBuffer(buffer, null);
        const buffer_memreq = ctx.device.getBufferMemoryRequirements(buffer);

        const memory_type_index = findMemoryType(
            buffer_memreq.memory_type_bits,
            ctx.physical_device_memory_properties,
        );
        const alloc_flags = vk.MemoryAllocateFlagsInfo{
            .flags = .{ .device_address_bit = true },
            .device_mask = undefined, // note, not used
        };
        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = buffer_memreq.size,
            .memory_type_index = memory_type_index,
            .p_next = &alloc_flags,
        };
        const memory = try ctx.device.allocateMemory(&alloc_info, null);
        errdefer ctx.device.freeMemory(memory, null);

        try ctx.device.bindBufferMemory(buffer, memory, 0);
        const buffer_device_address = ctx.device.getBufferDeviceAddress(&.{
            .buffer = buffer,
        });

        var allocator: OffsetAllocator = try .init(ctx.gpa, slab_size / 256, slab_size / 4096);
        errdefer allocator.deinit(ctx.gpa);

        const property_flags = ctx.physical_device_memory_properties
            .memory_types[memory_type_index].property_flags;

        var buffer_ptr: ?*anyopaque = null;
        if (property_flags.host_visible_bit) {
            // UMA system, map it so we can transfer directly
            buffer_ptr = try ctx.device.mapMemory(memory, 0, slab_size, .{});
        }

        return .{
            .ctx = ctx,
            .buffer = buffer,
            .buffer_device_address = buffer_device_address,
            .buffer_ptr = buffer_ptr,
            .memory = memory,
            .host_visible = !property_flags.host_visible_bit,
            .host_coherent = !property_flags.host_coherent_bit,
            .allocator = allocator,
        };
    }

    fn deinit(slab: *BufferSlab) void {
        // TODO we should probably debug log when buffers weren't freed
        // however, it's technically not required as all the actual resources are freed
        // also, without adding cruft to createBuffer it's hard to really make it easy to follow
        // although maybe copying the return address parts from the debug allocator could work?
        slab.ctx.device.destroyBuffer(slab.buffer, null);
        slab.ctx.device.freeMemory(slab.memory, null);
        slab.allocator.deinit(slab.ctx.gpa);
    }

    fn alloc(slab: *BufferSlab, size: u32) !Buffer {
        // by letting the allocator operate on 256 byte blocks
        // we skip needing to handle alignment, since 256 is enough for everything
        // at the cost of always using at least 256 bytes, which seems fine to me
        const allocation = try slab.allocator.allocate(size / 256);
        return .{
            .slab = slab,
            .allocation = allocation,
            .size = size,
            .buffer_device_address = slab.buffer_device_address + 256 * allocation.offset,
        };
    }

    fn findMemoryType(
        memory_type_bits: u32,
        physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
    ) u32 {
        // first try to pick device local only memory
        for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
            .memory_type_count], 0..) |memory_type, i|
        {
            if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (!memory_type.property_flags.device_local_bit) continue;
            if (memory_type.property_flags.host_visible_bit) continue;
            return @intCast(i);
        }
        // if not possible, pick also host visible
        for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
            .memory_type_count], 0..) |memory_type, i|
        {
            if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (!memory_type.property_flags.device_local_bit) continue;
            if (!memory_type.property_flags.host_visible_bit) continue;
            return @intCast(i);
        }
        // vulkan spec
        // There must be at least one memory type with the
        // VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT bit set in its propertyFlags
        // hence the above tests should always find a suitable memory type
        unreachable;
    }
};

const UploadSlab = struct {
    const slab_size = 256 * 1024 * 1024;

    ctx: *Context,
    buffer: vk.Buffer,
    buffer_ptr: *anyopaque,
    memory: vk.DeviceMemory,
    allocator: OffsetAllocator,

    fn init(ctx: *Context) !UploadSlab {
        const queue_family_indices: FixedSet(3, u32) = .init(&.{
            ctx.queue_families.get(.graphics),
            ctx.queue_families.get(.async_compute),
            ctx.queue_families.get(.transfer),
        });
        const buffer_info = vk.BufferCreateInfo{
            .size = slab_size,
            .usage = .{
                .transfer_src_bit = true,
            },
            .sharing_mode = .concurrent,
            .p_queue_family_indices = @ptrCast(queue_family_indices.items().ptr),
            .queue_family_index_count = @intCast(queue_family_indices.items().len),
        };
        const buffer = try ctx.device.createBuffer(&buffer_info, null);
        errdefer ctx.device.destroyBuffer(buffer, null);
        const buffer_memreq = ctx.device.getBufferMemoryRequirements(buffer);

        const memory_type_index = findMemoryType(
            buffer_memreq.memory_type_bits,
            ctx.physical_device_memory_properties,
        );
        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = buffer_memreq.size,
            .memory_type_index = memory_type_index,
        };
        const memory = try ctx.device.allocateMemory(&alloc_info, null);
        errdefer ctx.device.freeMemory(memory, null);

        try ctx.device.bindBufferMemory(buffer, memory, 0);

        const alignment: u32 = @intCast(ctx.physical_device_properties.limits
            .optimal_buffer_copy_offset_alignment);
        var allocator: OffsetAllocator = try .init(
            ctx.gpa,
            slab_size / alignment,
            slab_size / 4096,
        );
        errdefer allocator.deinit(ctx.gpa);

        const buffer_ptr = try ctx.device.mapMemory(memory, 0, slab_size, .{});

        return .{
            .ctx = ctx,
            .buffer = buffer,
            .buffer_ptr = buffer_ptr.?,
            .memory = memory,
            .allocator = allocator,
        };
    }

    fn deinit(slab: *UploadSlab) void {
        // TODO we should probably debug log when buffers weren't freed
        slab.allocator.deinit(slab.ctx.gpa);
        slab.ctx.device.destroyBuffer(slab.buffer, null);
        slab.ctx.device.freeMemory(slab.memory, null);
    }

    fn alloc(slab: *UploadSlab, size: u32) !UploadBuffer {
        const alignment: u32 = @intCast(slab.ctx.physical_device_properties.limits
            .optimal_buffer_copy_offset_alignment);
        const allocation = try slab.allocator.allocate(size / alignment);
        return .{
            .slab = slab,
            .allocation = allocation,
            .size = size,
            .allocator = .init(@as(
                [*]u8,
                @ptrCast(slab.buffer_ptr),
            )[alignment * allocation.offset .. alignment + allocation.offset + size]),
        };
    }

    fn findMemoryType(
        memory_type_bits: u32,
        physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
    ) u32 {
        // vulkan spec
        // There must be at least one memory type with both the
        // VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT and VK_MEMORY_PROPERTY_HOST_COHERENT_BIT bits
        // set in its propertyFlags
        // so this should always work
        for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
            .memory_type_count], 0..) |memory_type, i|
        {
            if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (!memory_type.property_flags.host_visible_bit) continue;
            if (!memory_type.property_flags.host_coherent_bit) continue;
            return @intCast(i);
        }
        unreachable;
    }
};

// const MemorySlab = struct {
//     const MemoryRequirement = struct {
//         size: usize,
//         memory_type_bits: u32,
//     };

//     ctx: *Context,
//     memory: vk.DeviceMemory,
//     memory_type_index: u32,
//     host_visible: bool,
//     host_coherent: bool,
//     allocator: OffsetAllocator,

//     fn init(ctx: *Context, req: MemoryRequirement) !MemorySlab {
//         const memory_type_index = findMemoryType(
//             req.memory_type_bits,
//             ctx.physical_device_memory_properties,
//         );
//         const alloc_info = vk.MemoryAllocateInfo{
//             .allocation_size = req.size,
//             .memory_type_index = memory_type_index,
//         };
//         const memory = try ctx.device.allocateMemory(&alloc_info, null);
//         errdefer ctx.device.freeMemory(memory, null);

//         const allocator: OffsetAllocator = try .init(ctx.gpa, req.size, req.size / 4096);
//         errdefer allocator.deinit(ctx.gpa);

//         const property_flags = ctx.physical_device_memory_properties
//             .memory_types[memory_type_index].property_flags;

//         if (property_flags.host_visible_bit) {
//             // UMA system, map it so we can transfer directly
//             ctx.device.mapMemory(memory, 0, req.size, .{});
//         }

//         return .{
//             .ctx = ctx,
//             .memory = memory,
//             .memory_type_index = memory_type_index,
//             .host_visible = !property_flags.host_visible,
//             .host_coherent = !property_flags.host_coherent,
//             .allocator = allocator,
//         };
//     }

//     fn deinit(slab: *MemorySlab) void {
//         errdefer slab.ctx.device.freeMemory(slab.memory, null);
//         errdefer slab.allocator.deinit(slab.ctx.gpa);
//     }

//     fn alloc(slab: *MemorySlab, size: u32) !Allocation {
//         return slab.allocator.allocate(size);
//     }

//     fn findMemoryType(
//         memory_type_bits: u32,
//         physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
//     ) u32 {
//         // first try to pick device local only memory
//         for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
//             .memory_type_count], 0..) |memory_type, i|
//         {
//             if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
//             if (!memory_type.property_flags.device_local_bit) continue;
//             if (memory_type.property_flags.host_visible) continue;
//             return @intCast(i);
//         }
//         // if not possible, pick also host visible
//         for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
//             .memory_type_count], 0..) |memory_type, i|
//         {
//             if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
//             if (!memory_type.property_flags.device_local_bit) continue;
//             if (!memory_type.property_flags.host_visible) continue;
//             return @intCast(i);
//         }
//         // otherwise, just pick whatever is possible
//         for (physical_device_memory_properties.memory_types[0..physical_device_memory_properties
//             .memory_type_count], 0..) |memory_type, i|
//         {
//             if (memory_type_bits & (@as(u32, 1) << @intCast(i)) == 0) continue;
//             log.warn("Ideal memory type not found, picking {}", .{memory_type});
//             return @intCast(i);
//         }
//         unreachable;
//     }
// };

const Command = union(enum) {
    begin_render_pass: struct {},
    end_render_pass: struct {},
    upload_to_buffer: struct {
        size: u32,
        src_offset: u32,
        src_buffer: vk.Buffer,
        dst_buffer: vk.Buffer,
        dst_offset: u32,
    },
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
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,

    fn init(ctx: *Context, queue_type: QueueType) !CommandBuffer {
        var result: CommandBuffer = .{
            .ctx = ctx,
            .queue_type = queue_type,
            .buffer = .empty,
            .command_pool = .null_handle,
            .command_buffer = .null_handle,
        };
        result.command_pool = try ctx.device.createCommandPool(&.{
            .flags = .{},
            .queue_family_index = ctx.queue_families.get(queue_type),
        }, null);
        errdefer ctx.device.destroyCommandPool(result.command_pool, null);
        try ctx.device.allocateCommandBuffers(&.{
            .command_pool = result.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&result.command_buffer));
        return result;
    }

    fn deinit(buffer: *CommandBuffer) void {
        buffer.ctx.device.freeCommandBuffers(
            buffer.command_pool,
            1,
            @ptrCast(&buffer.command_buffer),
        );
        buffer.ctx.device.destroyCommandPool(buffer.command_pool, null);
        buffer.buffer.deinit(buffer.ctx.gpa);
    }

    pub fn beginRenderPass(buffer: *CommandBuffer) !void {
        try buffer.buffer.append(buffer.ctx.gpa, .{ .begin_render_pass = .{} });
    }

    pub fn endRenderPass(buffer: *CommandBuffer) !void {
        try buffer.buffer.append(buffer.ctx.gpa, .{ .end_render_pass = .{} });
    }

    pub fn uploadToBuffer(
        buffer: *CommandBuffer,
        src: []const u8,
        staging: *UploadBuffer,
        dst: *Buffer,
        dst_offset: u32,
    ) !void {
        const staged = try staging.allocator.allocator().dupe(u8, src);
        try buffer.buffer.append(buffer.ctx.gpa, .{ .upload_to_buffer = .{
            .size = @intCast(src.len),
            .src_offset = @intCast(@intFromPtr(staged.ptr) - @intFromPtr(staging.slab.buffer_ptr)),
            .src_buffer = staging.slab.buffer,
            .dst_offset = dst_offset,
            .dst_buffer = dst.slab.buffer,
        } });
    }
};

const GraphicsPipeline = struct {};

const ComputePipeline = struct {};

const Buffer = struct {
    slab: *BufferSlab,
    allocation: Allocation,
    size: u32,
    buffer_device_address: u64,
};

const UploadBuffer = struct {
    slab: *UploadSlab,
    allocation: Allocation,
    size: u32,

    // TODO this needs to contain a linear allocator
    allocator: std.heap.FixedBufferAllocator,
};

const Texture = struct {};

fn FixedSet(comptime capacity: comptime_int, comptime T: type) type {
    return struct {
        const Self = @This();

        count: usize,
        data: [capacity]T,

        fn init(_items: []const T) Self {
            std.debug.assert(_items.len <= capacity);
            var result: Self = .{ .count = 0, .data = undefined };
            outer: for (_items) |new| {
                for (result.data[0..result.count]) |old| if (new == old) continue :outer;
                result.data[result.count] = new;
                result.count += 1;
            }
            return result;
        }

        fn items(set: *const Self) []const T {
            return set.data[0..set.count];
        }
    };
}
