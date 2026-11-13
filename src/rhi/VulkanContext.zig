const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");
const allocators = @import("allocators.zig");

const log = std.log.scoped(.rhi_vulkan);

const Context = @This();

pub const PlatformError = error{Platform};
pub const Platform = struct {
    // TODO not sure what the best function signatures are here
    getInstanceProcAddress: *const fn (?*anyopaque, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () PlatformError![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) PlatformError!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) PlatformError!vk.Extent2D,
};

/// enable_validation activates the validation layer
/// enable_debug activates debug_utils and buffer_device_address_capture_replay
pub const Config = struct {
    name: [:0]const u8,
    preferred_physical_device: ?[]const u8 = null,
    upload_staging_size: usize = 512 * 1024 * 1024,
    download_staging_size: usize = 128 * 1024 * 1024,
    enable_debug: bool = @import("builtin").mode == .debug,
    enable_validation: bool = @import("builtin").mode == .debug,
};

const PhysicalQueue = struct {
    queue: vk.QueueProxy,
    family: u32,
    semaphore: vk.Semaphore,
    value: u64,
};

const api_version: u32 = @bitCast(vk.API_VERSION_1_3);

const layers = [_][*:0]const u8{};
const debug_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const instance_extensions = [_][*:0]const u8{
    "VK_KHR_surface",
};
const debug_instance_extensions = [_][*:0]const u8{
    "VK_EXT_debug_utils",
};

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
    .buffer_device_address_capture_replay = .true, // FIXME somehow make this depend on the config
    .descriptor_binding_partially_bound = .true,
    .descriptor_binding_sampled_image_update_after_bind = .true,
    .descriptor_binding_storage_image_update_after_bind = .true,
    .descriptor_binding_update_unused_while_pending = .true,
    .descriptor_indexing = .true,
    .draw_indirect_count = .true,
    .runtime_descriptor_array = .true,
    .scalar_block_layout = .true,
    .shader_sampled_image_array_non_uniform_indexing = .true,
    .shader_storage_image_array_non_uniform_indexing = .true,
    .timeline_semaphore = .true,
};
const device_features_1_3 = vk.PhysicalDeviceVulkan13Features{
    .dynamic_rendering = .true,
    .synchronization_2 = .true,
};

const vtable: rhi.Context.VTable = .{
    .createSwapchain = undefined,
    .destroySwapchain = undefined,
    .acquireSwapchain = undefined,
    .createTexture = undefined,
    .createSampler = undefined,
    .createShader = undefined,
    .createGraphicsPipeline = undefined,
    .createComputePipeline = undefined,
    .destroyTexture = undefined,
    .destroySampler = undefined,
    .destroyShader = undefined,
    .destroyGraphicsPipeline = undefined,
    .destroyComputePipeline = undefined,
    .stagingAllocator = undefined,
    .alloc = undefined,
    .free = undefined,
    .flush = undefined,
    .acquireCommandList = undefined,
    .submit = undefined,
    .wait = undefined,
};

gpa: std.mem.Allocator,
io: std.Io,
platform: Platform,
config: Config,

base: vk.BaseWrapper,
instance: vk.InstanceProxy,
device: vk.DeviceProxy,

physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
physical_device_descriptor_indexing_properties: vk.PhysicalDeviceDescriptorIndexingProperties,
physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

graphics_queue: *PhysicalQueue,
present_queue: *PhysicalQueue,
queue_family_indices: []u32,

descriptor_set_layout: vk.DescriptorSetLayout,
pipeline_layout: vk.PipelineLayout,
descriptor_pool: vk.DescriptorPool,
descriptor_set: vk.DescriptorSet,

buffer_allocator: allocators.BufferAllocator,
texture_allocator: allocators.TextureAllocator,
upload_allocator: allocators.StagingAllocator,
download_allocator: allocators.StagingAllocator,

