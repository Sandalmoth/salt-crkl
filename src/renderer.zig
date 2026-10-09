const std = @import("std");
const lin = @import("math").lin;
const spiral = @import("spiral");
const profiler = @import("profiler");
const mem = @import("mem");

pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");

pub const max_instances = 1024 * 1024;
pub const max_models = 64 * 1024;

const Self = @This();

pub const VertexGeometry = extern struct {
    position: [3]f32,
    texcoord: [2]f16,
};

pub const VertexMaterial = extern struct {
    packed_normal: u32, // octahedral 16_16 snorm
    packed_tangent: u32, // octahedral 15_pad_15_sign snorm
    color: [4]u8,
};

pub const VertexRigged = extern struct {
    bone_ids: [4]u8,
    bone_weights: [4]u8,
};

pub const VertexMorph = extern struct {
    packed_position_delta: u32, // 10_10_10_pad snorm
    packed_normal_delta: u32, // 10_10_10_pad snorm
    packed_tangent_delta: u32, // 10_10_10_pad snorm
};

pub const Config = struct {
    width: u32,
    height: u32,
    // sample_count: sdl.c.SDL_GPUSampleCount,
};

pub const Key = enum(u64) {
    nil = 0,
    _,

    const HashContext = struct {
        pub fn hash(ctx: HashContext, key: Key) u64 {
            _ = ctx;
            return @intFromEnum(key); // it's already random
        }

        pub fn eql(ctx: HashContext, a: Key, b: Key) bool {
            _ = ctx;
            return a == b;
        }
    };
};

pub const CommandList = struct {
    renderer: *Self,

    // createInstance(transform, model_uuid) -> handle
    // setTransform(handle, position: lin.V3d, )
    // setModel(handle, model_uuid)
    // setMesh(handle, mesh_uuid)
    // setMaterial(handle, material_uuid)
    // destroyDrawable(handle)
};

const Material = struct {
    pipeline: *Pipeline,
    opacity: enum { solid, cutout, alpha },
    // somehow maps to what the pipeline expects
    // textures: []spiral.Uuid,
    // textures: []Texture
};

const Pipeline = struct {
    pipeline: *sdl.GPUGraphicsPipeline,
};

const Texture = struct {
    mip_levels: u32,
    min_mip_level: u32, // streaming state
    // texture: sdl.GPUTexture,
};

const Mesh = struct {
    buffer: *sdl.GPUBuffer,
    vertex_allocation: mem.OffsetAllocator.Allocation,
    vertex_rigged_allocation: mem.OffsetAllocator.Allocation,
    vertex_morph_allocation: mem.OffsetAllocator.Allocation,
};

const Model = struct {
    // a model uses
    // - one mesh (but all of its lods)
    // - a pipeline
    // - a material (textures & shader parameters)
    // - (optional) a skeleton and morph targets

    // the transform and lod state live on the gpu

    mesh: *Mesh,
    material: *Material,

    instance_count: usize,
};

const GpuDiff = extern struct {
    instance_id: u32, // position in paged buffers
    position: [3][2]f32, // global high low dual
    orientation: [4]f32,
    scale: [3]f32,
};
// persistent on the gpu
// updated via diffs from cpu
const GpuData = extern struct {
    position: [3][2]f32, // global high low dual
    orientation: [4]f32,
    scale: [3]f32,
};
const GPULodState = extern struct {
    timer: u32, // 4x8 unorm
    src: u32, // 4x8 uint
    dst: u32, // 4x8 uint
};

// temporary on gpu
// regenerated from the GpuData with a compute shader each frame
const GpuTransformData = extern struct {
    model: [4][4]f32 align(16), // relative to renderer origin
};
const GPUCullingData = extern struct {
    position: [3]f32 align(16), // relative to renderer origin
    radius: f32,
};

const GpuMeshData = extern struct {
    vertex_offsets: [8]u32,
    vertex_counts: [8]u32,
    lod_thresholds: [8]f32,
    lod_count: u32,
};

gpa: std.mem.Allocator,
blka: std.mem.Allocator,
config: Config,

window: *sdl.Window,

