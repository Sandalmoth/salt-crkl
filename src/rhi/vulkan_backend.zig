const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");

const log = std.log.scoped(.rhi_vulkan);

const MemoryPool = std.heap.MemoryPool;

const enable_debug = @import("builtin").mode == .Debug;
const enable_validation = @import("builtin").mode == .Debug;

pub const Platform = struct {
    // TODO not sure what the best function signatures are here
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () anyerror![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) anyerror!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) anyerror!vk.Extent2D,
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

// NOTE i think we should bake the passes into here with just separate vtables
const CommandBuffer = struct {};

const Context = struct {
    const vtable: rhi.Context.VTable = undefined;

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

    swapchains: std.AutoHashMapUnmanaged(rhi.Window, struct {
        surface: vk.SurfaceKHR,
        composition: rhi.SwapchainComposition,
        present_mode: rhi.PresentMode,
        swapchain: *Swapchain,
    }),

    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set: vk.DescriptorSet,
    texture_view_slots: SlotPool,
    sampler_slots: SlotPool,

    // pools are for resources that are recreated, not reused
    shader_pool: MemoryPool(Shader),
    graphics_pipeline_pool: MemoryPool(GraphicsPipeline),
    compute_pipeline_pool: MemoryPool(ComputePipeline),
    buffer_pool: MemoryPool(Buffer),
    texture_pool: MemoryPool(Texture),
    sampler_pool: MemoryPool(Sampler),

    // depots are for resources that are reused once available
    command_buffer_depots: std.EnumArray(Queue, Depot(CommandBuffer)),
    image_acquire_semaphore_depot: Depot(vk.Semaphore),

    buffer_allocator: BufferAllocator,
    texture_allocator: TextureAllocator,
    upload_allocator: UploadAllocator,
    download_allocator: DownloadAllocator,

    queues: std.EnumArray(Queue, *PhysicalQueue),

    fn init(gpa: std.mem.Allocator, platform: Platform, config: Config) !Context {
        var arena_impl: std.heap.ArenaAllocator = .init(gpa);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        var ctx: Context = undefined;

        ctx.gpa = gpa;
        ctx.platform = platform;
        ctx.config = config;
        ctx.base = .load(platform.getInstanceProcAddress);

        ctx.swapchains = .empty;

        try ctx.initInstance(arena, platform, config.name);
        errdefer ctx.deinitInstance();
        const physical_device_candidate = try ctx.pickPhysicalDevice(arena);
        try ctx.initDevice(arena, physical_device_candidate);
        errdefer ctx.deinitDevice();
        try ctx.initPipelineLayout();
        errdefer ctx.deinitPipelineLayout();

        ctx.gpa = gpa;
        ctx.platform = platform;
        ctx.shader_pool = .init(gpa);
        ctx.graphics_pipeline_pool = .init(gpa);
        ctx.compute_pipeline_pool = .init(gpa);
        ctx.buffer_pool = .init(gpa);
        ctx.texture_pool = .init(gpa);
        ctx.command_buffer_depots = .initFill(.init(gpa));
        ctx.image_acquire_semaphore_depot = .init(gpa);

        // TODO init allocators

        return ctx;
    }

    fn deinit(ctx: *Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in deinit: {}", .{e});
        };

        var physical_queues: [4]?*PhysicalQueue = .{null} ** 4;
        outer: for ([_]Queue{ .graphics, .compute, .transfer }, 0..) |queue, j| {
            for (0..4) |i| if (physical_queues[i] == ctx.queues.get(queue)) continue :outer;
            physical_queues[j] = ctx.queues.get(queue);
        }
        if (ctx.swapchains.metadata != null) {
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

const Swapchain = struct {
    next: ?*Swapchain,
};

const BufferAllocator = struct {};

const TextureAllocator = struct {};

const UploadAllocator = struct {};

const DownloadAllocator = struct {};

fn Depot(comptime T: type) type {
    _ = T;
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,

        fn init(gpa: std.mem.Allocator) Self {
            return .{
                .gpa = gpa,
            };
        }

        fn deinit(depot: *Self) void {
            depot.* = undefined;
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
