const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");

const log = std.log.scoped(.rhi_vulkan);

const Context = @This();

const SlotPool = @import("SlotPool.zig");
const OffsetAllocator = @import("OffsetAllocator.zig").Allocator;
const OffsetAllocation = @import("OffsetAllocator.zig").Allocation;

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
    .createSwapchain = createSwapchain,
    .destroySwapchain = destroySwapchain,
    .acquireSwapchain = acquireSwapchain,
    .createGroup = undefined,
    .createBuffer = undefined,
    .createTexture = undefined,
    .createSampler = undefined,
    .createShader = undefined,
    .createGraphicsPipeline = undefined,
    .createComputePipeline = undefined,
    .destroyBuffer = undefined,
    .destroyGroup = undefined,
    .destroyTexture = undefined,
    .destroySampler = undefined,
    .destroyShader = undefined,
    .destroyGraphicsPipeline = undefined,
    .destroyComputePipeline = undefined,
    .stagingAllocator = undefined,
    .invalidate = undefined,
    .acquireCommandList = undefined,
    .submit = undefined,
    .wait = undefined,
    .setBufferGroup = undefined,
    .setTextureGroup = undefined,
};

const Buffer = struct {
    public: rhi.Buffer,
    slab: *BufferAllocator.Slab,
    allocation: OffsetAllocation,

    fn vulkan(buffer: *Buffer) struct { buffer: vk.Buffer, offset: u64 } {
        return .{
            .buffer = buffer.slab.buffer,
            .offset = buffer.allocation.offset * BufferAllocator.Slab.granularity,
        };
    }
};

const Texture = struct {
    public: rhi.Texture,
    image: vk.Image,
    memory: union(enum) {
        slab: struct {
            allocation: OffsetAllocation,
            slab: *TextureAllocator.Slab,
        },
        dedicated: vk.DeviceMemory,
    },
};

const View = struct {
    public: rhi.View,
    view: vk.ImageView,
};

const Group = struct {
    public: rhi.Group,
    managed: bool,
    buffer_count: u32 = 0,
};

const Swapchain = struct {
    public: rhi.Swapchain,
    acquired: bool,
    window: rhi.Window,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    images: []vk.Image,
    views: []vk.ImageView,
    release_semaphores: []vk.Semaphore,
    image_index: ?u32,
    acquire_semaphore: vk.Semaphore,
};

const CommandPool = struct {
    pool: vk.CommandPool,
    buffer: vk.CommandBuffer,
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

graphics_command_depot: Depot(CommandPool),
present_command_depot: Depot(CommandPool),
acquire_semaphore_depot: Depot(vk.Semaphore),

group_pool: std.heap.MemoryPool(Group),
buffer_allocator: BufferAllocator,
texture_allocator: TextureAllocator,
upload_allocator: StagingAllocator,
download_allocator: StagingAllocator,

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

    ctx.graphics_command_pool_depot = .init(gpa);
    ctx.present_command_pool_depot = .init(gpa);
    ctx.acquire_semaphore_depot = .init(gpa);

    ctx.group_pool = .empty;
    ctx.buffer_allocator = try .init(ctx);
    errdefer ctx.buffer_allocator.deinit();
    ctx.texture_allocator = try .init(ctx);
    errdefer ctx.texture_allocator.deinit();
    ctx.upload_allocator = try .init(ctx, .upload);
    errdefer ctx.upload_allocator.deinit();
    ctx.download_allocator = try .init(ctx, .download);
    errdefer ctx.download_allocator.deinit();

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

    ctx.graphics_command_depot.deinit();
    ctx.present_command_depot.deinit();
    ctx.acquire_semaphore_depot.deinit();

    ctx.download_allocator.deinit();
    ctx.upload_allocator.deinit();
    ctx.texture_allocator.deinit();
    ctx.buffer_allocator.deinit();
    ctx.group_pool.deinit(ctx.gpa);

    ctx.deinitPipelineLayout();
    ctx.deinitDevice();
    ctx.deinitInstance();

    ctx.gpa.destroy(ctx);
}