upload_buffer: *sdl.GPUTransferBuffer,
download_buffer: *sdl.GPUTransferBuffer,

hdr_backbuffer: *sdl.GPUTexture,
sdr_backbuffer: *sdl.GPUTexture,

instance_allocator: mem.SlotAllocator,
instance_map: std.HashMapUnmanaged(Key, struct { slot: u32, refcount: u32 }, Key.HashContext, 80),

models: []Model,
model_allocator: mem.SlotAllocator,
model_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { slot: u32, refcount: u32 }),

mesh_allocator: mem.MemoryPool(Mesh),
mesh_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Mesh, refcount: u32 }),

material_allocator: mem.MemoryPool(Material),
material_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Material, refcount: u32 }),

pipeline_allocator: mem.MemoryPool(Pipeline),
pipeline_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Pipeline, refcount: u32 }),

texture_allocator: mem.MemoryPool(Texture),
texture_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Texture, refcount: u32 }),

// suballocated
index_buffer: *sdl.GPUBuffer,
vertex_geometry_buffer: *sdl.GPUBuffer, // paired to vertex_material
vertex_material_buffer: *sdl.GPUBuffer, // paired to vertex_geometry
vertex_rigged_buffer: *sdl.GPUBuffer,
vertex_morph_buffer: *sdl.GPUBuffer,
// bump allocated, used for animated meshes, recycled each frame
scratch_vertex_geometry_buffer: *sdl.GPUBuffer, // paired to vertex_material
scratch_vertex_material_buffer: *sdl.GPUBuffer, // paired to vertex_geometry

diff_buffer: *sdl.GPUBuffer,
// page structured
paged_data_buffer: *sdl.GPUBuffer,
paged_lod_buffer: *sdl.GPUBuffer,
// page structured, temporary
scratch_paged_transform_buffer: *sdl.GPUBuffer,
scratch_paged_culling_buffer: *sdl.GPUBuffer,

// vertex_allocator: OffsetAllocator,
// vertex_rigged_allocator: OffsetAllocator,
// vertex_morph_allocator: OffsetAllocator,

device: *sdl.GPUDevice,

// origin: lin.V3d,

pub fn init(
    _gpa: std.mem.Allocator,
    _blka: std.mem.Allocator,
    window: *sdl.Window,
    config: Config,
) !Self {
    const device = try sdl.createGPUDevice(
        sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        "vulkan",
    );
    errdefer sdl.destroyGPUDevice(device);
    try sdl.claimWindowForGPUDevice(device, window);

    const upload_buffer = try sdl.createGPUTransferBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUTransferBuffer(device, upload_buffer);
    const download_buffer = try sdl.createGPUTransferBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUTransferBuffer(device, download_buffer);

    const hdr_backbuffer = try sdl.createGPUTexture(device, &.{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET |
            sdl.c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = config.width,
        .height = config.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.c.SDL_GPU_SAMPLECOUNT_1,
    });
    errdefer sdl.releaseGPUTexture(device, hdr_backbuffer);
    const sdr_backbuffer = try sdl.createGPUTexture(device, &.{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = config.width,
        .height = config.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.c.SDL_GPU_SAMPLECOUNT_1,
    });
    errdefer sdl.releaseGPUTexture(device, sdr_backbuffer);

    // TODO think about how to size these, probably just add to config with usage logs?
    const index_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, index_buffer);
    const vertex_geometry_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, vertex_geometry_buffer);
    const vertex_material_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, vertex_material_buffer);
    const vertex_rigged_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, vertex_rigged_buffer);
    const vertex_morph_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, vertex_morph_buffer);
    const scratch_vertex_geometry_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, scratch_vertex_geometry_buffer);
    const scratch_vertex_material_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, scratch_vertex_material_buffer);
    const diff_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, diff_buffer);
    const paged_data_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, paged_data_buffer);
    const paged_lod_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, paged_lod_buffer);
    const scratch_paged_transform_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, scratch_paged_transform_buffer);
    const scratch_paged_culling_buffer = try sdl.createGPUBuffer(device, &.{
        .usage = sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ |
            sdl.c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        .size = 64 * 1024 * 1024,
    });
    errdefer sdl.releaseGPUBuffer(device, scratch_paged_culling_buffer);

    return .{
        .gpa = _gpa,
        .blka = _blka,
        .config = config,
        .window = window,
        .upload_buffer = upload_buffer,
        .download_buffer = download_buffer,
        .hdr_backbuffer = hdr_backbuffer,
        .sdr_backbuffer = sdr_backbuffer,
        .index_buffer = index_buffer,
        .vertex_geometry_buffer = vertex_geometry_buffer,
        .vertex_material_buffer = vertex_material_buffer,
        .vertex_rigged_buffer = vertex_rigged_buffer,
        .vertex_morph_buffer = vertex_morph_buffer,
        .scratch_vertex_geometry_buffer = scratch_vertex_geometry_buffer,
        .scratch_vertex_material_buffer = scratch_vertex_material_buffer,
        .diff_buffer = diff_buffer,
        .paged_data_buffer = paged_data_buffer,
        .paged_lod_buffer = paged_lod_buffer,
        .scratch_paged_transform_buffer = scratch_paged_transform_buffer,
        .scratch_paged_culling_buffer = scratch_paged_culling_buffer,
        .device = device,
    };
}

