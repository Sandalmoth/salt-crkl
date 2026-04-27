const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");
const log = std.log.scoped(.rhi_vulkan);

const MemoryPool = std.heap.MemoryPool;

fn Depot(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            data: T,
            queue: Queue,
            semaphore_value: u64,
        };

        const SyncPoint = struct {
            graphics: u64,
            compute: u64,
            transfer: u64,
            present: u64,
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

        fn push(depot: *Self, data: T, queue: Queue, semaphore_value: u64) !void {
            try depot.data.append(depot.gpa, .{
                .data = data,
                .queue = queue,
                .semaphore_value = semaphore_value,
            });
        }

        fn pop(depot: *Self, sync_point: SyncPoint) ?T {
            for (depot.data.items, 0..) |data, i| {
                switch (data.queue) {
                    .graphics => if (data.semaphore_value > sync_point.graphics) continue,
                    .compute => if (data.semaphore_value > sync_point.compute) continue,
                    .transfer => if (data.semaphore_value > sync_point.transfer) continue,
                    .present => if (data.semaphore_value > sync_point.present) continue,
                }
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
    enable_debug: bool =
        @import("builtin").mode == .Debug or
        @import("builtin").mode == .ReleaseSafe,
    enable_validation: bool = @import("builtin").mode == .Debug,
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

const Queue = enum(u16) {
    graphics,
    compute,
    transfer,
    present,
};

const PhysicalQueue = struct {
    queue: vk.QueueProxy,
    family: u32,
    semaphore: vk.Semaphore,
    value: u64,
};

const Fence = struct {
    graphics: ?u64,
    compute: ?u64,
    transfer: ?u64,
    present: ?u64,
};

const Group = struct {
    // NOTE this could be packed into a u32, or even smaller
    // but we'd have to either do some ugly masking on the layout
    // or map the layout to a continuous range
    const TextureState = packed struct(u64) {
        owned: bool,
        owner: Queue,
        layout: vk.ImageLayout,
        _padding: u15 = 0,
    };

    public: rhi.Group,

    texture_state: TextureState,
    texture_overrides: std.AutoArrayHashMapUnmanaged(*const Texture, TextureState),
};

const View = struct {
    public: rhi.View,
};

const Texture = struct {
    public: rhi.Texture,
    image: vk.Image,
    swapchain: bool, // is this a swapchain texture?

    fn group(texture: *Texture) *Group {
        return @ptrCast(@alignCast(@constCast(texture.public.group)));
    }
};

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

const Sampler = struct {
    public: rhi.Sampler,
};

const Shader = struct {
    public: rhi.Shader,
    stage: vk.ShaderStageFlags,
    module: vk.ShaderModule,
};

const GraphicsPipeline = struct {
    public: rhi.GraphicsPipeline,
};

const ComputePipeline = struct {
    public: rhi.ComputePipeline,
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

const Context = @This();

const vtable: rhi.Context.VTable = .{
    .createSwapchain = undefined,
    .destroySwapchain = undefined,
    .setSwapchainComposition = undefined,
    .setSwapchainPresentMode = undefined,
    .acquireSwapchain = undefined,
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
    .submit = undefined,
    .wait = undefined,
    .setBufferGroup = undefined,
    .setTextureGroup = undefined,
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
group_pool: MemoryPool(Group),
swapchain_pool: MemoryPool(Swapchain),
shader_pool: MemoryPool(Shader),
graphics_pipeline_pool: MemoryPool(GraphicsPipeline),
compute_pipeline_pool: MemoryPool(ComputePipeline),
buffer_pool: MemoryPool(Buffer),
texture_pool: MemoryPool(Texture),
sampler_pool: MemoryPool(Sampler),

// depots are for resources that are reused, not recreated
// command_buffer_depots: std.EnumArray(Queue, Depot(void)),
acquire_semaphore_depot: Depot(vk.Semaphore),

queues: std.EnumArray(Queue, *PhysicalQueue),

pub fn init(
    gpa: std.mem.Allocator,
    platform: Platform,
    config: Config,
    window: rhi.Window,
) !rhi.Context {
    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const ctx = try gpa.create(Context);
    errdefer gpa.destroy(ctx);

    ctx.gpa = gpa;
    ctx.platform = platform;
    ctx.config = config;
    ctx.base = .load(platform.getInstanceProcAddress);

    try ctx.initInstance(arena, platform, config);
    errdefer ctx.deinitInstance();
    const physical_device_candidate = try ctx.pickPhysicalDevice(arena, config, window);
    try ctx.initDevice(arena, physical_device_candidate);
    errdefer ctx.deinitDevice();
    try ctx.initPipelineLayout();
    errdefer ctx.deinitPipelineLayout();

    ctx.group_pool = .empty;
    ctx.shader_pool = .empty;
    ctx.graphics_pipeline_pool = .empty;
    ctx.compute_pipeline_pool = .empty;
    ctx.buffer_pool = .empty;
    ctx.texture_pool = .empty;
    ctx.sampler_pool = .empty;
    ctx.swapchain_pool = .empty;

    // ctx.command_buffer_depots = .initFill(.init(gpa));
    ctx.acquire_semaphore_depot = .init(gpa);

    // TODO init allocators

    return .{
        .ptr = ctx,
        .vtable = &vtable,
    };
}

pub fn deinit(rhi_ctx: rhi.Context) void {
    const ctx: *Context = @ptrCast(@alignCast(rhi_ctx.ptr));

    ctx.device.deviceWaitIdle() catch |e| {
        log.warn("Failed deviceWaitIdle in deinit: {}", .{e});
    };

    ctx.swapchain_pool.deinit(ctx.gpa);
    ctx.shader_pool.deinit(ctx.gpa);
    ctx.graphics_pipeline_pool.deinit(ctx.gpa);
    ctx.compute_pipeline_pool.deinit(ctx.gpa);
    ctx.buffer_pool.deinit(ctx.gpa);
    ctx.texture_pool.deinit(ctx.gpa);
    ctx.sampler_pool.deinit(ctx.gpa);
    ctx.group_pool.deinit(ctx.gpa);

    // for ([_]Queue{ .graphics, .compute, .transfer, .present }) |queue| {
    //     const depot = ctx.command_buffer_depots.getPtr(queue);
    //     log.debug("destroying {} {} queue command buffers", .{ depot.data.items.len, queue });
    //     for (depot.data.items) |item| {
    //         item.data.deinit();
    //         ctx.gpa.destroy(item.data);
    //     }
    //     depot.deinit();
    // }

    log.debug(
        "destroying {} queue acquire semaphores",
        .{ctx.acquire_semaphore_depot.data.items.len},
    );
    for (ctx.acquire_semaphore_depot.data.items) |item| {
        ctx.device.destroySemaphore(item.data, null);
    }
    ctx.acquire_semaphore_depot.deinit();

    var physical_queues: [4]?*PhysicalQueue = .{null} ** 4;
    outer: for ([_]Queue{ .graphics, .compute, .transfer, .present }, 0..) |queue, j| {
        for (0..4) |i| if (physical_queues[i] == ctx.queues.get(queue)) continue :outer;
        physical_queues[j] = ctx.queues.get(queue);
    }
    for (physical_queues[0..4]) |q| {
        const queue = q orelse continue;
        ctx.device.destroySemaphore(queue.semaphore, null);
        ctx.gpa.destroy(queue);
    }

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
    if (config.enable_validation) outer: for (debug_instance_extensions) |ext1| {
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
fn pickPhysicalDevice(
    ctx: *Context,
    arena: std.mem.Allocator,
    config: Config,
    window: ?rhi.Window,
) !PhysicalDeviceCandidate {
    const devices = try ctx.instance.enumeratePhysicalDevicesAlloc(arena);
    var candidates: std.ArrayList(PhysicalDeviceCandidate) =
        try .initCapacity(arena, devices.len);

    // construct a temporary surface used to identify devices that can present
    var surface: vk.SurfaceKHR = .null_handle;
    if (window) |w| surface = try ctx.platform.createWindowSurface(ctx.instance.handle, w);
    defer if (surface != .null_handle) ctx.instance.destroySurfaceKHR(surface, null);

    for (devices) |dev| {
        const candidate: PhysicalDeviceCandidate =
            try .init(arena, ctx.instance, dev, surface);
        const name = std.mem.sliceTo(&candidate.properties.device_name, 0);

        if (!try candidate.checkExtensionSupport(arena, ctx.instance, config)) {
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
        std.debug.assert(candidate.queue_families.contains(.present));

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
        physical_queue.semaphore = ctx.device.createSemaphore(&.{
            .p_next = &vk.SemaphoreTypeCreateInfo{
                .semaphore_type = .timeline,
                .initial_value = 0,
            },
        }, null) catch return error.Unknown;

        // then assign it to all queues that share that family
        for ([3]Queue{ .graphics, .compute, .transfer }) |queue| {
            if (candidate.queue_families.getAssertContains(queue) == queue_family_index) {
                ctx.queues.set(queue, physical_queue);
            }
        }
    }

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
        // present queue should preferably be same as graphics
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
            if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                candidate.device,
                @intCast(i),
                surface,
            ) != .true) continue;
            candidate.queue_families.put(.graphics, @intCast(i));
            candidate.queue_families.put(.present, @intCast(i));
            break;
        }

        // no graphics + present
        if (candidate.queue_families.get(.graphics) == null) {
            // select graphics
            for (queue_families, 0..) |family, i| {
                if (!family.queue_flags.graphics_bit) continue;
                candidate.queue_families.put(.graphics, @intCast(i));
                break;
            }
            // select present
            for (queue_families, 0..) |_, i| {
                if (try instance.getPhysicalDeviceSurfaceSupportKHR(
                    candidate.device,
                    @intCast(i),
                    surface,
                ) != .true) continue;
                candidate.queue_families.put(.present, @intCast(i));
                break;
            }
        }

        // no transfer, select compute if compute exists
        if (candidate.queue_families.get(.compute)) |compute_queue_family| {
            if (!candidate.queue_families.contains(.transfer)) {
                candidate.queue_families.put(.transfer, compute_queue_family);
            }
        }

        // no transfer or compute, select graphics if graphics exists
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
