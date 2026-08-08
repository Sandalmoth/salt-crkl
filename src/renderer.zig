const std = @import("std");
const lin = @import("math").lin;
const spiral = @import("spiral");
const profiler = @import("profiler");
// const mem = @import("mem");

pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");

const Self = @This();

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

origin: lin.V3d,

pub fn init(_gpa: std.mem.Allocator, _blka: std.mem.Allocator) Self {
    return .{
        .gpa = _gpa,
        .blka = _blka,
    };
}

pub fn deinit(renderer: *Self) void {
    _ = renderer;
}

// for each model, if dirty update its instances

// gpu buffer of (transform, mesh_index) -> mesh buffer of (radius, ...)

// cull to produce yes/no buffer and write yes count to indirect draw commands

// compact for each mesh individually
// if we know how many of each mesh were in the original buffer we know their offsets

// for each mesh
//   binds & uniforms (offset in instance buffer)
//   drawindirect(culled_buffer_for_single_lod)