pub fn deinit(renderer: *Self) void {
    sdl.releaseGPUTransferBuffer(renderer.device, renderer.upload_buffer);
    sdl.releaseGPUTransferBuffer(renderer.device, renderer.download_buffer);

    sdl.releaseGPUTexture(renderer.device, renderer.hdr_backbuffer);
    sdl.releaseGPUTexture(renderer.device, renderer.sdr_backbuffer);

    sdl.releaseGPUBuffer(renderer.device, renderer.index_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.vertex_geometry_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.vertex_material_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.vertex_rigged_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.vertex_morph_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.scratch_vertex_geometry_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.scratch_vertex_material_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.diff_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.paged_data_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.paged_lod_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.scratch_paged_transform_buffer);
    sdl.releaseGPUBuffer(renderer.device, renderer.scratch_paged_culling_buffer);

    sdl.destroyGPUDevice(renderer.device);
}

// for each model, if dirty update its instances

// gpu buffer of (transform, mesh_index) -> mesh buffer of (radius, ...)

// cull to produce yes/no buffer and write yes count to indirect draw commands

// compact for each mesh individually
// if we know how many of each mesh were in the original buffer we know their offsets

// for each mesh
//   binds & uniforms (offset in instance buffer)
//   drawindirect(culled_buffer_for_single_lod)

pub fn draw(renderer: *Self, arena: std.mem.Allocator, command_lists: []CommandList) !void {
    _ = arena;
    _ = command_lists;

    const upload_bytes: [*]u8 = @ptrCast(
        try sdl.mapGPUTransferBuffer(renderer.device, renderer.upload_buffer, true),
    );
    var upload_commands: std.ArrayList(struct {
        src: sdl.GPUTransferBufferLocation,
        dst: union(enum) {
            buffer: sdl.GPUBufferRegion,
            texture: sdl.GPUTextureRegion,
        },
        cycle: bool,
    }) = .empty;
    _ = upload_bytes;
    upload_commands = upload_commands;
    sdl.unmapGPUTransferBuffer(renderer.device, renderer.upload_buffer);
    for (upload_commands.items) |command| {
        _ = command;
    }

    const command_buffer = try sdl.acquireGPUCommandBuffer(renderer.device);

    const swapchain, const swapchain_width, const swapchain_height = blk: {
        var swapchain: ?*sdl.GPUTexture = null;
        var swapchain_width: u32 = 0;
        var swapchain_hegiht: u32 = 0;
        try sdl.waitAndAcquireGPUSwapchainTexture(
            command_buffer,
            renderer.window,
            &swapchain,
            &swapchain_width,
            &swapchain_hegiht,
        );
        break :blk .{ swapchain, swapchain_hegiht, swapchain_width };
    };

    std.debug.print("{*} {}x{}\n", .{ swapchain, swapchain_width, swapchain_height });

    try sdl.submitGPUCommandBuffer(command_buffer);
}