pub fn init(
    gpa: std.mem.Allocator,
    io: std.Io,
    platform: Context.Platform,
    config: Context.Config,
    window: rhi.Window,
) !rhi.Context {
    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const ctx = try gpa.create(Context);
    errdefer gpa.destroy(ctx);

    ctx.gpa = gpa;
    ctx.io = io;
    ctx.platform = platform;
    ctx.config = config;
    ctx.base = .load(platform.getInstanceProcAddress);

    try ctx.initInstance(arena, platform, config);
    errdefer ctx.deinitInstance();
    try ctx.initDevice(arena, config, window);
    errdefer ctx.deinitDevice();
    try ctx.initPipelineLayout();
    errdefer ctx.deinitPipelineLayout();
    // const physical_device_candidate = try ctx.pickPhysicalDevice(arena, config, window);
    // try ctx.initDevice(arena, physical_device_candidate);
    // errdefer ctx.deinitDevice();
    // try ctx.initPipelineLayout();
    // errdefer ctx.deinitPipelineLayout();

    // ctx.command_pool_depots = .initFill(.init(gpa));
    // ctx.acquire_semaphore_depot = .init(gpa);

    // // TODO init all allocators
    // ctx.texture_allocator = try .init(ctx);
    // errdefer ctx.texture_allocator.deinit();
    // ctx.buffer_allocator = try .init(ctx);
    // errdefer ctx.buffer_allocator.deinit();
    // ctx.upload_allocator = try .init(ctx, .upload);
    // errdefer ctx.upload_allocator.deinit();
    // ctx.download_allocator = try .init(ctx, .download);
    // errdefer ctx.download_allocator.deinit();

    ctx.buffer_allocator = try .init(ctx);
    std.debug.print("{}\n", .{try ctx.buffer_allocator.alloc(123, 0)});
    std.debug.print("{}\n", .{try ctx.buffer_allocator.alloc(456, 0)});

    return .{
        .ptr = ctx,
        .vtable = &Context.vtable,
    };
}

pub fn deinit(rhi_ctx: rhi.Context) void {
    const ctx: *Context = @ptrCast(@alignCast(rhi_ctx.ptr));

    ctx.device.deviceWaitIdle() catch |e| {
        log.warn("Failed deviceWaitIdle in deinit: {}", .{e});
    };

    ctx.buffer_allocator.deinit();

    ctx.deinitPipelineLayout();
    ctx.deinitDevice();
    ctx.deinitInstance();

    ctx.gpa.destroy(ctx);
}