fn createSwapchain(
    ptr: *anyopaque,
    create_info: rhi.SwapchainCreateInfo,
) rhi.Context.Error!*const rhi.Swapchain {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const swapchain: *Swapchain = try ctx.swapchain_pool.create(ctx.gpa);

    const surface = try ctx.platform.createWindowSurface(ctx.instance.handle, create_info.window);
    errdefer ctx.instance.destroySurfaceKHR(surface, null);

    swapchain.* = Swapchain{
        .public = .{ .info = .{
            .name = create_info.name,
            .composition = .sdr,
            .present_mode = .fifo,
            .size = .{ 0, 0, 0 },
        } },
        .acquired = false,
        .surface = surface,
        .window = create_info.window,
        .swapchain = .null,
        .images = &.{},
        .views = &.{},
        .release_semaphores = &.{},
        .image_index = null,
        .acquire_semaphore = .null,
    };

    return &swapchain.public;
}

fn destroySwapchain(ptr: *anyopaque, rhi_swapchain: *const rhi.Swapchain) void {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const swapchain: *Swapchain = @alignCast(@constCast(
        @fieldParentPtr("public", rhi_swapchain),
    ));

    // needs idle to make sure it's not in use since we can't wait on present
    ctx.device.deviceWaitIdle() catch |e| {
        log.warn("Failed deviceWaitIdle in destroySwapchain: {}", .{e});
    };

    if (swapchain.swapchain != .null) {
        for (0..swapchain.images.len) |i| {
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

fn acquireSwapchain(
    ptr: *anyopaque,
    rhi_swapchain: *const rhi.Swapchain,
    timeout: u64,
) rhi.Context.Error!bool {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const swapchain: *Swapchain = @alignCast(@constCast(
        @fieldParentPtr("public", rhi_swapchain),
    ));

    std.debug.assert(!swapchain.acquired);

    if (swapchain.swapchain == .null) {
        try ctx.recreateSwapchain(swapchain);
    }

    const acquire_semaphore = ctx.acquire_semaphore_depot.pop(
        try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.present).semaphore),
    ) orelse
        ctx.device.createSemaphore(&.{}, null) catch return false;
    // FIXME if we return early, this needs to be pushed

    const result = ctx.device.acquireNextImageKHR(
        swapchain.swapchain,
        timeout,
        acquire_semaphore,
        .null,
    ) catch |e| switch (e) {
        error.OutOfDateKHR => vk.DeviceWrapper.AcquireNextImageKHRResult{
            .result = .error_out_of_date_khr,
            .image_index = undefined,
        },
        else => return e,
    };
    switch (result.result) {
        .success => {
            swapchain.acquired = true;
            swapchain.image_index = result.image_index;
            swapchain.acquire_semaphore = acquire_semaphore;
        },
        .timeout => {},
        .not_ready => {},
        .suboptimal_khr, .error_out_of_date_khr => {
            try ctx.recreateSwapchain(swapchain);
        },
        else => unreachable,
    }

    return swapchain.acquired;
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

const BufferAllocator = struct {
    const Slab = struct {
        const slab_size = 256 * 1024 * 1024;
        const granularity = 64;

        allocator: OffsetAllocator,
        memory: vk.DeviceMemory,
        buffer: vk.Buffer,
        device_address: u64,
    };

    const Deferred = struct {
        semaphore_value: u64,
        buffer: *Buffer,
    };

    ctx: *Context,
    pool: std.heap.MemoryPool(Buffer),
    slabs: std.ArrayList(Slab),
    queue: std.ArrayList(Deferred),
    counter: u32,

    fn init(ctx: *Context) !BufferAllocator {
        return .{
            .ctx = ctx,
            .pool = .empty,
            .slabs = .empty,
            .queue = .empty,
            .counter = 0,
        };
    }

    fn deinit(alloc: *BufferAllocator) void {
        // TODO add some debug printing if we haven't freed everything?
        alloc.pool.deinit(alloc.ctx.gpa);
        alloc.queue.deinit(alloc.ctx.gpa);
        for (alloc.slabs.items) |*slab| {
            alloc.ctx.device.destroyBuffer(slab.buffer, null);
            alloc.ctx.device.freeMemory(slab.memory, null);
            slab.allocator.deinit(alloc.ctx.gpa);
        }
        alloc.slabs.deinit(alloc.ctx.gpa);
        alloc.* = undefined;
    }

    fn create(alloc: *BufferAllocator, create_info: rhi.BufferCreateInfo) !*Buffer {
        if (create_info.temporary) log.debug("BufferCreateInfo.temporary not implemented yet", .{});
        if (create_info.size > Slab.slab_size) return error.OutOfMemory;

        const granule_size: u32 = @intCast(
            (create_info.size + Slab.granularity - 1) / Slab.granularity,
        );

        // ensure that we have a spot for this allocation in the deferred destruction queue
        try alloc.queue.ensureUnusedCapacity(alloc.ctx.gpa, alloc.counter + 1);

        const buffer = try alloc.pool.create(alloc.ctx.gpa);
        errdefer alloc.pool.destroy(buffer);
        // TODO group in create info
        const group = try alloc.ctx.group_pool.create(alloc.ctx.gpa);
        group.* = .{
            .public = .{ .info = .{ .name = &.{} } },
            .managed = true,
            .buffer_count = 1,
        };
        errdefer alloc.ctx.group_pool.destroy(group);

        for (alloc.slabs.items) |*slab| {
            const allocation = slab.allocator.allocate(granule_size) catch continue;
            buffer.* = .{
                .public = .{
                    .group = &group.public, // TODO FIXME
                    .device_address = slab.device_address + allocation.offset * Slab.granularity,
                    .info = .{
                        .size = create_info.size,
                        .name = create_info.name,
                    },
                },
                .slab = slab,
                .allocation = allocation,
            };
            alloc.counter += 1;
            return buffer;
        }

        // no allocation possible with extant slabs, make a new one
        try alloc.addSlab();
        alloc.pool.destroy(buffer); // will be created again in the recursive call, so don't leak
        return alloc.create(create_info);
    }

    /// semaphore_value should be the value when the final use is done
    fn queueDestroy(
        alloc: *BufferAllocator,
        buffer: *Buffer,
        semaphore_value: u64,
    ) void {
        alloc.queue.appendAssumeCapacity(.{
            .semaphore_value = semaphore_value,
            .buffer = buffer,
        });
    }

    /// semaphore_value should be the current value of the semaphore
    fn sweep(alloc: *BufferAllocator, semaphore_value: u64) !void {
        var i = alloc.queue.items.len;
        while (i > 0) {
            if (semaphore_value >= alloc.queue.items[i - 1].semaphore_value) {
                const buffer = alloc.queue.items[i - 1].buffer;
                buffer.slab.allocator.free(buffer.allocation);
                alloc.pool.destroy(buffer);
                alloc.counter -= 1;
                _ = alloc.queue.swapRemove(i - 1);
            }
            i -= 1;
        }
    }

    fn addSlab(allocator: *BufferAllocator) !void {
        // TODO ensure that the slab size is within supported limits
        const buffer_info: vk.BufferCreateInfo = .{
            .size = Slab.slab_size,
            .flags = .{ .device_address_capture_replay = allocator.ctx.config.enable_debug },
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
                .storage_buffer = true,
                .index_buffer = true,
                .indirect_buffer = true,
                .shader_device_address = true,
            },
            .sharing_mode = .exclusive,
            .p_queue_family_indices = @ptrCast(&allocator.ctx.graphics_queue.family),
            .queue_family_index_count = 1,
        };
        const device_buffer = try allocator.ctx.device.createBuffer(&buffer_info, null);
        errdefer allocator.ctx.device.destroyBuffer(device_buffer, null);

        if (allocator.ctx.config.enable_debug) {
            try allocator.ctx.device.setDebugUtilsObjectNameEXT(&.{
                .object_type = .buffer,
                .object_handle = @backingInt(device_buffer),
                .p_object_name = "BUFFER_ALLOCATOR_SLAB",
            });
        }

        var dedicated_memreq: vk.MemoryDedicatedRequirements = .{
            .prefers_dedicated_allocation = .false,
            .requires_dedicated_allocation = .false,
        };
        var buffer_memreq: vk.MemoryRequirements2 = .{
            .p_next = &dedicated_memreq,
            .memory_requirements = undefined,
        };
        allocator.ctx.device.getBufferMemoryRequirements2(&.{
            .buffer = device_buffer,
        }, &buffer_memreq);
        buffer_memreq.memory_requirements.alignment = @max(
            buffer_memreq.memory_requirements.alignment,
            Slab.granularity,
        );

        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999999;

        const memory_types = allocator.ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = allocator.ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (buffer_memreq.memory_requirements.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local) score += 1;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }
        std.debug.assert(best_score != -999999);

        const dedicated_info: vk.MemoryDedicatedAllocateInfo = .{
            .buffer = device_buffer,
        };
        const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
            .device_mask = 0,
            .p_next = &dedicated_info,
            .flags = .{
                .device_address = true,
                .device_address_capture_replay = allocator.ctx.config.enable_debug,
            },
        };
        const memory = try allocator.ctx.device.allocateMemory(&.{
            .allocation_size = buffer_memreq.memory_requirements.size,
            .memory_type_index = memory_type_index,
            .p_next = &alloc_flags,
        }, null);
        errdefer allocator.ctx.device.freeMemory(memory, null);
        try allocator.ctx.device.bindBufferMemory(device_buffer, memory, 0);

        const device_address = allocator.ctx.device.getBufferDeviceAddress(&.{
            .buffer = device_buffer,
        });

        const slab = try allocator.slabs.addOne(allocator.ctx.gpa);
        errdefer _ = allocator.slabs.pop();
        slab.* = .{
            .memory = memory,
            .allocator = try .init(
                allocator.ctx.gpa,
                Slab.slab_size / Slab.granularity,
                Slab.slab_size / Slab.granularity,
            ),
            .buffer = device_buffer,
            .device_address = device_address,
        };
    }
};

