const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");
const log = std.log.scoped(.rhi_vulkan);

const MemoryPool = std.heap.MemoryPool;
const OffsetAllocator = @import("OffsetAllocator.zig").Allocator;
const Allocation = @import("OffsetAllocator.zig").Allocation;

const SyncPoint = struct {
    graphics: u64,
    compute: u64,
    transfer: u64,
    present: u64,
};

fn Depot(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            data: T,
            queue: Queue,
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

/// like std.EnumArray but two dimensional
fn EnumMatrix(comptime A: type, comptime B: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const AIndexer = std.enums.EnumIndexer(A);
        const BIndexer = std.enums.EnumIndexer(B);

        values: [AIndexer.count * BIndexer.count]T,

        fn initFill(value: T) Self {
            return .{ .values = @splat(value) };
        }

        fn get(matrix: Self, a: A, b: B) T {
            return matrix.values[AIndexer.indexOf(a) + AIndexer.count * BIndexer.indexOf(b)];
        }

        fn set(matrix: *Self, a: A, b: B, value: T) void {
            matrix.values[AIndexer.indexOf(a) + AIndexer.count * BIndexer.indexOf(b)] = value;
        }
    };
}

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

const Queue = enum {
    graphics,
    compute,
    transfer,
    present,

    fn fromRhi(rhi_queue: rhi.Queue) Queue {
        return switch (rhi_queue) {
            .graphics => .graphics,
            .compute => .compute,
            .transfer => .transfer,
        };
    }
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

    const never = Fence{
        .graphics = null,
        .compute = null,
        .transfer = null,
        .present = null,
    };
};

const CommandPool = struct {
    pool: vk.CommandPool,
    prefix: vk.CommandBuffer,
    body: vk.CommandBuffer,
    suffix: vk.CommandBuffer,
};

const Stage = enum {
    vertex,
    fragment,
    compute,
    tranfer,
};

fn vulkanImageType(texture_type: rhi.TextureType) vk.ImageType {
    return switch (texture_type) {
        .type_2d => .@"2d",
        .type_3d => .@"3d",
        .type_cube => .@"2d",
        .type_2d_array => .@"2d",
        .type_cube_array => .@"2d",
    };
}

fn vulkanImageViewType(texture_view_type: anytype) vk.ImageViewType {
    const T = @TypeOf(texture_view_type);
    if (T == rhi.TextureType) {
        return switch (texture_view_type) {
            .type_2d => .@"2d",
            .type_3d => .@"3d",
            .type_cube => .cube,
            .type_2d_array => .@"2d_array",
            .type_cube_array => .cube_array,
        };
    }
    if (T == rhi.ViewType) {
        return switch (texture_view_type) {
            .type_2d => .@"2d",
            .type_3d => .@"3d",
            .type_cube => .cube,
            .type_2d_array => .@"2d_array",
            .type_cube_array => .cube_array,
        };
    }
    @compileError("vulkanImageViewType takes either an rhi.TextureType or an rhi.ViewType");
}

