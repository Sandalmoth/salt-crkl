const std = @import("std");
const lin = @import("math").lin;
const spiral = @import("spiral");
const profiler = @import("profiler");
const mem = @import("mem");

pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");

pub const max_instances = 256 * 1024;
pub const max_meshes = 64 * 1024;
pub const max_textures = 64 * 1024;
pub const max_materials = 16 * 1024;
pub const max_models = 16 * 1024;
pub const max_pipelines = 4 * 1024;

const hdr_format = sdl.c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT;
const sdr_format = sdl.c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB;

const Renderer = @This();

pub const VertexGeometry = extern struct {
    position: [3]f32,
    texcoord: [2]f16, // texcoords are here for depth only alpha-cutout passes
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
};

pub const CommandList = struct {
    const Command = union(enum) {
        create_instance: struct {
            uuid: spiral.Uuid,
            position: lin.V3d,
            orientation: lin.Qf,
            scale: lin.V3f,
        },
    };

    renderer: *Renderer,
    arena: std.mem.Allocator,
    list: std.ArrayList(Command), // TODO: switch to something that doesn't reallocate

    fn createInstance(
        list: *CommandList,
        uuid: spiral.Uuid,
        position: lin.V3d,
        orientation: lin.Qf,
        scale: lin.V3f,
    ) !*Instance {
        const model = list.renderer.model_map.get(uuid) orelse try list.renderer.loadModel(uuid);
        _ = model;
        try list.list.ensureUnusedCapacity(list.arena, 1);
        list.renderer.mutex.lockUncancelable(list.renderer.io);
        defer list.renderer.mutex.unlock(list.renderer.io);
        for (0..list.renderer.pages.items) |page| {
            _ = page;
        }
        const command = list.list.addOneAssumeCapacity(list.arena);
        command.* = .{
            .uuid = uuid,
            .position = position,
            .orientation = orientation,
            .scale = scale,
        };
    }

    // createInstance(transform, model_uuid) -> handle
    // setTransform(handle, position: lin.V3d, )
    // setModel(handle, model_uuid)
    // setMesh(handle, mesh_uuid)
    // setMaterial(handle, material_uuid)
    // destroyDrawable(handle)
};

const UploadAllocator = struct {
    const capacity = 64 * 1024 * 1024;

    const Command = struct {
        src: sdl.GPUTransferBufferLocation,
        dst: union(enum) {
            buffer: sdl.GPUBufferRegion,
            texture: sdl.GPUTextureRegion,
        },
        cycle: bool,
    };

    gpa: std.mem.Allocator,
    device: *sdl.GPUDevice,
    buffer: *sdl.GPUTransferBuffer,
    cursor: usize = 0,
    bytes: ?[*]u8 = null,
    commands: std.ArrayList(Command) = .empty,

    pub fn init(renderer: *Renderer) !UploadAllocator {
        const buffer = try sdl.createGPUTransferBuffer(renderer.device, &.{
            .usage = sdl.c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = capacity,
        });
        errdefer sdl.releaseGPUTransferBuffer(renderer.device, buffer);
        return .{
            .gpa = renderer.gpa,
            .device = renderer.device,
            .buffer = buffer,
        };
    }

    pub fn deinit(alloc: *UploadAllocator) void {
        sdl.releaseGPUTransferBuffer(alloc.device, alloc.buffer);
        alloc.commands.deinit(alloc.gpa);
    }

    pub fn bind(alloc: *UploadAllocator) !void {
        alloc.cursor = 0;
        alloc.bytes = @ptrCast(
            try sdl.mapGPUTransferBuffer(alloc.device, alloc.buffer, true),
        );
    }

    pub fn bufferUpload(
        alloc: *UploadAllocator,
        src: []const u8,
        dst: *sdl.GPUBuffer,
        offset: u32,
        cycle: bool,
    ) !void {
        if (capacity < alloc.cursor + src.len) return error.OutOfMemory;
        const command = try alloc.commands.addOne(alloc.gpa);
        command.* = .{
            .src = .{ .transfer_buffer = alloc.buffer, .offset = @intCast(alloc.cursor) },
            .dst = .{ .buffer = .{ .buffer = dst, .offset = offset, .size = @intCast(src.len) } },
            .cycle = cycle,
        };
        @memcpy(alloc.bytes.?[alloc.cursor..], src);
        alloc.cursor += src.len;
    }

    pub fn submit(alloc: *UploadAllocator, command_buffer: *sdl.GPUCommandBuffer) !void {
        sdl.unmapGPUTransferBuffer(alloc.device, alloc.buffer);
        const pass = try sdl.beginGPUCopyPass(command_buffer);
        for (alloc.commands.items) |command| {
            switch (command.dst) {
                .buffer => |dst| sdl.uploadToGPUBuffer(pass, &command.src, &dst, command.cycle),
                .texture => |dst| {
                    _ = dst;
                    @panic("TODO");
                },
            }
        }
        sdl.endGPUCopyPass(pass);
    }
};