const TextureAllocator = struct {
    const Slab = struct {
        const slab_size = 256 * 1024 * 1024;
        const granularity = 64;

        memory_type_index: u32,
        allocator: OffsetAllocator,
        memory: vk.DeviceMemory,
    };

    const Deferred = struct {
        semaphore_value: u64,
        texture: *Texture,
    };

    ctx: *Context,
    slabs: std.ArrayList(Slab),
    slots: SlotPool,
    texture_pool: std.heap.MemoryPool(Texture),
    view_pool: std.heap.MemoryPool(View),
    queue: std.ArrayList(Deferred),
    counter: u32,

    fn init(ctx: *Context) !TextureAllocator {
        return .{
            .ctx = ctx,
            .slabs = .empty,
            .slots = try .init(ctx.gpa, 256 * 1024),
            .texture_pool = .empty,
            .view_pool = .empty,
            .queue = .empty,
            .counter = 0,
        };
    }

    fn deinit(alloc: *TextureAllocator) void {
        for (alloc.slabs.items) |*slab| {
            alloc.ctx.device.freeMemory(slab.memory, null);
            slab.allocator.deinit(alloc.ctx.gpa);
        }
        alloc.slabs.deinit(alloc.ctx.gpa);
        alloc.slots.deinit(alloc.ctx.gpa);
        alloc.texture_pool.deinit(alloc.ctx.gpa);
        alloc.view_pool.deinit(alloc.ctx.gpa);
        alloc.queue.deinit(alloc.ctx.gpa);
        alloc.* = undefined;
    }

    fn create(alloc: *TextureAllocator, create_info: rhi.TextureCreateInfo) !*Texture {
        // TODO validation of create_info

        const multiformat: bool = blk: {
            const base_format = create_info.format;
            for (create_info.views) |view| {
                if (view.format) |format| {
                    if (format != base_format) break :blk true;
                }
            }
            break :blk false;
        };
        const arrayview: bool = blk: {
            if (create_info.texture_type != .texture_3d) break :blk false;
            for (create_info.views) |view| {
                if (view.view_type == .view_2d_array) break :blk true;
            }
            break :blk false;
        };
        const depth_stencil_format: bool = switch (create_info.format) {
            .s8_uint,
            .d16_unorm,
            .d24_unorm_s8_uint,
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            => true,
            else => false,
        };
        const color_attachment = create_info.usage.attachment and !depth_stencil_format;
        const depth_stencil_attachment = create_info.usage.attachment and depth_stencil_format;

        const image_info: vk.ImageCreateInfo = .{
            .flags = .{
                .mutable_format = multiformat,
                .cube_compatible = create_info.texture_type == .texture_cube or
                    create_info.texture_type == .texture_cube_array,
                .@"2d_array_compatible" = arrayview,
            },
            .image_type = vulkanImageType(create_info.texture_type),
            .format = vulkanFormat(create_info.format),
            .extent = .{
                .width = create_info.size[0],
                .height = create_info.size[1],
                .depth = if (create_info.texture_type == .texture_3d)
                    create_info.size[2]
                else
                    1,
            },
            .mip_levels = create_info.mip_levels,
            .array_layers = if (create_info.texture_type == .texture_3d)
                1
            else
                create_info.size[2],
            .samples = vulkanSampleCount(create_info.samples),
            .tiling = .optimal,
            .usage = .{
                .storage = create_info.usage.storage,
                .sampled = create_info.usage.sampled,
                .transfer_src = create_info.usage.transfer_src,
                .transfer_dst = create_info.usage.transfer_dst,
                .color_attachment = color_attachment,
                .depth_stencil_attachment = depth_stencil_attachment,
            },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        };
        const image = try alloc.ctx.device.createImage(&image_info, null);
        errdefer alloc.ctx.device.destroyImage(image, null);

        if (alloc.ctx.config.enable_debug) {
            try alloc.ctx.device.setDebugUtilsObjectNameEXT(&.{
                .object_type = .image,
                .object_handle = @backingInt(image),
                .p_object_name = create_info.name,
            });
        }

        var dedicated_memreq: vk.MemoryDedicatedRequirements = .{
            .prefers_dedicated_allocation = .false,
            .requires_dedicated_allocation = .false,
        };
        var image_memreq: vk.MemoryRequirements2 = .{
            .p_next = &dedicated_memreq,
            .memory_requirements = undefined,
        };
        alloc.ctx.device.getImageMemoryRequirements2(&.{
            .image = image,
        }, &image_memreq);
        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999999;
        const memory_types = alloc.ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = alloc.ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (image_memreq.memory_requirements.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local) score += 1;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }
        std.debug.assert(best_score != -999999);

        var texture = try alloc.texture_pool.create(alloc.ctx.gpa);
        errdefer alloc.texture_pool.destroy(texture);
        texture.image = image;

        if (dedicated_memreq.requires_dedicated_allocation == .true or
            (dedicated_memreq.prefers_dedicated_allocation == .true and
                create_info.usage.attachment == true) or
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
            const memory = try alloc.ctx.device.allocateMemory(&.{
                .allocation_size = image_memreq.memory_requirements.size,
                .memory_type_index = memory_type_index,
                .p_next = &alloc_flags,
            }, null);
            errdefer alloc.ctx.device.freeMemory(memory, null);
            try alloc.ctx.device.bindImageMemory(image, memory, 0);

            texture.memory = .{ .dedicated = memory };
        } else {
            // slab allocation
            const size = if (image_memreq.memory_requirements.alignment <= Slab.granularity)
                image_memreq.memory_requirements.size
            else
                image_memreq.memory_requirements.size + image_memreq.memory_requirements.alignment;
            const suballoc = try alloc.suballocate(memory_type_index, size);
            try alloc.ctx.device.bindImageMemory(
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
            .view_type = vulkanImageViewType(create_info.texture_type),
            .format = vulkanFormat(create_info.format),
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .base_mip_level = 0,
                .level_count = create_info.mip_levels,
                .base_array_layer = 0,
                .layer_count = create_info.size[2],
                .aspect_mask = switch (create_info.format) {
                    .s8_uint => .{ .stencil = true },
                    .d16_unorm,
                    .d24_unorm_s8_uint,
                    .d32_sfloat,
                    .d32_sfloat_s8_uint,
                    => .{ .depth = true },
                    else => .{ .color = true },
                },
            },
        };
        const default_view = try alloc.ctx.device.createImageView(&default_view_info, null);
        errdefer alloc.ctx.device.destroyImageView(default_view, null);

        const default_view_slot = try alloc.slots.acquire();
        errdefer alloc.slots.release(default_view_slot);

        const default_view_2 = try alloc.view_pool.create(alloc.ctx.gpa);
        errdefer alloc.view_pool.destroy(default_view_2);
        default_view_2.* = .{
            .public = .{
                .device_address = @intCast(default_view_slot),
                .texture = &texture.public,
                .info = .{
                    .view_type = switch (create_info.texture_type) {
                        .texture_2d => .view_2d,
                        .texture_3d => .view_3d,
                        .texture_cube => .view_cube,
                        .texture_2d_array => .view_2d_array,
                        .texture_cube_array => .view_cube_array,
                    },
                    .format = create_info.format,
                    .swizzle = .{},
                    .range = .{
                        .base_mip_level = 0,
                        .level_count = create_info.mip_levels,
                        .base_array_layer = 0,
                        .layer_count = if (create_info.texture_type == .texture_3d)
                            1
                        else
                            create_info.size[2],
                    },
                    .name = &.{},
                },
            },
            .view = default_view,
        };
        texture.public.default_view = &default_view_2.public;

        const descriptor_image_info: vk.DescriptorImageInfo = .{
            .sampler = .null,
            .image_view = default_view,
            .image_layout = .shader_read_only_optimal,
        };
        const write_descriptor_set: vk.WriteDescriptorSet = .{
            .dst_set = alloc.ctx.descriptor_set,
            .dst_binding = 0,
            .dst_array_element = default_view_slot,
            .descriptor_count = 1,
            .descriptor_type = .sampled_image,
            .p_image_info = @ptrCast(&descriptor_image_info),
        };
        alloc.ctx.device.updateDescriptorSets(&.{write_descriptor_set}, null);

        alloc.counter += 1;
        errdefer alloc.counter -= 1;
        try alloc.queue.ensureUnusedCapacity(alloc.ctx.gpa, alloc.counter);

        if (create_info.group) |group| {
            _ = group;
            @panic("TODO");
        } else {
            const group = try alloc.ctx.group_pool.create(alloc.ctx.gpa);
            group.* = .{
                .public = .{
                    .info = .{ .name = &.{} },
                },
                .managed = true,
                // .last_used = .{},
                // .textures = .empty,
                // .buffer_count = 0,
                // .texture_state = .{
                //     .owner = null,
                //     .layout = .undefined,
                // },
                // .texture_state_overrides = .empty,
                // .last_write_epoch = 0,
                // .last_write_stage_mask = .{},
                // .last_read_epoch = 0,
                // .last_read_stage_mask = .{},
            };
            texture.public.group = &group.public;
        }
        // FIXME cleanup of group is very hard on errdefer, so don't have errors after it

        // TODO create the other views

        texture.public.info = .{
            .usage = create_info.usage,
            .size = create_info.size,
            .format = create_info.format,
            .mip_levels = create_info.mip_levels,
            .sample_count = create_info.samples,
            .texture_type = create_info.texture_type,
            .name = create_info.name,
        };
        texture.public.views = &.{};

        return texture;
    }

    /// semaphore_value should be the value when the final use is done
    fn queueDestroy(alloc: *TextureAllocator, texture: *Texture, semaphore_value: u64) void {
        alloc.queue.appendAssumeCapacity(.{
            .semaphore_value = semaphore_value,
            .texture = texture,
        });
    }

    fn sweep(alloc: *TextureAllocator, semaphore_value: u64) void {
        var i = alloc.queue.items.len;
        std.debug.print("{}\n", .{i});
        while (i > 0) {
            if (semaphore_value >= alloc.queue.items[i - 1].semaphore_value) {
                const texture = alloc.queue.items[i - 1].texture;
                switch (texture.memory) {
                    .slab => |suballoc| {
                        suballoc.slab.allocator.free(suballoc.allocation);
                    },
                    .dedicated => |memory| {
                        alloc.ctx.device.freeMemory(memory, null);
                    },
                }
                const view: *View = @alignCast(@constCast(
                    @fieldParentPtr("public", texture.public.default_view),
                ));
                // TODO non-default views
                alloc.ctx.device.destroyImageView(view.view, null);
                alloc.ctx.device.destroyImage(texture.image, null);
                alloc.texture_pool.destroy(texture);
                alloc.view_pool.destroy(view);
                alloc.counter -= 1;
                _ = alloc.queue.swapRemove(i - 1);
            }
            i -= 1;
        }
    }

    fn suballocate(alloc: *TextureAllocator, memory_type_index: u32, size: u64) !struct {
        allocation: OffsetAllocation,
        slab: *Slab,
    } {
        const granule_size: u32 = @intCast((size + Slab.granularity - 1) / Slab.granularity);

        for (alloc.slabs.items) |*slab| {
            if (slab.memory_type_index != memory_type_index) continue;
            const allocation = slab.allocator.allocate(granule_size) catch continue;
            return .{
                .allocation = allocation,
                .slab = slab,
            };
        }

        // no allocation possible with extant slabs, make a new one
        const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
            .flags = .{},
            .device_mask = 0,
        };
        const memory = try alloc.ctx.device.allocateMemory(&.{
            .allocation_size = Slab.slab_size,
            .memory_type_index = memory_type_index,
            .p_next = &alloc_flags,
        }, null);
        errdefer alloc.ctx.device.freeMemory(memory, null);

        const slab = try alloc.slabs.addOne(alloc.ctx.gpa);
        errdefer _ = alloc.slabs.pop();
        slab.* = .{
            .memory_type_index = memory_type_index,
            .memory = memory,
            .allocator = try .init(
                alloc.ctx.gpa,
                Slab.slab_size / Slab.granularity,
                Slab.slab_size / Slab.granularity,
            ),
        };

        const allocation = try slab.allocator.allocate(granule_size);
        return .{
            .slab = slab,
            .allocation = allocation,
        };
    }
};