fn initInstance(
    ctx: *Context,
    arena: std.mem.Allocator,
    platform: Platform,
    config: Config,
) !void {
    var all_layers: std.ArrayList([*:0]const u8) = .empty;
    try all_layers.appendSlice(arena, &layers);
    if (config.enable_validation) try all_layers.appendSlice(arena, &debug_layers);
    const available_layers = try ctx.base.enumerateInstanceLayerPropertiesAlloc(arena);
    for (all_layers.items) |req| {
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
    outer: for (instance_extensions) |ext1| {
        for (all_extensions.items) |ext2| if (std.mem.eql(
            u8,
            std.mem.sliceTo(ext1, 0),
            std.mem.sliceTo(ext2, 0),
        )) continue :outer;
        try all_extensions.append(arena, ext1);
    }
    if (config.enable_debug) outer: for (debug_instance_extensions) |ext1| {
        for (all_extensions.items) |ext2| if (std.mem.eql(
            u8,
            std.mem.sliceTo(ext1, 0),
            std.mem.sliceTo(ext2, 0),
        )) continue :outer;
        try all_extensions.append(arena, ext1);
    };
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

    // TODO take engine name an versions in config
    const app_info = vk.ApplicationInfo{
        .p_application_name = config.name,
        .application_version = 0,
        .p_engine_name = null,
        .engine_version = 0,
        .api_version = api_version,
    };
    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(all_layers.items.len),
        .pp_enabled_layer_names = all_layers.items.ptr,
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

const PhysicalDeviceCandidate = struct {
    device: vk.PhysicalDevice,

    properties: vk.PhysicalDeviceProperties,
    descriptor_indexing_properties: vk.PhysicalDeviceDescriptorIndexingProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    features: vk.PhysicalDeviceFeatures,
    features_1_1: vk.PhysicalDeviceVulkan11Features,
    features_1_2: vk.PhysicalDeviceVulkan12Features,
    features_1_3: vk.PhysicalDeviceVulkan13Features,

    graphics_queue_family: u32,
    present_queue_family: u32,

    fn init(
        arena: std.mem.Allocator,
        instance: vk.InstanceProxy,
        dev: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
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
            .graphics_queue_family = std.math.maxInt(u32),
            .present_queue_family = std.math.maxInt(u32),
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
        // present queue should preferably be same as graphics
        const queue_families =
            try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(dev, arena);
        for (queue_families, 0..) |family, i| {
            if (!family.queue_flags.graphics) continue;
            if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                candidate.device,
                @intCast(i),
                surface,
            ) != .true) continue;
            candidate.graphics_queue_family = @intCast(i);
            candidate.present_queue_family = @intCast(i);
            break;
        } else {
            // no graphics + present
            // select graphics
            for (queue_families, 0..) |family, i| {
                if (!family.queue_flags.graphics) continue;
                candidate.graphics_queue_family = @intCast(i);
                break;
            }
            // select present
            for (queue_families, 0..) |_, i| {
                if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                    candidate.device,
                    @intCast(i),
                    surface,
                ) != .true) continue;
                candidate.present_queue_family = @intCast(i);
                break;
            }
        }

        return candidate;
    }

    fn checkExtensionSupport(
        candidate: *const PhysicalDeviceCandidate,
        arena: std.mem.Allocator,
        instance: vk.InstanceProxy,
        config: Config,
    ) !bool {
        const available_exts = try instance.enumerateDeviceExtensionPropertiesAlloc(
            candidate.device,
            null,
            arena,
        );

        for (if (config.enable_validation)
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
                log.info("Unsupported instance extension: {s}", .{req_name});
                return false;
            }
        }
        return true;
    }

    fn checkFeatureSupport(candidate: *const PhysicalDeviceCandidate) !bool {
        const features_info = @typeInfo(vk.PhysicalDeviceFeatures).@"struct";
        inline for (features_info.field_names, features_info.field_types) |n, t| {
            if (t != vk.Bool32) continue;
            if (@field(device_features, n) == .false) continue;
            if (@field(candidate.features, n) == .false) {
                log.debug("Unsupported physical device feature: {s}", .{n});
                return false;
            }
        }
        const features_1_1_info = @typeInfo(vk.PhysicalDeviceVulkan11Features).@"struct";
        inline for (features_1_1_info.field_names, features_1_1_info.field_types) |n, t| {
            if (t != vk.Bool32) continue;
            if (@field(device_features_1_1, n) == .false) continue;
            if (@field(candidate.features_1_1, n) == .false) {
                log.debug("Unsupported physical device feature: {s}", .{n});
                return false;
            }
        }
        const features_1_2_info = @typeInfo(vk.PhysicalDeviceVulkan12Features).@"struct";
        inline for (features_1_2_info.field_names, features_1_2_info.field_types) |n, t| {
            if (t != vk.Bool32) continue;
            if (@field(device_features_1_2, n) == .false) continue;
            if (@field(candidate.features_1_2, n) == .false) {
                log.debug("Unsupported physical device feature: {s}", .{n});

                return false;
            }
        }
        const features_1_3_info = @typeInfo(vk.PhysicalDeviceVulkan13Features).@"struct";
        inline for (features_1_3_info.field_names, features_1_3_info.field_types) |n, t| {
            if (t != vk.Bool32) continue;
            if (@field(device_features_1_3, n) == .false) continue;
            if (@field(candidate.features_1_3, n) == .false) {
                log.debug("Unsupported physical device feature: {s}", .{n});
                return false;
            }
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
            if (!heap.flags.device_local) continue;
            ha += @intCast(heap.size);
        }
        var hb: i64 = 0;
        for (b.memory_properties.memory_heaps[0..b.memory_properties.memory_heap_count]) |heap| {
            if (!heap.flags.device_local) continue;
            hb += @intCast(heap.size);
        }
        if (ha == hb) return null;
        return hb > ha;
    }
};

