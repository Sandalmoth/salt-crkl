const std = @import("std");

pub const Vulkan = @import("VulkanContext.zig");

pub const Window = *anyopaque;

// enums and config/helper structs

pub const PresentMode = enum {
    fifo,
    mailbox,
};

pub const Composition = enum {
    sdr,
};

pub const Format = enum {
    r8g8b8a8_unorm,
    r8g8b8a8_srgb,
    b8g8r8a8_unorm,
    b8g8r8a8_srgb,
    r16g16b16a16_sfloat,
    r32_uint,
    s8_uint,
    d16_unorm,
    d16_unorm_s8_uint,
    d24_unorm_s8_uint,
    d32_sfloat,
    d32_sfloat_s8_uint,
    // TODO check for other particularly useful and well supported formats
};

pub const SampleCount = enum {
    count_1,
    count_2,
    count_4,
    count_8,
    count_16,
    count_32,
    count_64,
};

pub const TextureType = enum {
    texture_2d,
    texture_3d,
    texture_cube,
    texture_2d_array,
    texture_cube_array,
};

pub const ViewType = enum {
    view_2d,
    view_3d,
    view_cube,
    view_2d_array,
    view_cube_array,
};

pub const TextureUsage = struct {
    storage: bool = false,
    sampled: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    attachment: bool = false, // color or depth_stencil is inferred based on format
};

pub const ViewSwizzle = struct {
    const Component = enum {
        zero,
        one,
        r,
        g,
        b,
        a,
    };
    r: Component = .r,
    g: Component = .g,
    b: Component = .b,
    a: Component = .a,
};

pub const ViewRange = struct {
    base_mip_level: u32,
    level_count: u32,
    base_array_layer: u32,
    layer_count: u32,
    mask: ?enum { depth, stencil } = null,
};

pub const BufferUsage = struct {
    storage: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    index: bool = false,
    indirect: bool = false,
};

pub const Filter = enum {
    nearest,
    linear,
};

pub const AddressMode = enum {
    repeat,
    mirrored_repeat,
    clamp_to_edge,
};

pub const PolygonMode = enum {
    fill,
    line,
    point,
};

pub const MultisampleState = struct {
    sample_count: SampleCount = .count_1,
    enable_alpha_to_coverage: bool = false,
};

pub const ColorWriteMask = struct {
    r: bool = true,
    g: bool = true,
    b: bool = true,
    a: bool = true,
};

pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,
    constant_color,
    one_minus_constant_color,
    constant_alpha,
    one_minus_constant_alpha,
    src_alpha_saturate,
};

pub const BlendOp = enum {
    add,
    subtract,
    reverse_subtract,
    min,
    max,
};

pub const BlendState = struct {
    src_color_blend_factor: BlendFactor,
    dst_color_blend_factor: BlendFactor,
    color_blend_op: BlendOp,
    src_alpha_blend_factor: BlendFactor,
    dst_alpha_blend_factor: BlendFactor,
    alpha_blend_op: BlendOp,
};

pub const ColorAttachment = struct {
    format: Format,
    color_write_mask: ColorWriteMask = .{},
    blend_state: ?BlendState = null,
};

pub const CompareOp = enum {
    never,
    less,
    equal,
    less_or_equal,
    greater,
    not_equal,
    greater_or_equal,
    always,
};

pub const Viewport = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    width: f32,
    height: f32,
    min_depth: f32,
    max_depth: f32,
};

pub const Scissor = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32,
    height: u32,
};

pub const PrimitiveTopology = enum {
    point_list,
    line_list,
    line_strip,
    triangle_list,
    triangle_strip,
    triangle_fan,
};

pub const InputAssemblyState = struct {
    primitive_topology: PrimitiveTopology = .triangle_list,
    enable_primitive_restart: bool = false,
};

pub const CullMode = struct {
    front: bool = false,
    back: bool = false,
};

pub const FrontFace = enum {
    counter_clockwise,
    clockwise,
};

pub const DepthBias = struct {
    constant_factor: f32,
    clamp: f32,
    slope_factor: f32,
};

pub const RasterizationState = struct {
    cull_mode: CullMode = .{ .back = true },
    front_face: FrontFace = .counter_clockwise,
    depth_bias: ?DepthBias = null,
};