const StagingAllocator = struct {
    const min_granularity = 64;

    ctx: *Context,
    granularity: usize,
    memory: vk.DeviceMemory,
    mapped_memory: []u8,
    buffer: vk.Buffer,
    allocator: OffsetAllocator,
    allocations: []OffsetAllocation,

    fn init(ctx: *Context, usage: rhi.StagingAllocatorUsage) !StagingAllocator {
        const granularity = @max(
            switch (usage) {
                .upload => 1,
                .download => ctx.physical_device_properties.limits.non_coherent_atom_size,
            },
            ctx.physical_device_properties.limits.optimal_buffer_copy_offset_alignment,
            min_granularity,
        );
        const size = switch (usage) {
            .upload => ctx.config.upload_staging_size,
            .download => ctx.config.download_staging_size,
        };
        const granule_size: u32 = @intCast((size + granularity - 1) / granularity);

        const buffer = try ctx.device.createBuffer(&.{
            .size = size,
            .usage = .{
                .transfer_src = usage == .upload,
                .transfer_dst = usage == .download,
            },
            .sharing_mode = .exclusive,
            .p_queue_family_indices = @ptrCast(&ctx.graphics_queue.family),
            .queue_family_index_count = 1,
        }, null);
        errdefer ctx.device.destroyBuffer(buffer, null);

        if (ctx.config.enable_debug) {
            try ctx.device.setDebugUtilsObjectNameEXT(&.{
                .object_type = .buffer,
                .object_handle = @backingInt(buffer),
                .p_object_name = switch (usage) {
                    .upload => "UPLOAD_STAGING_BUFFER",
                    .download => "DOWNLOAD_STAGING_BUFFER",
                },
            });
        }

        var buffer_memreq = ctx.device.getBufferMemoryRequirements(buffer);
        buffer_memreq.alignment = @max(buffer_memreq.alignment, granularity);

        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999999;

        const memory_types = ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (buffer_memreq.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            if (!memory_type.property_flags.host_visible) continue;
            if (usage == .upload and !memory_type.property_flags.host_coherent) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local) score -= 1;
            if (usage == .download and memory_type.property_flags.host_coherent) score += 2;
            if (usage == .download and memory_type.property_flags.host_cached) score += 4;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }
        if (best_score == -999999) {
            log.err("{} StagingAllocator memory type unsupported", .{usage});
            return error.Unsupported;
        }

        const memory = try ctx.device.allocateMemory(&.{
            .allocation_size = size,
            .memory_type_index = memory_type_index,
        }, null);
        errdefer ctx.device.freeMemory(memory, null);

        try ctx.device.bindBufferMemory(buffer, memory, 0);
        const buffer_ptr: [*]u8 = @ptrCast((try ctx.device.mapMemory(memory, 0, size, .{})).?);

        const allocations = try ctx.gpa.alloc(OffsetAllocation, granule_size);
        errdefer ctx.gpa.free(allocations);

        return .{
            .ctx = ctx,
            .mapped_memory = buffer_ptr[0..size],
            .memory = memory,
            .buffer = buffer,
            .allocator = try .init(
                ctx.gpa,
                @intCast(size / granularity),
                @intCast(size / granularity),
            ),
            .allocations = allocations,
            .granularity = granularity,
        };
    }

    fn deinit(allocator: *StagingAllocator) void {
        allocator.ctx.device.destroyBuffer(allocator.buffer, null);
        allocator.ctx.device.freeMemory(allocator.memory, null);
        allocator.allocator.deinit(allocator.ctx.gpa);
        allocator.ctx.gpa.free(allocator.allocations);
        allocator.* = undefined;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const allocator: *StagingAllocator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;

        const granule_size: u32 = @intCast((len + allocator.granularity - 1) / allocator.granularity);

        if (alignment.toByteUnits() > allocator.granularity) {
            log.info("TODO: implement large alignment", .{});
            return null;
        }
        const allocation = allocator.allocator.allocate(granule_size) catch return null;
        const slot = allocation.offset;
        allocator.allocations[slot] = allocation;

        return allocator.mapped_memory[allocation.offset * allocator.granularity .. allocation.offset * allocator.granularity + len].ptr;
    }

    fn resize(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const allocator: *StagingAllocator = @ptrCast(@alignCast(ctx));
        _ = allocator;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        log.info("TODO: implement resize", .{});
        return false;
    }

    fn remap(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const allocator: *StagingAllocator = @ptrCast(@alignCast(ctx));
        _ = allocator;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        log.info("TODO: implement remap", .{});
        return null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const allocator: *StagingAllocator = @ptrCast(@alignCast(ctx));
        const allocation = allocator.allocations[
            (@intFromPtr(memory.ptr) - @intFromPtr(allocator.mapped_memory.ptr)) / allocator.granularity
        ];
        allocator.allocator.free(allocation);

        _ = alignment;
        _ = ret_addr;
    }
};

