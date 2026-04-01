const std = @import("std");
const vk = @import("vulkan");

const rhi = @import("root.zig");

const MemoryPool = std.heap.MemoryPool;

pub const Platform = struct {
    // TODO not sure what the best function signatures are here
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () anyerror![]const [*:0]const u8,
    createWindowSurface: *const fn (vk.Instance, window: *anyopaque) anyerror!vk.SurfaceKHR,
    getFramebufferSize: *const fn (window: *anyopaque) anyerror!vk.Extent2D,
};

pub const Config = struct {
    preferred_physical_device: ?[]const u8 = null,
    upload_staging_size: usize = 256 * 1024 * 1024,
    download_staging_size: usize = 128 * 1024 * 1024,
};

pub fn init(gpa: std.mem.Allocator, platform: Platform, config: Config) !rhi.Context {
    const ctx = try gpa.create(Context);
    ctx.* = try .init(gpa, platform, config);
    return .{
        .ptr = ctx,
        .vtable = Context.vtable,
    };
}

pub fn deinit(ctx: rhi.Context) void {
    const vkctx: *Context = @ptrCast(@alignCast(ctx.ptr));
    const gpa = vkctx.gpa;
    vkctx.deinit();
    gpa.destroy(vkctx);
}

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

const ComputePass = struct {};

const RenderPass = struct {};

const CommandBuffer = struct {};

const Context = struct {
    const vtable: rhi.Context.VTable = undefined;

    gpa: std.mem.Allocator,
    platform: Platform,

    base: vk.BaseWrapper,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,

    physical_device: vk.PhysicalDevice,
    physical_device_properties: vk.PhysicalDeviceProperties,
    physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,

    swapchains: std.AutoHashMap(rhi.Window, struct {
        surface: vk.SurfaceKHR,
        composition: rhi.SwapchainComposition,
        present_mode: rhi.PresentMode,
        swapchain: *Swapchain,
    }),

    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,

    // pools are for resources that are recreated, not reused
    shader_pool: MemoryPool(Shader),
    graphics_pipeline_pool: MemoryPool(GraphicsPipeline),
    compute_pipeline_pool: MemoryPool(ComputePipeline),
    buffer_pool: MemoryPool(Buffer),
    texture_pool: MemoryPool(Texture),
    sampler_pool: MemoryPool(Sampler),
    render_pass_pool: MemoryPool(RenderPass),
    compute_pass_pool: MemoryPool(ComputePass),

    // depots are for resources that are reused once available
    command_buffer_depots: std.EnumArray(Queue, Depot(CommandBuffer)),
    image_acquire_semaphore_depot: Depot(vk.Semaphore),

    buffer_allocator: BufferAllocator,
    texture_allocator: TextureAllocator,
    upload_allocator: UploadAllocator,
    download_allocator: DownloadAllocator,

    fn init(gpa: std.mem.Allocator, platform: Platform, config: Config) !Context {
        _ = gpa;
        _ = platform;
        _ = config;
        return .{};
    }

    fn deinit(ctx: *Context) void {
        ctx.* = undefined;
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
    return struct {};
}