pub const StencilOp = enum {
    keep,
    zero,
    replace,
    increment_and_clamp,
    decrement_and_clamp,
    invert,
    increment_and_wrap,
    decrement_and_wrap,
};

pub const StencilOpState = struct {
    fail_op: StencilOp,
    pass_op: StencilOp,
    depth_fail_op: StencilOp,
    compare_op: CompareOp,
    compare_mask: u32 = 0xFFFFFFFF,
    write_mask: u32 = 0xFFFFFFFF,
    reference: u32 = 0x00000000,
};

pub const StencilState = struct {
    front: StencilOpState,
    back: StencilOpState,
};

pub const DepthStencilState = struct {
    depth_test: ?CompareOp = .greater,
    enable_depth_write: bool = true,
    stencil_test: ?StencilState = null,
};

pub const DynamicState = struct {
    viewport: Viewport,
    scissor: Scissor,
    input_assembly: InputAssemblyState = .{},
    rasterization: RasterizationState = .{},
    depth_stencil: DepthStencilState = .{},
    blend_constants: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
};

pub const StagingAllocatorUsage = enum { upload, download };

pub const Queue = enum { graphics, compute, transfer };

pub const BlitRegion = struct {
    bounds: [2][3]i32,
    mip_level: u32,
};

pub const LoadOp = enum {
    load,
    clear,
    dont_care,
};

pub const StoreOp = enum {
    store,
    dont_care,
    none,
};

pub const ClearValue = union(enum) {
    color: union(enum) {
        float: [4]f32,
        int: [4]i32,
        uint: [4]u32,
    },
    depth_stencil: struct {
        depth: f32,
        stencil: u8,
    },

    pub fn float(values: [4]f32) ClearValue {
        return .{ .color = .{ .float = values } };
    }
    pub fn int(values: [4]i32) ClearValue {
        return .{ .color = .{ .int = values } };
    }
    pub fn uint(values: [4]u32) ClearValue {
        return .{ .color = .{ .uint = values } };
    }
    pub fn depthStencil(depth: f32, stencil: u8) ClearValue {
        return .{ .depth_stencil = .{ .depth = depth, .stencil = stencil } };
    }
};

pub const RenderingAttachment = struct {
    texture: *const Texture,
    view: ?*const View = null, // defaults to default_view
    load_op: LoadOp,
    store_op: StoreOp,
    clear_value: ?ClearValue = null,
};

pub const RenderPassAccess = struct {
    color_attachments: []const RenderingAttachment = &.{},
    depth_attachment: ?RenderingAttachment = null,
    stencil_attachment: ?RenderingAttachment = null,
    vertex_read_groups: []const Group = &.{},
    fragment_read_groups: []const Group = &.{},
    fragment_write_groups: []const Group = &.{},
};

pub const ComputePassAccess = struct {
    read_groups: []const Group = &.{},
    write_groups: []const Group = &.{},
};

pub const Present = struct {
    swapchain: *const Swapchain,
    texture: *const Texture,
};

pub const DrawIndexedIndirectCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
};

pub const DispatchIndirectCommand = extern struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const TimestampStage = enum {
    top,
    bottom,
};

pub const Fence = struct {
    graphics: ?u64,
    compute: ?u64,
    transfer: ?u64,
};

pub const FenceMask = struct {
    graphics: bool = true,
    compute: bool = true,
    transfer: bool = true,
};

pub const Stage = enum { vertex, fragment, compute };

// objects

pub const GroupCreateInfo = struct {
    name: [:0]const u8 = &.{},
};

pub const Group = struct {
    info: struct {
        name: [:0]const u8,
    },
};

pub const TextureCreateInfo = struct {
    usage: TextureUsage,
    format: Format,
    texture_type: TextureType,
    mip_levels: u32,
    size: [3]u32, // x, y, z or layer_count
    samples: SampleCount = .count_1,
    views: []const ViewCreateInfo = &.{},
    group: ?*const Group = null,
    name: [:0]const u8 = &.{},
};

pub const Texture = struct {
    group: *const Group,
    default_view: *const View,
    views: []const View,

    info: struct {
        usage: TextureUsage,
        size: [3]u32,
        format: Format,
        mip_levels: u32,
        sample_count: SampleCount,
        texture_type: TextureType,
        name: [:0]const u8,
    },
};

