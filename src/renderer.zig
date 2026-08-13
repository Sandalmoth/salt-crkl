const std = @import("std");
const lin = @import("math").lin;
const spiral = @import("spiral");
const profiler = @import("profiler");
// const mem = @import("mem");

pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");

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

pub const CommandList = struct {
    // createDrawable(transform, model_uuid) -> handle
    // setTransform(handle, transform)
    // setModel(handle, model_uuid)
    // setMesh(handle, mesh_uuid)
    // setMaterial(handle, material_uuid)
    // destroyDrawable(handle)
};

const Model = struct {
    instances: []*Instance,
    // current_lod:
};

const Material = struct {
    pipeline: *Pipeline,
    opacity: enum { solid, cutout, alpha },
    // somehow maps to what the pipeline expects
    // textures: []spiral.Uuid,
    // textures: []Texture
};

const Pipeline = struct {
    // pipeline: sdl...
};

const Texture = struct {
    mip_levels: u32,
    min_mip_level: u32, // streaming state
    // texture: sdl.GPUTexture,
};

const Mesh = struct {
    // buffer: sdl.GPUBuffer,
};

const Instance = struct {
    position: lin.V3d,
    orientation: lin.Qf,
    scale: lin.V3f,
    lod: f32,
};

const Page = struct {
    const capacity = (defines.block_size - @sizeOf(Header)) / @sizeOf(Instance) - 1;

    const Header = struct {
        // a page should hold just one mesh (but can hold any of its lods)
        // it has a pipeline
        // and a material (textures & shader parameters)

        // for each individual mesh instances we need
        // - a transform
        mesh: *Mesh,
        material: *Material,
        instances: [*]Instance,
        instance_count: usize,
    };

    header: Header,
    bytes: [defines.block_size - @sizeOf(Header)]u8,
};

gpa: std.mem.Allocator,
blka: std.mem.Allocator,
config: Config,

hdr_backbuffer: *sdl.GPUTexture,
sdr_backbuffer: *sdl.GPUTexture,

// suballocated
vertex_geometry_buffer: *sdl.GPUBuffer,
vertex_material_buffer: *sdl.GPUBuffer,
vertex_rigged_buffer: *sdl.GPUBuffer,
vertex_morph_buffer: *sdl.GPUBuffer,
// bump allocated, recycled each frame
rigged_vertex_geometry_buffer: *sdl.GPUBuffer,
rigged_vertex_material_buffer: *sdl.GPUBuffer,

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
    defer sdl.destroyGPUDevice(device);
    try sdl.claimWindowForGPUDevice(device, window);

    const hdr_backbuffer = sdl.createGPUTexture(device, &.{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET |
            sdl.c.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ,
        .width = config.width,
        .height = config.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.c.SDL_GPU_SAMPLECOUNT_4,
    });
    errdefer sdl.releaseGPUTexture(device, hdr_backbuffer);
    const sdr_backbuffer = sdl.createGPUTexture(device, &.{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET |
            sdl.c.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE,
        .width = config.width,
        .height = config.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.c.SDL_GPU_SAMPLECOUNT_1,
    });
    errdefer sdl.releaseGPUTexture(device, sdr_backbuffer);

    return .{
        .gpa = _gpa,
        .blka = _blka,
        .config = config,
        .hdr_backbuffer = hdr_backbuffer,
        .sdr_backbuffer = sdr_backbuffer,
        .device = device,
    };
}

pub fn deinit(renderer: *Self) void {
    sdl.releaseGPUTexture(renderer.device, renderer.hdr_backbuffer);
    sdl.releaseGPUTexture(renderer.device, renderer.sdr_backbuffer);
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