/// object pool that doesn't release items until their semaphore has passed
fn Depot(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            data: T,
            semaphore_value: u64,
        };

        gpa: std.mem.Allocator,
        data: std.ArrayList(Node),

        fn init(gpa: std.mem.Allocator) Self {
            return .{
                .gpa = gpa,
                .data = .empty,
            };
        }

        fn deinit(depot: *Self) void {
            depot.data.deinit(depot.gpa);
            depot.* = undefined;
        }

        /// semaphore value when the data will be safe to use again
        fn push(depot: *Self, data: T, semaphore_value: u64) !void {
            try depot.data.append(depot.gpa, .{
                .data = data,
                .semaphore_value = semaphore_value,
            });
        }

        /// current semaphore value
        fn pop(depot: *Self, semaphore_value: u64) ?T {
            for (depot.data.items, 0..) |data, i| {
                if (data.semaphore_value > semaphore_value) continue;
                return depot.data.swapRemove(i).data;
            }
            return null;
        }

        fn debugPrint(depot: *Self) void {
            std.debug.print("Depot <{s}> [ ", .{@typeName(T)});

            for (depot.data.items) |item| {
                std.debug.print("{} ", .{item});
            }
            std.debug.print("]\n", .{});
        }
    };
}

fn vulkanImageType(texture_type: rhi.TextureType) vk.ImageType {
    return switch (texture_type) {
        .texture_2d => .@"2d",
        .texture_3d => .@"3d",
        .texture_cube => .@"2d",
        .texture_2d_array => .@"2d",
        .texture_cube_array => .@"2d",
    };
}