pub const ViewCreateInfo = struct {
    view_type: ?ViewType = null,
    format: ?Format = null,
    swizzle: ViewSwizzle = .{},
    range: ?ViewRange,
    name: [:0]const u8 = &.{},
};

pub const View = struct {
    device_address: u20,

    info: struct {
        view_type: ViewType,
        format: Format,
        swizzle: ViewSwizzle,
        range: ViewRange,
        name: [:0]const u8,
    },
};

pub const BufferCreateInfo = struct {
    usage: BufferUsage,
    size: usize,
    group: ?*const Group = null,
    name: [:0]const u8 = &.{},
};

pub const Buffer = struct {
    group: *const Group,
    device_address: u64,

    info: struct {
        usage: BufferUsage,
        size: usize,
        name: [:0]const u8,
    },
};

pub const SamplerCreateInfo = struct {
    mag_filter: Filter,
    min_filter: Filter,
    mipmap_filter: Filter,
    address_mode_u: AddressMode,
    address_mode_v: AddressMode,
    address_mode_w: AddressMode,
    mip_lod_bias: f32 = 0.0,
    max_anisotropy: ?f32 = null,
    compare_op: ?CompareOp,
    min_lod: f32 = 0.0,
    max_lod: ?f32 = null,
    name: [:0]const u8 = &.{},
};

pub const Sampler = struct {
    device_address: u12,

    info: struct {
        mag_filter: Filter,
        min_filter: Filter,
        mipmap_filter: Filter,
        address_mode_u: AddressMode,
        address_mode_v: AddressMode,
        address_mode_w: AddressMode,
        mip_lod_bias: f32 = 0.0,
        max_anisotropy: ?f32 = null,
        compare_op: ?CompareOp,
        min_lod: f32 = 0.0,
        max_lod: ?f32 = null,
        name: [:0]const u8 = &.{},
    },
};

pub const ShaderCreateInfo = struct {
    stage: Stage,
    src: []const u8,
    name: [:0]const u8 = &.{},
};

pub const Shader = struct {
    info: struct {
        stage: Stage,
        name: [:0]const u8,
    },
};

pub const GraphicsPipelineCreateInfo = struct {
    vertex_shader: *const Shader,
    fragment_shader: ?*const Shader,
    polygon_mode: PolygonMode = .fill,
    multisample: MultisampleState = .{},
    color_attachments: []const ColorAttachment,
    depth_attachment_format: ?Format,
    stencil_attachment_format: ?Format,
    name: [:0]const u8 = &.{},
};

pub const GraphicsPipeline = struct {
    info: struct {
        fragment_shader: bool,
        polygon_mode: PolygonMode,
        multisample: MultisampleState,
        color_attachments: []const ColorAttachment,
        depth_attachment_format: ?Format,
        stencil_attachment_format: ?Format,
        name: [:0]const u8,
    },
};

pub const ComputePipelineCreateInfo = struct {
    shader: *const Shader,
    local_size: [3]u32,
    name: [:0]const u8 = &.{},
};

pub const ComputePipeline = struct {
    info: struct {
        local_size: [3]u32,
        name: [:0]const u8,
    },
};

pub const SwapchainCreateInfo = struct {
    name: [:0]const u8 = &.{},
    window: Window,
    present_mode: PresentMode = .fifo,
    composition: Composition = .sdr,
    recreate: ?*Swapchain = null,
};

pub const Swapchain = struct {
    info: struct {
        name: [:0]const u8,
        present_mode: PresentMode,
        composition: Composition,
        size: [3]u32,
    },
};