fn vulkanFormat(format: rhi.Format) vk.Format {
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

fn vulkanSampleCount(sample_count: rhi.SampleCount) vk.SampleCountFlags {
    return .{
        .@"1_bit" = sample_count == .count_1,
        .@"2_bit" = sample_count == .count_2,
        .@"4_bit" = sample_count == .count_4,
        .@"8_bit" = sample_count == .count_8,
        .@"16_bit" = sample_count == .count_16,
        .@"32_bit" = sample_count == .count_32,
        .@"64_bit" = sample_count == .count_64,
    };
}

fn vulkanStage(stage: rhi.Stage) vk.ShaderStageFlags {
    return switch (stage) {
        .vertex => .{ .vertex_bit = true },
        .fragment => .{ .fragment_bit = true },
        .compute => .{ .compute_bit = true },
    };
}

fn vulkanColorWriteMask(mask: rhi.ColorWriteMask) vk.ColorComponentFlags {
    return .{
        .r_bit = mask.r,
        .g_bit = mask.g,
        .b_bit = mask.b,
        .a_bit = mask.a,
    };
}

fn vulkanBlendFactor(blend_factor: rhi.BlendFactor) vk.BlendFactor {
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

fn vulkanBlendOp(blend_op: rhi.BlendOp) vk.BlendOp {
    return switch (blend_op) {
        .add => .add,
        .subtract => .subtract,
        .reverse_subtract => .reverse_subtract,
        .min => .min,
        .max => .max,
    };
}

fn vulkanPolygonMode(polygon_mode: rhi.PolygonMode) vk.PolygonMode {
    return switch (polygon_mode) {
        .fill => .fill,
        .line => .line,
        .point => .point,
    };
}

const Group = struct {
    const TextureState = struct {
        owner: ?Queue,
        layout: vk.ImageLayout,
    };

    public: rhi.Group,

    texture_state: TextureState,
    texture_state_overrides: std.AutoArrayHashMapUnmanaged(*Texture, TextureState),

    last_used: Fence,

    textures: std.AutoArrayHashMapUnmanaged(*Texture, void),
    buffers: std.AutoArrayHashMapUnmanaged(*Buffer, void),
    // buffers could actually be just a refcount since we don't need to do anything to them

    last_write_epoch: u64,
    last_write_stage_mask: std.EnumSet(Stage),
    last_read_epoch: u64,
    last_read_stage_mask: std.EnumSet(Stage),
};

const View = struct {
    public: rhi.View,
    view: vk.ImageView,
};

const Texture = struct {
    public: rhi.Texture,
    memory: union(enum) {
        slab: struct {
            allocation: Allocation,
            slab: *TextureAllocator.Slab,
        },
        dedicated: vk.DeviceMemory,
    },
    image: vk.Image,

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
    module: vk.ShaderModule,
};

const GraphicsPipeline = struct {
    public: rhi.GraphicsPipeline,
    pipeline: vk.Pipeline,
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
    image_index: ?u32,
    acquire_semaphore: vk.Semaphore,
};

const Context = @This();

const vtable: rhi.Context.VTable = .{
    .createSwapchain = createSwapchain,
    .destroySwapchain = destroySwapchain,
    .createBuffer = undefined,
    .createTexture = createTexture,
    .createSampler = undefined,
    .createShader = createShader,
    .createGroup = undefined,
    .createGraphicsPipeline = createGraphicsPipeline,
    .createComputePipeline = undefined,
    .destroyBuffer = undefined,
    .destroyTexture = queueDestroyTexture,
    .destroySampler = undefined,
    .destroyShader = destroyShader,
    .destroyGroup = undefined,
    .destroyGraphicsPipeline = queueDestroyGraphicsPipeline,
    .destroyComputePipeline = undefined,
    .stagingAllocator = undefined,
    .submit = submit,
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
view_pool: MemoryPool(View),

// depots are for resources that are reused, not recreated
command_pool_depots: std.EnumArray(Queue, Depot(CommandPool)),
acquire_semaphore_depot: Depot(vk.Semaphore),

queues: std.EnumArray(Queue, *PhysicalQueue),

texture_allocator: TextureAllocator,

syncronization_epoch: u64,
visibility_map: EnumMatrix(Stage, Stage, u64),

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
    ctx.view_pool = .empty;

    ctx.command_pool_depots = .initFill(.init(gpa));
    ctx.acquire_semaphore_depot = .init(gpa);

    // TODO init all allocators
    ctx.texture_allocator = try .init(ctx);
    errdefer ctx.texture_allocator.deinit();

    ctx.syncronization_epoch = 0;
    ctx.visibility_map = .initFill(0);

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

    ctx.texture_allocator.deinit();

    ctx.view_pool.deinit(ctx.gpa);
    ctx.swapchain_pool.deinit(ctx.gpa);
    ctx.shader_pool.deinit(ctx.gpa);
    ctx.graphics_pipeline_pool.deinit(ctx.gpa);
    ctx.compute_pipeline_pool.deinit(ctx.gpa);
    ctx.buffer_pool.deinit(ctx.gpa);
    ctx.texture_pool.deinit(ctx.gpa);
    ctx.sampler_pool.deinit(ctx.gpa);
    ctx.group_pool.deinit(ctx.gpa);

    for ([_]Queue{ .graphics, .compute, .transfer, .present }) |queue| {
        const depot = ctx.command_pool_depots.getPtr(queue);
        log.debug("destroying {} {} queue command pools", .{ depot.data.items.len, queue });
        for (depot.data.items) |item| {
            const buffers: [3]vk.CommandBuffer = .{
                item.data.prefix,
                item.data.body,
                item.data.suffix,
            };
            ctx.device.freeCommandBuffers(item.data.pool, &buffers);
            ctx.device.destroyCommandPool(item.data.pool, null);
        }
        depot.deinit();
    }

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
        }, .state = .{
            .acquired = false,
            .composition = .sdr,
            .present_mode = .fifo,
            .size = .{ 0, 0, 0 },
        } },
        .surface = surface,
        .window = create_info.window,
        .swapchain = .null_handle,
        .images = &.{},
        .views = &.{},
        .release_semaphores = &.{},
        .image_index = null,
        .acquire_semaphore = .null_handle,
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

    if (swapchain.swapchain != .null_handle) {
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

    std.debug.assert(!swapchain.public.state.acquired);

    if (swapchain.swapchain == .null_handle) {
        try ctx.recreateSwapchain(swapchain);
    }

    ctx.acquire_semaphore_depot.debugPrint();
    const acquire_semaphore = ctx.acquire_semaphore_depot.pop(.{
        .graphics = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.graphics).semaphore),
        .compute = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.compute).semaphore),
        .transfer = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.transfer).semaphore),
        .present = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.present).semaphore),
    }) orelse
        ctx.device.createSemaphore(&.{}, null) catch return false;
    // FIXME if we return early, this needs to be pushed

    const result = ctx.device.acquireNextImageKHR(
        swapchain.swapchain,
        timeout,
        acquire_semaphore,
        .null_handle,
    ) catch |e| switch (e) {
        error.OutOfDateKHR => vk.DeviceWrapper.AcquireNextImageKHRResult{
            .result = .error_out_of_date_khr,
            .image_index = undefined,
        },
        else => return e,
    };
    std.debug.print("{}\n", .{result});
    switch (result.result) {
        .success => {
            swapchain.public.state.acquired = true;
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

    return swapchain.public.state.acquired;
}

fn createTexture(
    ptr: *anyopaque,
    create_info: rhi.TextureCreateInfo,
) rhi.Context.Error!*const rhi.Texture {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const texture = try ctx.texture_allocator.createTexture(create_info);
    std.debug.print("fun {*}\n", .{texture});
    std.debug.print("fun {}\n", .{texture});
    std.debug.print("fun {}\n", .{texture.public});
    std.debug.print("fun {*}\n", .{&texture.public});
    return &texture.public;
}

fn queueDestroyTexture(ptr: *anyopaque, rhi_texture: *const rhi.Texture) void {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const texture: *Texture = @alignCast(@constCast(
        @fieldParentPtr("public", rhi_texture),
    ));

    std.debug.print("destroying {}\n", .{texture.*});

    _ = ctx;
    // _ = texture;
}

fn createShader(
    ptr: *anyopaque,
    create_info: rhi.ShaderCreateInfo,
) rhi.Context.Error!*const rhi.Shader {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    std.debug.assert(@intFromPtr(create_info.src.ptr) % 4 == 0); // SPIR-V alignment requirement
    const shader = try ctx.shader_pool.create(ctx.gpa);
    errdefer ctx.shader_pool.destroy(shader);
    shader.* = .{
        .public = .{
            .info = .{
                .stage = create_info.stage,
                .name = create_info.name,
            },
        },
        .module = try ctx.device.createShaderModule(&.{
            .code_size = create_info.src.len,
            .p_code = @ptrCast(@alignCast(create_info.src.ptr)),
        }, null),
    };
    return &shader.public;
}

fn destroyShader(
    ptr: *anyopaque,
    rhi_shader: *const rhi.Shader,
) void {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const shader: *Shader = @alignCast(@constCast(@fieldParentPtr("public", rhi_shader)));
    ctx.device.destroyShaderModule(shader.module, null);
    ctx.shader_pool.destroy(shader);
}

pub fn createGraphicsPipeline(
    ptr: *anyopaque,
    create_info: rhi.GraphicsPipelineCreateInfo,
) rhi.Context.Error!*const rhi.GraphicsPipeline {
    const ctx: *Context = @ptrCast(@alignCast(ptr));
    const pipeline = try ctx.graphics_pipeline_pool.create(ctx.gpa);
    errdefer ctx.graphics_pipeline_pool.destroy(pipeline);

    // TODO handle fragment-shader-free pipelines
    const vertex_shader: *Shader = @alignCast(@constCast(
        @fieldParentPtr("public", create_info.vertex_shader),
    ));
    const fragment_shader: *Shader = @alignCast(@constCast(
        @fieldParentPtr("public", create_info.fragment_shader.?),
    ));
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ .{
        .stage = vulkanStage(vertex_shader.public.info.stage),
        .module = vertex_shader.module,
        .p_name = "main",
    }, .{
        .stage = vulkanStage(fragment_shader.public.info.stage),
        .module = fragment_shader.module,
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
        .depth_bias_enable,
        .primitive_restart_enable,
    };

    // TODO probably better to have a reusable arena in Context
    var arena_impl: std.heap.ArenaAllocator = .init(ctx.gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const color_attachment_formats = try arena.alloc(
        vk.Format,
        create_info.color_attachments.len,
    );
    const color_blend_attachments = try arena.alloc(
        vk.PipelineColorBlendAttachmentState,
        create_info.color_attachments.len,
    );
    for (create_info.color_attachments, 0..) |color_attachment, i| {
        color_attachment_formats[i] = vulkanFormat(color_attachment.format);
        var cba = std.mem.zeroes(vk.PipelineColorBlendAttachmentState);
        cba.color_write_mask = vulkanColorWriteMask(color_attachment.color_write_mask);
        if (color_attachment.blend_state) |blend_state| {
            cba.blend_enable = .true;
            cba.src_color_blend_factor = vulkanBlendFactor(blend_state.src_color_blend_factor);
            cba.dst_color_blend_factor = vulkanBlendFactor(blend_state.dst_color_blend_factor);
            cba.color_blend_op = vulkanBlendOp(blend_state.color_blend_op);
            cba.src_alpha_blend_factor = vulkanBlendFactor(blend_state.src_alpha_blend_factor);
            cba.dst_alpha_blend_factor = vulkanBlendFactor(blend_state.dst_alpha_blend_factor);
            cba.alpha_blend_op = vulkanBlendOp(blend_state.alpha_blend_op);
        }
        color_blend_attachments[i] = cba;
    }

    const dynamic_rendering: vk.PipelineRenderingCreateInfo = .{
        .color_attachment_count = @intCast(color_attachment_formats.len),
        .p_color_attachment_formats = if (color_attachment_formats.len > 0) @ptrCast(&color_attachment_formats[0]) else null,
        .depth_attachment_format = if (create_info.depth_attachment_format) |format| vulkanFormat(format) else .undefined,
        .stencil_attachment_format = if (create_info.stencil_attachment_format) |format| vulkanFormat(format) else .undefined,
        .view_mask = 0, // multiview is not supported
    };

    const pipeline_create_info: vk.GraphicsPipelineCreateInfo = .{
        .stage_count = @intCast(shader_stages.len),
        .p_stages = @ptrCast(&shader_stages[0]),
        .p_viewport_state = &.{
            .viewport_count = 1, // multiple viewports are not supported
            .scissor_count = 1, // multiple viewports are not supported
        },
        .p_rasterization_state = &.{
            .depth_clamp_enable = .false, // depth clamp not supported
            .rasterizer_discard_enable = .false,
            .polygon_mode = vulkanPolygonMode(create_info.polygon_mode),
            .line_width = 1.0,
            .cull_mode = .{ .back_bit = true },
            .front_face = .counter_clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
        },
        .p_multisample_state = &.{
            .rasterization_samples = vulkanSampleCount(create_info.multisample.sample_count),
            .sample_shading_enable = .false, // sample shading not supported
            .min_sample_shading = 1.0, // sample shading not supported
            .p_sample_mask = null, // sample mask not supported
            .alpha_to_coverage_enable = if (create_info.multisample.enable_alpha_to_coverage) .true else .false,
            .alpha_to_one_enable = .false, // alpha to one not supported
        },
        .p_depth_stencil_state = &.{
            .depth_test_enable = .false,
            .depth_write_enable = .false,
            .depth_compare_op = .never,
            .depth_bounds_test_enable = .false, // depth boudns not supported
            .stencil_test_enable = .false,
            .front = std.mem.zeroes(vk.StencilOpState),
            .back = std.mem.zeroes(vk.StencilOpState),
            .min_depth_bounds = 0.0, // depth boudns not supported
            .max_depth_bounds = 0.0, // depth boudns not supported
        },
        .p_color_blend_state = &.{
            .logic_op_enable = .false, // logic op is not supported
            .logic_op = .clear, // logic op is not supported
            .attachment_count = @intCast(color_blend_attachments.len),
            .p_attachments = if (color_blend_attachments.len > 0) @ptrCast(&color_blend_attachments[0]) else null,
            .blend_constants = @splat(1.0),
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

    var pipelines: [1]vk.Pipeline = undefined;
    _ = try ctx.device.createGraphicsPipelines(
        .null_handle,
        &.{pipeline_create_info},
        null,
        &pipelines,
    );

    pipeline.* = .{
        .public = .{
            .info = .{
                .fragment_shader = create_info.fragment_shader != null,
                .polygon_mode = create_info.polygon_mode,
                .multisample = create_info.multisample,
                .color_attachments = create_info.color_attachments,
                .depth_attachment_format = create_info.depth_attachment_format,
                .stencil_attachment_format = create_info.stencil_attachment_format,
                .name = create_info.name,
            },
        },
        .pipeline = pipelines[0],
    };

    return &pipeline.public;
}

pub fn queueDestroyGraphicsPipeline(ptr: *anyopaque, rhi_pipeline: *const rhi.GraphicsPipeline) void {
    _ = ptr;
    _ = rhi_pipeline;
}

fn submit(
    ptr: *anyopaque,
    io: std.Io,
    command_buffers: []const rhi.CommandBuffer,
    presents: []const rhi.Present,
) rhi.Context.Error!rhi.Fence {
    const ctx: *Context = @ptrCast(@alignCast(ptr));

    var arena_impl: std.heap.ArenaAllocator = .init(ctx.gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const sync_point: SyncPoint = .{
        .graphics = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.graphics).semaphore),
        .compute = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.compute).semaphore),
        .transfer = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.transfer).semaphore),
        .present = try ctx.device.getSemaphoreCounterValue(ctx.queues.get(.present).semaphore),
    };

    _ = io;

    const command_pools = try arena.alloc(CommandPool, command_buffers.len);
    for (command_buffers, 0..) |command_buffer, i| {
        command_pools[i] = try ctx.getCommandPool(.fromRhi(command_buffer.queue), sync_point);
        // FIXME cleanup if we error
    }

    // TODO this can be done in parallel using the io
    for (command_buffers, command_pools) |command_buffer, command_pool| {
        try ctx.device.beginCommandBuffer(command_pool.body, &.{
            .flags = .{ .one_time_submit_bit = true },
        });
        for (command_buffer.commands.items) |command| {
            switch (command) {
                .begin_render_pass => |cmd| {
                    // TODO dispatch barriers

                    _ = cmd;

                    //     const color_attachment_infos: []vk.RenderingAttachmentInfo =
                    //         if (cmd.color_attachments.len > 0)
                    //             try arena.alloc(vk.RenderingAttachmentInfo, cmd.color_attachments.len)
                    //         else
                    //             &.{};
                    //     const depth_attachment_info: ?*vk.RenderingAttachmentInfo =
                    //         if (cmd.depth_attachment != null)
                    //             try arena.create(vk.RenderingAttachmentInfo)
                    //         else
                    //             null;
                    //     const stencil_attachment_info: ?*vk.RenderingAttachmentInfo =
                    //         if (cmd.stencil_attachment != null)
                    //             try arena.create(vk.RenderingAttachmentInfo)
                    //         else
                    //             null;

                    //     for (cmd.color_attachments, 0..) |attachment, i| {
                    //         const texture: *Texture = @alignCast(@constCast(
                    //             @fieldParentPtr("public", attachment.texture),
                    //         ));
                    //         const view: *View = @alignCast(@constCast(
                    //             @fieldParentPtr("public", if (attachment.view) |view|
                    //                 view
                    //             else
                    //                 attachment.texture.default_view),
                    //         ));

                    //         color_attachment_infos[i] = .{
                    //             .image_view = view.view,
                    //             .image_layout = texture.group,
                    //             .resolve_mode = .{},
                    //             .resolve_image_layout = .undefined,
                    //             .load_op = attachment.load_op.vulkan(),
                    //             .store_op = attachment.store_op.vulkan(),
                    //             .clear_value = attachment.clear_value.vulkan(),
                    //         };
                    //     }
                    //     if (cmd.depth_attachment) |attachment| {
                    //         _ = attachment;
                    //     }
                    //     if (cmd.stencil_attachment) |attachment| {
                    //         _ = attachment;
                    //     }

                    //     ctx.device.cmdBeginRendering(cmdbuf, &.{
                    //         .color_attachment_count = @intCast(color_attachment_infos.len),
                    //         .p_color_attachments = color_attachment_infos.ptr,
                    //         .p_depth_attachment = depth_attachment_info,
                    //         .p_stencil_attachment = stencil_attachment_info,
                    //         .layer_count = 1,
                    //         .view_mask = 0,
                    //         .render_area = .{
                    //             .offset = .{ .x = 0, .y = 0 },
                    //             .extent = cmd.render_area_extent,
                    //         },
                    //     });
                    //     // set all the dynamic state
                    //     // TODO we should probably store the state in the command buffer and
                    //     // only update the diff
                    //     const dynamic_state = cmd.pipeline.dynamic_state;
                    //     ctx.device.cmdBindPipeline(cmdbuf, .graphics, cmd.pipeline.pipeline);
                    //     ctx.device.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(
                    //         &dynamic_state.viewport.vulkan(),
                    //     ));
                    //     ctx.device.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(
                    //         &dynamic_state.scissor.vulkan(),
                    //     ));
                    //     ctx.device.cmdSetPrimitiveTopology(
                    //         cmdbuf,
                    //         dynamic_state.input_assembly.primitive_topology.vulkan(),
                    //     );
                    //     ctx.device.cmdSetPrimitiveRestartEnable(
                    //         cmdbuf,
                    //         if (dynamic_state.input_assembly.enable_primitive_restart) .true else .false,
                    //     );
                    //     ctx.device.cmdSetRasterizerDiscardEnable(
                    //         cmdbuf,
                    //         if (dynamic_state.rasterization.enable_rasterizer_discard) .true else .false,
                    //     );
                    //     ctx.device.cmdSetCullMode(
                    //         cmdbuf,
                    //         dynamic_state.rasterization.cull_mode.vulkan(),
                    //     );
                    //     ctx.device.cmdSetFrontFace(
                    //         cmdbuf,
                    //         dynamic_state.rasterization.front_face.vulkan(),
                    //     );
                    //     if (dynamic_state.rasterization.depth_bias) |depth_bias| {
                    //         ctx.device.cmdSetDepthBiasEnable(cmdbuf, .true);
                    //         ctx.device.cmdSetDepthBias(
                    //             cmdbuf,
                    //             depth_bias.constant_factor,
                    //             depth_bias.clamp,
                    //             depth_bias.slope_factor,
                    //         );
                    //     } else {
                    //         ctx.device.cmdSetDepthBiasEnable(cmdbuf, .false);
                    //     }
                    //     if (dynamic_state.depth_stencil.depth_test) |compare_op| {
                    //         ctx.device.cmdSetDepthTestEnable(cmdbuf, .true);
                    //         ctx.device.cmdSetDepthCompareOp(cmdbuf, compare_op.vulkan());
                    //     } else {
                    //         ctx.device.cmdSetDepthTestEnable(cmdbuf, .false);
                    //     }
                    //     ctx.device.cmdSetDepthWriteEnable(
                    //         cmdbuf,
                    //         if (dynamic_state.depth_stencil.enable_depth_write) .true else .false,
                    //     );
                    //     if (dynamic_state.depth_stencil.stencil_test) |stencil_test| {
                    //         ctx.device.cmdSetStencilTestEnable(cmdbuf, .true);
                    //         const front_op_state = stencil_test.front.vulkan();
                    //         const back_op_state = stencil_test.back.vulkan();
                    //         ctx.device.cmdSetStencilOp(
                    //             cmdbuf,
                    //             .{ .front_bit = true },
                    //             front_op_state.fail_op,
                    //             front_op_state.pass_op,
                    //             front_op_state.depth_fail_op,
                    //             front_op_state.compare_op,
                    //         );
                    //         ctx.device.cmdSetStencilCompareMask(
                    //             cmdbuf,
                    //             .{ .front_bit = true },
                    //             front_op_state.compare_mask,
                    //         );
                    //         ctx.device.cmdSetStencilWriteMask(
                    //             cmdbuf,
                    //             .{ .front_bit = true },
                    //             front_op_state.write_mask,
                    //         );
                    //         ctx.device.cmdSetStencilReference(
                    //             cmdbuf,
                    //             .{ .front_bit = true },
                    //             front_op_state.reference,
                    //         );
                    //         ctx.device.cmdSetStencilOp(
                    //             cmdbuf,
                    //             .{ .back_bit = true },
                    //             back_op_state.fail_op,
                    //             back_op_state.pass_op,
                    //             back_op_state.depth_fail_op,
                    //             back_op_state.compare_op,
                    //         );
                    //         ctx.device.cmdSetStencilCompareMask(
                    //             cmdbuf,
                    //             .{ .back_bit = true },
                    //             back_op_state.compare_mask,
                    //         );
                    //         ctx.device.cmdSetStencilWriteMask(
                    //             cmdbuf,
                    //             .{ .back_bit = true },
                    //             back_op_state.write_mask,
                    //         );
                    //         ctx.device.cmdSetStencilReference(
                    //             cmdbuf,
                    //             .{ .back_bit = true },
                    //             back_op_state.reference,
                    //         );
                    //     } else {
                    //         ctx.device.cmdSetStencilTestEnable(cmdbuf, .false);
                    //     }
                },
                .bind_graphics_pipeline => |cmd| {
                    _ = cmd;
                },
                .end_render_pass => {},
                else => log.err("TODO: handle command {}", .{command}),
            }
        }
        try ctx.device.endCommandBuffer(command_pool.body);
    }

    // for each present
    // transition the src image to the graphics queue
    // we can assume that the swapchain image is on the graphics queue
    // because we don't care about the contents since we always fully overwrite
    // perform a graphics pass to transfer the src image onto the swapchain
    // transfer the swapchain image to the present queue
    // perform present

    const present_queue = ctx.queues.get(.present);
    const present_command_pool = try ctx.getCommandPool(.present, sync_point);

    var acquire_semaphore_infos: std.ArrayList(vk.SemaphoreSubmitInfo) = .empty;
    var release_semaphores: std.ArrayList(vk.Semaphore) = .empty;
    var release_semaphore_infos: std.ArrayList(vk.SemaphoreSubmitInfo) = .empty;
    var swapchains: std.ArrayList(vk.SwapchainKHR) = .empty;
    var image_indices: std.ArrayList(u32) = .empty;
    var swapchain_barriers: std.ArrayList(vk.ImageMemoryBarrier2) = .empty;

    for (presents) |present| {
        const swapchain: *Swapchain = @alignCast(@constCast(
            @fieldParentPtr("public", present.swapchain),
        ));
        std.debug.assert(swapchain.public.state.acquired);
        const image_index = swapchain.image_index.?;

        // FIXME acquire should actually relate to the first queue that writes to the swapchain
        try acquire_semaphore_infos.append(arena, .{
            .semaphore = swapchain.acquire_semaphore,
            .stage_mask = .{ .all_commands_bit = true },
            .device_index = 0,
            .value = undefined, // binary semaphore
        });
        try release_semaphores.append(arena, swapchain.release_semaphores[image_index]);
        try release_semaphore_infos.append(arena, .{
            .semaphore = swapchain.release_semaphores[image_index],
            .stage_mask = .{ .all_commands_bit = true },
            .device_index = 0,
            .value = undefined, // binary semaphore
        });
        try swapchains.append(arena, swapchain.swapchain);
        try image_indices.append(arena, image_index);
        try swapchain_barriers.append(arena, .{
            .src_stage_mask = .{ .all_commands_bit = true },
            .src_access_mask = .{ .memory_write_bit = true },
            .dst_stage_mask = .{ .all_commands_bit = true },
            .dst_access_mask = .{ .memory_read_bit = true },
            .image = swapchain.images[image_index],
            .old_layout = .undefined,
            .new_layout = .present_src_khr,
            .src_queue_family_index = present_queue.family,
            .dst_queue_family_index = present_queue.family,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_array_layer = 0,
                .base_mip_level = 0,
                .layer_count = 1,
                .level_count = 1,
            },
        });

        swapchain.public.state.acquired = false;
    }

    present_queue.value += 1;
    try release_semaphore_infos.append(arena, .{
        .semaphore = present_queue.semaphore,
        .stage_mask = .{ .all_commands_bit = true },
        .device_index = 0,
        .value = present_queue.value,
    });

    try ctx.device.beginCommandBuffer(present_command_pool.body, &.{
        .flags = .{ .one_time_submit_bit = true },
    });
    ctx.device.cmdPipelineBarrier2(present_command_pool.body, &.{
        .image_memory_barrier_count = @intCast(swapchain_barriers.items.len),
        .p_image_memory_barriers = swapchain_barriers.items.ptr,
    });
    try ctx.device.endCommandBuffer(present_command_pool.body);

    try present_queue.queue.submit2(&[_]vk.SubmitInfo2{.{
        .command_buffer_info_count = 1,
        .p_command_buffer_infos = @ptrCast(&[_]vk.CommandBufferSubmitInfo{.{
            .command_buffer = present_command_pool.body,
            .device_mask = 0,
        }}),
        // FIXME the acquire will change
        .wait_semaphore_info_count = @intCast(acquire_semaphore_infos.items.len),
        .p_wait_semaphore_infos = acquire_semaphore_infos.items.ptr,
        .signal_semaphore_info_count = @intCast(release_semaphore_infos.items.len),
        .p_signal_semaphore_infos = release_semaphore_infos.items.ptr,
    }}, .null_handle);

    _ = try present_queue.queue.presentKHR(&.{
        .wait_semaphore_count = @intCast(release_semaphores.items.len),
        .p_wait_semaphores = release_semaphores.items.ptr,
        .swapchain_count = @intCast(swapchains.items.len),
        .p_swapchains = swapchains.items.ptr,
        .p_image_indices = image_indices.items.ptr,
    });

    for (command_buffers, command_pools) |command_buffer, command_pool| {
        const queue: Queue = .fromRhi(command_buffer.queue);
        try ctx.command_pool_depots.getPtr(queue).push(
            command_pool,
            queue,
            ctx.queues.get(queue).value,
        );
    }
    try ctx.command_pool_depots.getPtr(.present).push(
        present_command_pool,
        .present,
        present_queue.value,
    );
    // NOTE this is conservative but safe, when the presentation engine has the image
    // the acquire semaphore is long-since used
    for (acquire_semaphore_infos.items) |acquire_semaphore_info| {
        try ctx.acquire_semaphore_depot.push(
            acquire_semaphore_info.semaphore,
            .present,
            present_queue.value,
        );
    }

    return undefined;
}