fn vulkanImageViewType(texture_view_type: anytype) vk.ImageViewType {
    const T = @TypeOf(texture_view_type);
    if (T == rhi.TextureType) {
        return switch (texture_view_type) {
            .texture_2d => .@"2d",
            .texture_3d => .@"3d",
            .texture_cube => .cube,
            .texture_2d_array => .@"2d_array",
            .texture_cube_array => .cube_array,
        };
    }
    if (T == rhi.ViewType) {
        return switch (texture_view_type) {
            .view_2d => .@"2d",
            .view_3d => .@"3d",
            .view_cube => .cube,
            .view_2d_array => .@"2d_array",
            .view_cube_array => .cube_array,
        };
    }
    @compileError("vulkanImageViewType takes either an rhi.TextureType or an rhi.ViewType");
}

fn vulkanFormat(format: rhi.Format) vk.Format {
    return switch (format) {
        .r8g8b8a8_unorm => .r8g8b8a8_unorm,
        .r8g8b8a8_srgb => .r8g8b8a8_srgb,
        .r16g16b16a16_sfloat => .r16g16b16a16_sfloat,
        .r32_uint => .r32_uint,
        .s8_uint => .s8_uint,
        .d16_unorm => .d16_unorm,
        .d24_unorm_s8_uint => .d24_unorm_s8_uint,
        .d32_sfloat => .d32_sfloat,
        .d32_sfloat_s8_uint => .d32_sfloat_s8_uint,
    };
}

fn vulkanSampleCount(sample_count: rhi.SampleCount) vk.SampleCountFlags {
    return .{
        .@"1" = sample_count == .count_1,
        .@"2" = sample_count == .count_2,
        .@"4" = sample_count == .count_4,
        .@"8" = sample_count == .count_8,
        .@"16" = sample_count == .count_16,
    };
}