pub const Context = struct {
    pub const Error = error{
        Platform,
        OutOfMemory,
        OutOfDeviceMemory,
        Unsupported,
        Timeout,
        DeviceLost,
        Unknown,
        // TODO cleanup and narrow down to one uniform set of errors like what's above
        OutOfHostMemory,
        ValidationFailed,
        SurfaceLostKHR,
        OutOfDateKHR,
        FullScreenExclusiveModeLostEXT,
        PresentTimingQueueFullEXT,
        Minimized,
        InvalidVideoStdParametersKHR,
        CompressionExhaustedEXT,
        InvalidOpaqueCaptureAddressKHR,
        InvalidExternalHandle,
        MaxAllocs,
        OutOfSlots,
        InvalidShaderNV,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        createSwapchain: *const fn (*anyopaque, SwapchainCreateInfo) Error!*const Swapchain,
        destroySwapchain: *const fn (*anyopaque, *const Swapchain) void,
        acquireSwapchain: *const fn (*anyopaque, *const Swapchain, u64) Error!bool,

        createBuffer: *const fn (*anyopaque, BufferCreateInfo) Error!*const Buffer,
        createTexture: *const fn (*anyopaque, TextureCreateInfo) Error!*const Texture,
        createSampler: *const fn (*anyopaque, SamplerCreateInfo) Error!*const Sampler,
        createGroup: *const fn (*anyopaque) Error!*const Group,
        createShader: *const fn (*anyopaque, ShaderCreateInfo) Error!*const Shader,
        createGraphicsPipeline: *const fn (*anyopaque, GraphicsPipelineCreateInfo) Error!*const GraphicsPipeline,
        createComputePipeline: *const fn (*anyopaque, ComputePipelineCreateInfo) Error!*const ComputePipeline,

        destroyBuffer: *const fn (*anyopaque, *const Buffer) void,
        destroyTexture: *const fn (*anyopaque, *const Texture) void,
        destroySampler: *const fn (*anyopaque, *const Sampler) void,
        destroyGroup: *const fn (*anyopaque, *const Group) void,
        destroyShader: *const fn (*anyopaque, *const Shader) void,
        destroyGraphicsPipeline: *const fn (*anyopaque, *const GraphicsPipeline) void,
        destroyComputePipeline: *const fn (*anyopaque, *const ComputePipeline) void,

        stagingAllocator: *const fn (*anyopaque, StagingAllocatorUsage) std.mem.Allocator,

        submit: *const fn (*anyopaque, io: std.Io, []const CommandBuffer, []const Present) Error!Fence,
        wait: *const fn (*anyopaque, Fence, FenceMask, u64) Error!void,

        setBufferGroup: *const fn (*anyopaque, *const Buffer, ?*const Group) void,
        setTextureGroup: *const fn (*anyopaque, *const Texture, ?*const Group) void,

        // readTimestamps: *const fn (*anyopaque, []const u8) ?u64, // could maybe happen on wait?
    };

    pub fn createSwapchain(ctx: Context, create_info: SwapchainCreateInfo) Error!*const Swapchain {
        return ctx.vtable.createSwapchain(ctx.ptr, create_info);
    }
    pub fn destroySwapchain(ctx: Context, swapchain: *const Swapchain) void {
        ctx.vtable.destroySwapchain(ctx.ptr, swapchain);
    }
    pub fn acquireSwapchain(ctx: Context, swapchain: *const Swapchain, timeout: u64) Error!bool {
        return ctx.vtable.acquireSwapchain(ctx.ptr, swapchain, timeout);
    }
    pub fn createTexture(ctx: Context, create_info: TextureCreateInfo) Error!*const Texture {
        return ctx.vtable.createTexture(ctx.ptr, create_info);
    }
    pub fn destroyTexture(ctx: Context, texture: *const Texture) void {
        ctx.vtable.destroyTexture(ctx.ptr, texture);
    }
    pub fn createShader(ctx: Context, create_info: ShaderCreateInfo) Error!*const Shader {
        return ctx.vtable.createShader(ctx.ptr, create_info);
    }
    pub fn destroyShader(ctx: Context, shader: *const Shader) void {
        ctx.vtable.destroyShader(ctx.ptr, shader);
    }
    pub fn createGraphicsPipeline(ctx: Context, create_info: GraphicsPipelineCreateInfo) Error!*const GraphicsPipeline {
        return ctx.vtable.createGraphicsPipeline(ctx.ptr, create_info);
    }
    pub fn destroyGraphicsPipeline(ctx: Context, pipeline: *const GraphicsPipeline) void {
        ctx.vtable.destroyGraphicsPipeline(ctx.ptr, pipeline);
    }

    pub fn submit(
        ctx: Context,
        io: std.Io,
        command_buffers: []const CommandBuffer,
        presents: []const Present,
    ) Error!Fence {
        return ctx.vtable.submit(ctx.ptr, io, command_buffers, presents);
    }
};