const Page = struct {
    // a page

    const Header = struct {
        mesh: *Mesh,
        instances: StaticSkipArray(*Instance, u16),
    };

    header: Header,
    bytes: [defines.block_size - @sizeOf(Header)]u8,

    fn create(blka: std.mem.Allocator, mesh: *Mesh) !*Page {
        const page = blka.create(Page);
        page.header = .{
            .mesh = mesh,
            .instances = .initBacking(&page.bytes),
        };
        return page;
    }
};
comptime {
    std.debug.assert(@sizeOf(Page) <= defines.block_size);
}

// instances are the external interface, you get a pointer to an instance
// an instance is composed of several meshes
// instances must have a stable address, simple solution is to cap the maximum number
pub const Instance = struct {
    position: lin.V3d,
    orientation: lin.Qf,
    scale: lin.V3f,
    visible: bool,

    // lod state
    src: [4]u8,
    dst: [4]u8,
    timer: [4]u8,
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

    reference_count: u32,
};

const Mesh = struct {
    material: *Material,
    buffer: *sdl.GPUBuffer,
    bounding_sphere_offset: [3]f32,
    bounding_sphere_radius: f32,
    vertex_allocation: mem.OffsetAllocator.Allocation,
    vertex_rigged_allocation: mem.OffsetAllocator.Allocation,
    vertex_morph_allocation: mem.OffsetAllocator.Allocation,

    reference_count: u32,
};

const Model = struct {
    // a model is a collection of meshes
    meshes: []*Mesh,
    instance_count: usize,
};

const GpuMeshData = extern struct {
    vertex_offsets: [8]u32,
    vertex_counts: [8]u32,
    lod_thresholds: [8]f32,
    lod_count: u32,
};

gpa: std.mem.Allocator,
blka: std.mem.Allocator,
io: std.Io,
config: Config,

mutex: std.Io.Mutex,

window: *sdl.Window,

storage: *spiral.Storage,

pages: std.ArrayList(*Page),

upload_allocator: UploadAllocator,

depth_stencil_format: sdl.c.SDL_GPUTextureFormat,
hdr_backbuffer: *sdl.GPUTexture,
sdr_backbuffer: *sdl.GPUTexture,
depth_backbuffer: *sdl.GPUTexture,

// instance_allocator: mem.SlotAllocator,
// instance_map: std.HashMapUnmanaged(Key, struct { slot: u32, refcount: u32 }, Key.HashContext, 80),

// all these maps are append only (maybe we could even preload everything)
model_map: std.AutoHashMapUnmanaged(spiral.Uuid, u32),
// material_map: std.AutoHashMapUnmanaged(spiral.Uuid, u32),
// pipeline_map: std.AutoHashMapUnmanaged(spiral.Uuid, u32),
// meshe_map: std.AutoHashMapUnmanaged(spiral.Uuid, *Mesh),
// texture_map: std.AutoHashMapUnmanaged(spiral.Uuid, *Mesh),

// mesh_allocator: mem.MemoryPool(Mesh),
// mesh_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Mesh, refcount: u32 }),