fn initDevice(
    ctx: *Context,
    arena: std.mem.Allocator,
    config: Config,
    window: ?rhi.Window,
) !void {
    const devices = try ctx.instance.enumeratePhysicalDevicesAlloc(arena);
    var candidates: std.ArrayList(PhysicalDeviceCandidate) =
        try .initCapacity(arena, devices.len);

    // construct a temporary surface used to identify devices that can present
    var surface: vk.SurfaceKHR = .null;
    if (window) |w| surface = try ctx.platform.createWindowSurface(ctx.instance.handle, w);
    defer if (surface != .null) ctx.instance.destroySurfaceKHR(surface, null);

    for (devices) |dev| {
        const candidate: PhysicalDeviceCandidate =
            try .init(arena, ctx.instance, dev, surface);
        const name = std.mem.sliceTo(&candidate.properties.device_name, 0);

        if (!try candidate.checkExtensionSupport(arena, ctx.instance, config)) {
            log.debug("Cannot pick {s}: Unsupported device extensions", .{name});
            continue;
        }
        if (!try candidate.checkFeatureSupport()) {
            log.debug("Cannot pick {s}: Unsupported physical device features", .{name});
            continue;
        }
        if (candidate.graphics_queue_family == std.math.maxInt(u32)) {
            log.debug("Cannot pick {s}: No graphics queue", .{name});
            continue;
        }
        if (candidate.present_queue_family == std.math.maxInt(u32)) {
            log.debug("Cannot pick {s}: No present queue", .{name});
            continue;
        }

        log.debug("Added {s} as a candidate physical device", .{name});
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
    const candidate = candidates.items[0];
    log.info(
        "Selected physical device: {s}",
        .{std.mem.sliceTo(&candidate.properties.device_name, 0)},
    );
    log.debug(
        "Graphics queue family: {}",
        .{candidates.items[0].graphics_queue_family},
    );
    log.debug(
        "Present queue family: {}",
        .{candidates.items[0].present_queue_family},
    );

    var queue_create_infos: std.AutoArrayHashMapUnmanaged(u32, vk.DeviceQueueCreateInfo) = .empty;
    try queue_create_infos.put(arena, candidate.graphics_queue_family, .{
        .queue_family_index = candidate.graphics_queue_family,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&@as(f32, 1.0)),
    });
    try queue_create_infos.put(arena, candidate.present_queue_family, .{
        .queue_family_index = candidate.present_queue_family,
        .queue_count = 1,
        .p_queue_priorities = @ptrCast(&@as(f32, 1.0)),
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

    ctx.queue_family_indices = try ctx.gpa.alloc(u32, queue_create_infos.count());

    // for each unique queue, create the physical queue
    for (queue_create_infos.keys(), 0..) |queue_family_index, i| {
        const physical_queue = try ctx.gpa.create(PhysicalQueue);
        physical_queue.family = queue_family_index;
        physical_queue.queue = .init(
            ctx.device.getDeviceQueue(queue_family_index, 0),
            ctx.device.wrapper,
        );
        physical_queue.value = 0;
        physical_queue.semaphore = ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null) catch return error.Unknown; // TODO

        // then assign it to all queues that share that family
        if (candidate.graphics_queue_family == queue_family_index) {
            ctx.graphics_queue = physical_queue;
        }
        if (candidate.present_queue_family == queue_family_index) {
            ctx.present_queue = physical_queue;
        }
        ctx.queue_family_indices[i] = queue_family_index;
    }

    ctx.physical_device = candidate.device;
    ctx.physical_device_properties = candidate.properties;
    ctx.physical_device_descriptor_indexing_properties = candidate.descriptor_indexing_properties;
    ctx.physical_device_memory_properties = candidate.memory_properties;

    for (ctx.queue_family_indices, 0..) |q0, i| {
        for (ctx.queue_family_indices, 0..) |q1, j| {
            if (i == j) continue;
            std.debug.assert(q0 != q1);
        }
    }
}

fn deinitDevice(ctx: *Context) void {
    if (ctx.present_queue != ctx.graphics_queue) {
        ctx.device.destroySemaphore(ctx.present_queue.semaphore, null);
        ctx.gpa.destroy(ctx.present_queue);
    }
    ctx.device.destroySemaphore(ctx.graphics_queue.semaphore, null);
    ctx.gpa.destroy(ctx.graphics_queue);
    ctx.gpa.free(ctx.queue_family_indices);

    ctx.device.destroyDevice(null);
    ctx.gpa.destroy(ctx.device.wrapper);
    ctx.physical_device = undefined;
}

fn initPipelineLayout(ctx: *Context) !void {
    // TODO we should maybe check the limits just in case and limit further if broken
    // however, these are within the minimum required, so safe if the driver is compliant
    const bindings: [3]vk.DescriptorSetLayoutBinding = .{ .{
        .binding = 0,
        .descriptor_type = .sampled_image,
        .descriptor_count = 256 * 1024,
        .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
    }, .{
        .binding = 1,
        .descriptor_type = .storage_image,
        .descriptor_count = 256 * 1024,
        .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
    }, .{
        .binding = 2,
        .descriptor_type = .sampler,
        .descriptor_count = 1024,
        .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
    } };
    const binding_flags: [3]vk.DescriptorBindingFlags = .{ .{
        .update_after_bind = true,
        .update_unused_while_pending = true,
        .partially_bound = true,
    }, .{
        .update_after_bind = true,
        .update_unused_while_pending = true,
        .partially_bound = true,
    }, .{
        .update_after_bind = true,
        .update_unused_while_pending = true,
        .partially_bound = true,
    } };

    ctx.descriptor_set_layout = try ctx.device.createDescriptorSetLayout(&.{
        .binding_count = 3,
        .flags = .{ .update_after_bind_pool = true },
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
            .stage_flags = .{ .vertex = true, .fragment = true, .compute = true },
            .offset = 0,
            .size = 128,
        }),
    }, null);
    errdefer ctx.device.destroyPipelineLayout(ctx.pipeline_layout, null);

    const pool_sizes = [3]vk.DescriptorPoolSize{
        .{ .type = .sampled_image, .descriptor_count = 256 * 1024 },
        .{ .type = .storage_image, .descriptor_count = 256 * 1024 },
        .{ .type = .sampler, .descriptor_count = 1024 },
    };
    ctx.descriptor_pool = try ctx.device.createDescriptorPool(&.{
        .flags = .{ .update_after_bind = true },
        .max_sets = 1,
        .pool_size_count = @intCast(pool_sizes.len),
        .p_pool_sizes = &pool_sizes,
    }, null);
    errdefer ctx.device.destroyDescriptorPool(ctx.descriptor_pool, null);

    ctx.descriptor_set = .null;
    try ctx.device.allocateDescriptorSets(&.{
        .descriptor_pool = ctx.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&ctx.descriptor_set_layout),
    }, @ptrCast(&ctx.descriptor_set));
}

fn deinitPipelineLayout(ctx: *Context) void {
    // NOTE freeing the pool frees the set
    ctx.device.destroyDescriptorPool(ctx.descriptor_pool, null);
    ctx.device.destroyPipelineLayout(ctx.pipeline_layout, null);
    ctx.device.destroyDescriptorSetLayout(ctx.descriptor_set_layout, null);
}