// NOTE could we design some kind of compile time safety for this
// where calling functions incompatible with the queue
// and where calling illegal functions inside the passes is a compile error
// for now, just have runtime asserts
pub const CommandBuffer = struct {
    // TODO add definitions and functions

    const Command = union(enum) {
        buffer_upload: struct {},
        buffer_download: struct {},
        texture_upload: struct {},
        texture_download: struct {},

        buffer_copy: struct {},
        texture_copy: struct {},
        blit: struct {
            src: *const Texture,
            src_region: BlitRegion,
            dst: *const Texture,
            dst_region: BlitRegion,
            filter: Filter,
        },

        // push_label: [:0]u8,
        // pop_label: void,
        // timestamp: [:0]u8,

        push_constant: []u8,

        begin_render_pass: struct {
            color_attachments: []const RenderingAttachment,
            depth_attachment: ?*const RenderingAttachment,
            stencil_attachment: ?*const RenderingAttachment,
            vertex_read_groups: []const Group,
            fragment_read_groups: []const Group,
            fragment_write_groups: []const Group,
        },
        bind_graphics_pipeline: struct {
            pipeline: *const GraphicsPipeline,
            dynamic_state: *const DynamicState,
        },
        draw_indexed: struct {},
        draw_indexed_indirect: struct {},
        draw_indexed_indirect_count: struct {},
        end_render_pass: void,

        begin_compute_pass: struct {},
        bind_compute_pipeline: struct {},
        dispatch: struct {},
        dispatch_indirect: struct {},
        end_compute_pass: void,
    };

    arena: std.mem.Allocator,
    commands: std.ArrayList(Command), // TODO reimplement segmentedlist (rip as of 0.16) or better

    queue: Queue,
    active_pass: ?enum { render, compute },

    pub fn init(arena: std.mem.Allocator, queue: Queue) CommandBuffer {
        return .{
            .arena = arena,
            .commands = .empty,
            .queue = queue,
            .active_pass = null,
        };
    }

    pub fn blit(
        command_buffer: *CommandBuffer,
        src: *const Texture,
        src_region: BlitRegion,
        dst: *const Texture,
        dst_region: BlitRegion,
        filter: Filter,
    ) void {
        _ = command_buffer;
        _ = src;
        _ = src_region;
        _ = dst;
        _ = dst_region;
        _ = filter;
    }

    pub fn beginRenderPass(
        command_buffer: *CommandBuffer,
        color_attachments: []const RenderingAttachment,
        depth_attachment: ?RenderingAttachment,
        stencil_attachment: ?RenderingAttachment,
        vertex_read_groups: []const Group,
        fragment_read_groups: []const Group,
        fragment_write_groups: []const Group,
    ) !void {
        std.debug.assert(command_buffer.active_pass == null);
        const arena = command_buffer.arena;
        const command = try command_buffer.commands.addOne(arena);
        errdefer _ = command_buffer.commands.pop();
        var depth_attachment_copy: ?*RenderingAttachment = null;
        if (depth_attachment) |attachment| {
            depth_attachment_copy = try arena.create(RenderingAttachment);
            depth_attachment_copy.?.* = attachment;
        }
        var stencil_attachment_copy: ?*RenderingAttachment = null;
        if (stencil_attachment) |attachment| {
            stencil_attachment_copy = try arena.create(RenderingAttachment);
            stencil_attachment_copy.?.* = attachment;
        }
        command.* = .{ .begin_render_pass = .{
            .color_attachments = try arena.dupe(RenderingAttachment, color_attachments),
            .depth_attachment = depth_attachment_copy,
            .stencil_attachment = stencil_attachment_copy,
            .vertex_read_groups = try arena.dupe(Group, vertex_read_groups),
            .fragment_read_groups = try arena.dupe(Group, fragment_read_groups),
            .fragment_write_groups = try arena.dupe(Group, fragment_write_groups),
        } };
        command_buffer.active_pass = .render;
    }

    pub fn bindGraphicsPipeline(
        command_buffer: *CommandBuffer,
        pipeline: *const GraphicsPipeline,
        dynamic_state: DynamicState,
    ) !void {
        const arena = command_buffer.arena;
        const command = try command_buffer.commands.addOne(arena);
        errdefer _ = command_buffer.commands.pop();
        const dynamic_state_copy = try arena.create(DynamicState);
        dynamic_state_copy.* = dynamic_state;
        command.* = .{ .bind_graphics_pipeline = .{
            .pipeline = pipeline,
            .dynamic_state = dynamic_state_copy,
        } };
    }

    pub fn endRenderPass(command_buffer: *CommandBuffer) !void {
        std.debug.assert(command_buffer.active_pass.? == .render);
        const arena = command_buffer.arena;
        const command = try command_buffer.commands.addOne(arena);
        errdefer _ = command_buffer.commands.pop();
        command.* = .{ .end_render_pass = {} };
        command_buffer.active_pass = null;
    }
};