// material_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Material, refcount: u32 }),

// pipeline_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Pipeline, refcount: u32 }),

// texture_allocator: mem.MemoryPool(Texture),
// texture_map: std.AutoHashMapUnmanaged(spiral.Uuid, struct { ptr: *Texture, refcount: u32 }),

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
    renderer: *Renderer,
    _gpa: std.mem.Allocator,
    _blka: std.mem.Allocator,
    _io: std.Io,
    window: *sdl.Window,
    config: Config,
    storage: *spiral.Storage,
) !void {
    const device = try sdl.createGPUDevice(
        sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        true,
        "vulkan",
    );
    errdefer sdl.destroyGPUDevice(device);
    try sdl.claimWindowForGPUDevice(device, window);

    // what the fuck is up with this intcast?
    const depth_stencil_format: sdl.c.SDL_GPUTextureFormat = @intCast(
        if (sdl.c.SDL_GPUTextureSupportsFormat(
            device,
            sdl.c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
            sdl.c.SDL_GPU_TEXTURETYPE_2D,
            sdl.c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        )) sdl.c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT else sdl.c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
    );

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
    const depth_backbuffer = try sdl.createGPUTexture(device, &.{
        .type = sdl.c.SDL_GPU_TEXTURETYPE_2D,
        .format = depth_stencil_format,
        .usage = sdl.c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = config.width,
        .height = config.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.c.SDL_GPU_SAMPLECOUNT_1,
    });
    errdefer sdl.releaseGPUTexture(device, depth_backbuffer);

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

    renderer.* = .{
        .gpa = _gpa,
        .blka = _blka,
        .io = _io,
        .config = config,
        .depth_stencil_format = depth_stencil_format,
        .mutex = .init,
        .storage = storage,
        .window = window,
        .upload_allocator = undefined,
        .pages = .empty,
        .model_map = .empty,
        .hdr_backbuffer = hdr_backbuffer,
        .sdr_backbuffer = sdr_backbuffer,
        .depth_backbuffer = depth_backbuffer,
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

    renderer.upload_allocator = try .init(renderer);
    try renderer.upload_allocator.bind();

    try renderer._testSetup();
}

pub fn deinit(renderer: *Renderer) void {
    renderer.upload_allocator.deinit();

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

pub fn draw(renderer: *Renderer, arena: std.mem.Allocator, command_lists: []CommandList) !void {
    _ = arena;
    _ = command_lists;

    const command_buffer = try sdl.acquireGPUCommandBuffer(renderer.device);

    // uploads everything for the frame
    try renderer.upload_allocator.submit(command_buffer);

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

    // rebinds the transfer buffer so we can upload more during next frame
    try renderer.upload_allocator.bind();
}

fn loadModel(renderer: *Renderer, uuid: spiral.Uuid) !*Model {
    _ = renderer;
    _ = uuid;
    return undefined;
}

fn _testSetup(renderer: *Renderer) !void {
    std.debug.print("--- start testSetup ---\n", .{});

    var arena_impl: std.heap.ArenaAllocator = .init(renderer.gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const cube_vertices: [8]VertexGeometry = .{
        .{ .position = .{ -0.5, -0.5, -0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ -0.5, -0.5, 0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .texcoord = .{ 0, 0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .texcoord = .{ 0, 0 } },
    };
    try renderer.upload_allocator.bufferUpload(std.mem.asBytes(
        &cube_vertices,
    ), renderer.vertex_geometry_buffer, 0, false);

    const cube_indices: [12][3]u32 = .{
        .{ 1, 3, 0 },
        .{ 3, 2, 0 },
        .{ 4, 6, 5 },
        .{ 6, 7, 5 },
        .{ 0, 4, 1 },
        .{ 4, 5, 1 },
        .{ 3, 7, 2 },
        .{ 7, 6, 2 },
        .{ 0, 2, 4 },
        .{ 2, 6, 4 },
        .{ 5, 7, 1 },
        .{ 7, 3, 1 },
    };
    try renderer.upload_allocator.bufferUpload(std.mem.asBytes(
        &cube_indices,
    ), renderer.index_buffer, 0, false);

    var vertex_future = try renderer.storage.load(
        arena,
        try .parse("3649X98QWPGM8GPAXNAW6PJW1R"),
    );
    const vertex_bytes = try vertex_future.await();
    var fragment_future = try renderer.storage.load(
        arena,
        try .parse("7VFRQ770Y7EPQGF2VZZWP7Q97H"),
    );
    const fragment_bytes = try fragment_future.await();

    const vertex_shader = try sdl.createGPUShader(renderer.device, &.{
        .code_size = vertex_bytes.len,
        .code = vertex_bytes.ptr,
        .entrypoint = "main",
        .format = sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = sdl.c.SDL_GPU_SHADERSTAGE_VERTEX,
        // CONSIDER: we could parse these out and store in the asset together with the spv
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 1,
        .num_uniform_buffers = 1,
    });
    defer sdl.releaseGPUShader(renderer.device, vertex_shader);
    const fragment_shader = try sdl.createGPUShader(renderer.device, &.{
        .code_size = fragment_bytes.len,
        .code = fragment_bytes.ptr,
        .entrypoint = "main",
        .format = sdl.c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = sdl.c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        // CONSIDER: we could parse these out and store in the asset together with the spv
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = 0,
    });
    defer sdl.releaseGPUShader(renderer.device, fragment_shader);

    const pipeline = try sdl.createGPUGraphicsPipeline(renderer.device, &.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = sdl.c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .front_face = sdl.c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .cull_mode = sdl.c.SDL_GPU_CULLMODE_BACK,
        },
        .depth_stencil_state = .{
            .compare_op = sdl.c.SDL_GPU_COMPAREOP_GREATER,
            .enable_depth_test = true,
            .enable_depth_write = true,
        },
        .target_info = .{
            .color_target_descriptions = &.{ .format = hdr_format },
            .num_color_targets = 0,
            .depth_stencil_format = @intCast(renderer.depth_stencil_format),
            .has_depth_stencil_target = true,
        },
    });
    errdefer sdl.releaseGPUGraphicsPipeline(renderer.device, pipeline);

    std.debug.print("--- end testSetup ---\n", .{});
}

fn StaticSkipArray(comptime T: type, comptime Skip: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            next: Skip,
            prev: Skip,
        };
        const Data = union {
            node: Node,
            value: T,
        };

        capacity: usize,
        skip: [*]Skip, // capacity + 1
        data: [*]Data, // capacity
        first_free_block: ?Skip,

        /// init into a slice of memory at maximum capacity that fits
        fn initBacking(backing_memory: []u8) Self {
            const capacity = backing_memory.len / (@sizeOf(T) + @sizeOf(Skip)) - 1;
            std.debug.print("StaticSkipArray initBacking capacity is {}\n", .{capacity});
            std.debug.assert(capacity <= std.math.maxInt(Skip));

            // (sub)allocate and setup skiplist
            const skip: [*]Skip = @ptrCast(backing_memory.ptr);
            skip[0] = @intCast(capacity);
            skip[capacity - 1] = @intCast(capacity);
            skip[capacity] = 0;

            // (sub)allocate data segment and setup free-block
            const data: [*]Data = @ptrFromInt(std.mem.alignForward(
                usize,
                @intFromPtr(backing_memory.ptr) + @sizeOf(Skip) * (capacity + 1),
                @alignOf(T),
            ));
            data[0] = .{ .node = .{
                .prev = 0,
                .next = 0,
            } };
            std.debug.assert(
                @intFromPtr(&data[capacity]) <= @intFromPtr(backing_memory.ptr) + backing_memory.len,
            );

            return .{
                .capacity = capacity,
                .skip = skip,
                .data = data,
                .first_free_block = 0,
            };
        }

        /// init to a fixed capacity by allocating the required memory
        fn initCapacity(gpa: std.mem.Allocator, capacity: usize) Self {
            std.debug.assert(capacity <= std.math.maxInt(Skip));
            const backing_memory = try gpa.alloc(Skip, size(capacity));

            // (sub)allocate and setup skiplist
            const skip: [*]Skip = backing_memory.ptr;
            skip[0] = @intCast(capacity);
            skip[capacity - 1] = @intCast(capacity);
            skip[capacity] = 0;

            // (sub)allocate data segment and setup free-block
            const data: [*]Data = @ptrFromInt(std.mem.alignForward(
                usize,
                @intFromPtr(backing_memory.ptr) + @sizeOf(Skip) * (capacity + 1),
                @alignOf(T),
            ));
            data[0] = .{ .node = .{
                .prev = 0,
                .next = 0,
            } };

            return .{
                .capacity = capacity,
                .skip = skip,
                .data = data,
                .first_free_block = 0,
            };
        }

        fn deinit(array: *Self, gpa: std.mem.Allocator) void {
            const backing_memory = array.skip[0..size(array.capacity)];
            gpa.free(backing_memory);
            array.* = undefined;
        }

        fn size(capacity: usize) usize {
            const sizeof_skip = @sizeOf(Skip) * (capacity + 1) + @alignOf(Skip);
            const sizeof_data = @sizeOf(Data) * (capacity + 1) + @alignOf(Data);
            return (sizeof_skip + sizeof_data + @sizeOf(Skip) - 1) / @sizeOf(Skip);
        }

        fn full(array: Self) bool {
            return array.first_free_block == null;
        }

        fn empty(array: Self) bool {
            return array.skip[0] == array.capacity;
        }

        fn insertAssumeCapacity(array: *Self) *T {
            std.debug.assert(array.first_free_block != null);

            const ix = array.first_free_block.?;
            const skip = array.skip;
            const data = array.data;

            std.debug.assert(skip[ix] > 0);
            std.debug.assert(skip[ix] == skip[ix + skip[ix] - 1]);
            const free_block = data[ix].node;
            const free_block_len = skip[ix];

            skip[ix + 1] = skip[ix] - 1;
            if (skip[ix] > 2) skip[ix + skip[ix] - 1] -= 1;
            skip[ix] = 0;
            std.debug.assert(skip[ix + 1] < array.capacity - ix);

            data[ix] = .{ .value = undefined };

            if (free_block_len > 1) {
                data[ix + 1] = .{ .node = .{
                    .prev = ix + 1,
                    .next = if (free_block.next != ix) free_block.next else @intCast(ix + 1),
                } };
                if (free_block.next != ix) {
                    data[free_block.next].node.prev = ix + 1;
                }
                array.first_free_block.? += 1;
            } else {
                // free block is exhausted, remove from free list
                std.debug.assert(free_block.prev == ix);
                if (free_block.next != ix) {
                    data[free_block.next].node.prev = free_block.next;
                    array.first_free_block = free_block.next;
                } else {
                    // segment is completely full
                    array.first_free_block = null;
                }
            }

            return &array.data[ix].value;
        }

        fn erase(array: *Self, ix: Skip) T {
            const skip = array.skip;
            const data = array.data;

            std.debug.assert(skip[ix] == 0);
            const value = data[ix].value;

            const skip_left = if (ix == 0) 0 else skip[ix - 1];
            const skip_right = skip[ix + 1]; // NOTE may index into the padding skipfield
            // there are four options for the free block
            // a) both neighbours occupied, form new free block
            // b/c) one neighbour occupied (left/right), extend free block
            // d) both neighbours free, merge into the free block on the left
            // and the way to determine the case is to look at the skipfields
            if (skip_left == 0 and skip_right == 0) {
                skip[ix] = 1;
                data[ix] = .{ .node = .{
                    .prev = ix,
                    .next = array.first_free_block orelse ix,
                } };
                if (array.first_free_block) |first| array.data[first].node.prev = ix;
                array.first_free_block = ix;
            } else if (skip_left > 0 and skip_right == 0) {
                const new_block_len = skip_left + 1;
                skip[ix - skip[ix - 1]] = new_block_len;
                skip[ix] = new_block_len;
            } else if (skip_left == 0 and skip_right > 0) {
                const new_block_len = skip_right + 1;
                skip[ix + skip[ix + 1]] = new_block_len;
                skip[ix] = new_block_len;
                const old_block = data[ix + 1].node;
                data[ix] = .{ .node = .{
                    .prev = if (old_block.prev != ix + 1) old_block.prev else ix,
                    .next = if (old_block.next != ix + 1) old_block.next else ix,
                } };
                // since the free block has moved one step over, update the linked list
                if (old_block.prev == ix + 1) {
                    array.first_free_block = ix;
                } else {
                    data[old_block.prev].node.next = ix;
                }
                if (old_block.next != ix + 1) {
                    data[old_block.next].node.prev = ix;
                }
            } else if (skip_left > 0 and skip_right > 0) {
                const new_block_len = skip_left + skip_right + 1;
                skip[ix - skip[ix - 1]] = new_block_len;
                skip[ix + skip[ix + 1]] = new_block_len;
                // now remove the skip block on the right
                const old_block = data[ix + 1].node;
                if (old_block.prev != ix + 1) {
                    data[old_block.prev].node.next = if (old_block.next != ix + 1)
                        old_block.next
                    else
                        old_block.prev;
                } else {
                    array.first_free_block = if (old_block.next != ix + 1)
                        old_block.next
                    else
                        null;
                }
                if (old_block.next != ix + 1) {
                    data[old_block.next].node.prev = if (old_block.prev != ix + 1)
                        old_block.prev
                    else
                        old_block.next;
                }
            } else unreachable;

            return value;
        }

        fn getIndex(array: *Self, ptr: *T) ?Skip {
            const ptr_addr = @intFromPtr(ptr);
            const data_addr = @intFromPtr(array.data);
            if (ptr_addr < data_addr or
                ptr_addr >= data_addr + array.capacity * @sizeOf(T)) return null;
            return @intCast((@intFromPtr(ptr) - @intFromPtr(array.data)) / @sizeOf(T));
        }

        const Iterator = struct {
            const Cursor =
                switch (Skip) {
                    u16 => u32,
                    u32 => u64,
                    else => @compileError("unsupported skipfield size"),
                };

            cursor: Cursor,
            capacity: usize,
            data: [*]Data,
            skip: [*]Skip,

            const dummy: Iterator = .{
                .cursor = std.math.maxInt(Cursor),
                .capacity = 0,
                .data = undefined,
                .skip = undefined,
            };

            fn next(it: *Iterator) ?*T {
                if (it.cursor >= it.capacity) return null;
                const value_ptr = &it.data[it.cursor].value;
                it.cursor += 1;
                it.cursor += it.skip[it.cursor];
                return value_ptr;
            }
        };

        fn iterator(array: *Self) Iterator {
            return .{
                .cursor = array.skip[0],
                .capacity = array.capacity,
                .data = array.data,
                .skip = array.skip,
            };
        }

        fn debugPrint(array: Self) void {
            std.debug.print("StaticSkipArray <{s}>, ", .{@typeName(T)});
            std.debug.print("skipfield size: {s}, ", .{@typeName(Skip)});
            std.debug.print("capacity: {}\n", .{array.capacity});
            std.debug.print("  skip:", .{});
            for (array.skip[0 .. array.capacity + 1]) |skip| std.debug.print(" {}", .{skip});
            std.debug.print("\n", .{});
            std.debug.print("  freelist: ", .{});
            if (array.first_free_block) |first_free_block| {
                var i = first_free_block;
                while (true) {
                    const node = array.data[i].node;
                    std.debug.print("({} [{}] {})", .{ node.prev, i, node.next });
                    if (node.next == i) break;
                    std.debug.print("->", .{});
                    i = node.next;
                }
            } else {
                std.debug.print("[StaticSkipArray is full]", .{});
            }
            std.debug.print("\n", .{});
        }
    };
}