fn recreateSwapchain(ctx: *Context, swapchain: *Swapchain) !void {
    // TODO rewrite
    try ctx.device.deviceWaitIdle();

    var arena_impl = std.heap.ArenaAllocator.init(ctx.gpa);
    defer _ = arena_impl.deinit();
    const arena = arena_impl.allocator();

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

    swapchain.public.state.size = .{ extent.width, extent.height, 1 };

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
        for (0..swapchain.images.len) |i| {
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

fn initInstance(
    ctx: *Context,
    arena: std.mem.Allocator,
    platform: Platform,
    config: Config,
) !void {
    // enable_validation activates the validation layer
    // enable_debug activates the debug_utils instance extension

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
        if (!candidate.queue_families.contains(.present)) {
            log.info("Did not pick {s}: No present queue", .{name});
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
        .{candidates.items[0].queue_families.getAssertContains(.graphics)},
    );
    log.debug(
        "- compute queue family: {}",
        .{candidates.items[0].queue_families.getAssertContains(.compute)},
    );
    log.debug(
        "- transfer queue family: {}",
        .{candidates.items[0].queue_families.getAssertContains(.transfer)},
    );
    log.debug(
        "- present queue family: {}",
        .{candidates.items[0].queue_families.getAssertContains(.present)},
    );
    return candidates.items[0];
}

fn initDevice(
    ctx: *Context,
    arena: std.mem.Allocator,
    candidate: PhysicalDeviceCandidate,
) !void {
    var queue_create_infos: std.AutoArrayHashMapUnmanaged(u32, vk.DeviceQueueCreateInfo) = .empty;
    for ([_]Queue{ .graphics, .compute, .transfer, .present }) |queue| {
        const queue_family_index = candidate.queue_families.getAssertContains(queue);
        try queue_create_infos.put(arena, queue_family_index, .{
            .queue_family_index = queue_family_index,
            .queue_count = 1,
            .p_queue_priorities = @ptrCast(&@as(f32, 1.0)),
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
        }, null) catch return error.Unknown; // TODO

        // then assign it to all queues that share that family
        for ([_]Queue{ .graphics, .compute, .transfer, .present }) |queue| {
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
        .descriptor_count = 256 * 1024,
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true },
    }, .{
        .binding = 1,
        .descriptor_type = .storage_image,
        .descriptor_count = 256 * 1024,
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
        .{ .type = .sampled_image, .descriptor_count = 256 * 1024 },
        .{ .type = .storage_image, .descriptor_count = 256 * 1024 },
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
    swapchain_composition: rhi.Composition,
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

fn getCommandPool(ctx: *Context, queue: Queue, sync_point: SyncPoint) !CommandPool {
    const command_pool = ctx.command_pool_depots.getPtr(queue).pop(sync_point) orelse blk: {
        const pool = try ctx.device.createCommandPool(&.{
            .flags = .{},
            .queue_family_index = ctx.queues.get(queue).family,
        }, null);
        errdefer ctx.device.destroyCommandPool(pool, null);
        var buffers: [3]vk.CommandBuffer = .{.null_handle} ** 3;
        try ctx.device.allocateCommandBuffers(&.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 3,
        }, @ptrCast(&buffers[0]));
        errdefer ctx.device.freeCommandBuffers(pool, 3, &buffers);
        break :blk CommandPool{
            .pool = pool,
            .prefix = buffers[0],
            .body = buffers[1],
            .suffix = buffers[2],
        };
    };
    try ctx.device.resetCommandPool(command_pool.pool, .{});
    return command_pool;
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

const TextureAllocator = struct {
    const Slab = struct {
        const slab_size = 256 * 1024 * 1024;
        const granularity = 4096;

        memory_type_index: u32,
        flags: vk.MemoryAllocateFlags,
        allocator: OffsetAllocator,
        memory: vk.DeviceMemory,
    };

    ctx: *Context,
    slabs: std.ArrayList(Slab),

    fn init(ctx: *Context) !TextureAllocator {
        return .{
            .ctx = ctx,
            .slabs = .empty,
        };
    }

    fn deinit(allocator: *TextureAllocator) void {
        for (allocator.slabs.items) |*slab| {
            allocator.ctx.device.freeMemory(slab.memory, null);
            slab.allocator.deinit(allocator.ctx.gpa);
        }
        allocator.slabs.deinit(allocator.ctx.gpa);
        allocator.* = undefined;
    }

    fn alloc(
        allocator: *TextureAllocator,
        memory_type_index: u32,
        flags: vk.MemoryAllocateFlags,
        size: u64,
    ) !struct {
        allocation: Allocation,
        slab: *Slab,
    } {
        const granule_size: u32 = @intCast((size + Slab.granularity - 1) / Slab.granularity);

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
        };

        const allocation = try slab.allocator.allocate(granule_size);
        return .{
            .slab = slab,
            .allocation = allocation,
        };
    }

    fn createTexture(
        allocator: *TextureAllocator,
        texture_create_info: rhi.TextureCreateInfo,
    ) !*Texture {
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
            if (texture_create_info.texture_type != .texture_3d) break :blk false;
            for (texture_create_info.views) |view| {
                if (view.view_type == .view_2d_array) break :blk true;
            }
            break :blk false;
        };

        const depth_stencil_format: bool = switch (texture_create_info.format) {
            .d16_unorm,
            .d16_unorm_s8_uint,
            .d24_unorm_s8_uint,
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            => true,
            else => false,
        };

        const color_attachment = texture_create_info.usage.attachment and !depth_stencil_format;
        const depth_stencil_attachment = texture_create_info.usage.attachment and depth_stencil_format;

        const image_info: vk.ImageCreateInfo = .{
            .flags = .{
                .mutable_format_bit = multiformat,
                .cube_compatible_bit = texture_create_info.texture_type == .texture_cube or
                    texture_create_info.texture_type == .texture_cube_array,
                .@"2d_array_compatible_bit" = arrayview,
            },
            .image_type = vulkanImageType(texture_create_info.texture_type),
            .format = vulkanFormat(texture_create_info.format),
            .extent = .{
                .width = texture_create_info.size[0],
                .height = texture_create_info.size[1],
                .depth = if (texture_create_info.texture_type == .texture_3d)
                    texture_create_info.size[2]
                else
                    1,
            },
            .mip_levels = texture_create_info.mip_levels,
            .array_layers = if (texture_create_info.texture_type == .texture_3d)
                1
            else
                texture_create_info.size[2],
            .samples = vulkanSampleCount(texture_create_info.samples),
            .tiling = .optimal,
            .usage = .{
                .storage_bit = texture_create_info.usage.storage,
                .sampled_bit = texture_create_info.usage.sampled,
                .transfer_src_bit = texture_create_info.usage.transfer_src,
                .transfer_dst_bit = texture_create_info.usage.transfer_dst,
                .color_attachment_bit = color_attachment,
                .depth_stencil_attachment_bit = depth_stencil_attachment,
            },
            .sharing_mode = .exclusive,
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

        var texture = try allocator.ctx.texture_pool.create(allocator.ctx.gpa);
        errdefer allocator.ctx.texture_pool.destroy(texture);
        texture.image = image;

        if (dedicated_memreq.requires_dedicated_allocation == .true or
            (dedicated_memreq.prefers_dedicated_allocation == .true and
                texture_create_info.usage.attachment == true) or
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
            .view_type = vulkanImageViewType(texture_create_info.texture_type),
            .format = vulkanFormat(texture_create_info.format),
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

        const default_view_slot = try allocator.ctx.texture_view_slots.acquire();
        errdefer allocator.ctx.texture_view_slots.release(default_view_slot);

        const default_view_2 = try allocator.ctx.view_pool.create(allocator.ctx.gpa);
        errdefer allocator.ctx.view_pool.destroy(default_view_2);
        default_view_2.* = .{
            .public = .{
                .device_address = @intCast(default_view_slot),
                .info = .{
                    .view_type = switch (texture_create_info.texture_type) {
                        .texture_2d => .view_2d,
                        .texture_3d => .view_3d,
                        .texture_cube => .view_cube,
                        .texture_2d_array => .view_2d_array,
                        .texture_cube_array => .view_cube_array,
                    },
                    .format = texture_create_info.format,
                    .swizzle = .{},
                    .range = .{
                        .base_mip_level = 0,
                        .level_count = texture_create_info.mip_levels,
                        .base_array_layer = 0,
                        .layer_count = if (texture_create_info.texture_type == .texture_3d)
                            1
                        else
                            texture_create_info.size[2],
                    }, // cmon
                    .name = &.{},
                },
            },
            .view = default_view,
        };
        texture.public.default_view = &default_view_2.public;

        std.debug.print("default view info {}\n", .{texture.public.default_view});

        if (texture_create_info.group) |group| {
            _ = group;
            @panic("TODO");
        } else {
            const group = try allocator.ctx.group_pool.create(allocator.ctx.gpa);
            group.* = .{
                .public = .{
                    .info = .{
                        .name = "",
                    },
                },
                .last_used = .never,
                .textures = .empty,
                .buffers = .empty,
                .texture_state = .{
                    .owner = null,
                    .layout = .undefined,
                },
                .texture_state_overrides = .empty,
                .last_write_epoch = 0,
                .last_write_stage_mask = .{},
                .last_read_epoch = 0,
                .last_read_stage_mask = .{},
            };
            texture.public.group = &group.public;

            std.debug.print("{}\n", .{group.*});
            std.debug.print("{}\n", .{texture.public.group.*});
        }
        // FIXME cleanup of group is very hard on errdefer, so don't have errors after it

        // TODO create the other views

        texture.public.info = .{
            .usage = texture_create_info.usage,
            .size = texture_create_info.size,
            .format = texture_create_info.format,
            .mip_levels = texture_create_info.mip_levels,
            .sample_count = texture_create_info.samples,
            .texture_type = texture_create_info.texture_type,
            .name = texture_create_info.name,
        };
        texture.public.views = &.{};

        std.debug.print("end {}\n", .{texture.public.default_view});
        std.debug.print("end {}\n", .{texture});
        std.debug.print("end {*}\n", .{texture});
        std.debug.print("end {*}\n", .{&texture.public});

        return texture;
    }
};