// pub const CommandBuffer = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,

//     pub const VTable = struct {
//         cancel: *const fn (*anyopaque) void,

//         bufferUpload: *const fn (*anyopaque, *anyopaque, usize, *const Buffer, u64) void,
//         bufferDownload: *const fn (*anyopaque, *const Buffer, u64, *anyopaque, usize) void,
//         textureUpload: *const fn (*anyopaque, *anyopaque, usize, *const Texture, u64) void,
//         textureDownload: *const fn (*anyopaque, *const Texture, u64, *anyopaque, usize) void,

//         bufferCopy: *const fn (*anyopaque, *const Buffer, u64, *const Buffer, u64, u64) void,
//         textureCopy: *const fn (*anyopaque, *const Texture, *const Texture) void, // TODO args
//         blit: *const fn (*anyopaque, *const Texture, BlitRegion, *const Texture, BlitRegion, Filter) void,
//         resolve: *const fn (*anyopaque, *const Texture, *const Texture, ResolveRegion) void,

//         beginRenderPass: *const fn (*anyopaque, RenderPassAccess) *RenderPass,
//         endRenderPass: *const fn (*anyopaque, *RenderPass) void,
//         beginComputePass: *const fn (*anyopaque, ComputePassAccess) *RenderPass,
//         endComputePass: *const fn (*anyopaque, *RenderPass) void,

//         waitAndAcquireSwapchainTexture: *const fn (*anyopaque, *const Swapchain) ?*const Texture,

//         timestamp: *const fn (*anyopaque) ?Timestamp,
//     };

//     pub fn cancel(
//         command_buffer: CommandBuffer,
//     ) void {
//         return command_buffer.vtable.cancel(command_buffer.ptr);
//     }
//     pub fn waitAndAcquireSwapchainTexture(
//         command_buffer: CommandBuffer,
//         swapchain: *const Swapchain,
//     ) ?*const Texture {
//         return command_buffer.vtable.waitAndAcquireSwapchainTexture(command_buffer.ptr, swapchain);
//     }

//     // generics will have to be wrapped like this
//     // fn bufferUpload(
//     //     cmdbuf: *CommandBuffer,
//     //     src: anytype,
//     //     buf: *const Buffer,
//     //     offset: u64,
//     // ) void {
//     //     const info = @typeInfo(@TypeOf(src));
//     //     std.debug.assert(info == .pointer);
//     //     const ptr: *anyopaque = switch (info.pointer.size) {
//     //         .slice => @ptrCast(src.ptr),
//     //         else => @ptrCast(src),
//     //     };
//     //     const len: usize = switch (info.pointer.size) {
//     //         .slice => @sizeOf(info.pointer.child) * src.len,
//     //         else => @sizeOf(info.pointer.child),
//     //     };
//     //     cmdbuf.vtable.bufferUpload(cmdbuf, ptr, len, buf, offset);
//     // }
// };

// pub const RenderPass = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,

//     pub const VTable = struct {
//         pushConstant: *const fn (*anyopaque, *anyopaque, usize) void, // TODO generic wrap
//         bindPipeline: *const fn (*anyopaque, *const GraphicsPipeline, GraphicsPipeline.DynamicState) void,
//         drawIndexed: *const fn (*anyopaque, u32, u32, u32, i32, u32) void,
//         drawIndexedIndirect: *const fn (*anyopaque, *const Buffer, u64, u32) void,
//         drawIndexedIndirectCount: *const fn (*anyopaque, *const Buffer, u64, *const Buffer, u64, u32) void,
//     };
// };

// pub const ComputePass = struct {
//     ptr: *anyopaque,
//     vtable: *const VTable,

//     pub const VTable = struct {
//         pushConstant: *const fn (*anyopaque, *anyopaque, usize) void, // TODO generic wrap
//         bindPipeline: *const fn (*anyopaque, *const ComputePipeline) void,
//         dispatch: *const fn (*anyopaque, u32, u32, u32) void,
//         dispatchIndirect: *const fn (*anyopaque, *const Buffer, u64) void,
//     };
// };
