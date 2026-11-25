const std = @import("std");

pub const Vulkan = @import("VulkanContext.zig");

pub const Window = *anyopaque;

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
    temporary: bool = false,
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
    device_address: u18,
    texture: *const Texture,

    info: struct {
        view_type: ViewType,
        format: Format,
        swizzle: ViewSwizzle,
        range: ViewRange,
        name: [:0]const u8,
    },
};

pub const BufferCreateInfo = struct {
    size: usize,
    temporary: bool = false,
    group: ?*const Group = null,
    name: [:0]const u8 = &.{},
};

pub const Buffer = struct {
    group: *const Group,
    device_address: u64,

    info: struct {
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
    compare_op: ?CompareOp = null,
    min_lod: f32 = 0.0,
    max_lod: ?f32 = null,
    name: [:0]const u8 = &.{},
};

pub const Sampler = struct {
    device_address: u10,

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
};

pub const Swapchain = struct {
    info: struct {
        name: [:0]const u8,
        present_mode: PresentMode,
        composition: Composition,
        size: [3]u32,
    },
};
pub const MultisampleState = struct {
    sample_count: SampleCount = .count_1,
    enable_alpha_to_coverage: bool = false,
};

pub const TextureUsage = struct {
    storage: bool = false,
    sampled: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    attachment: bool = false, // color or depth_stencil is inferred based on format
};

pub const ColorWriteMask = struct {
    r: bool = true,
    g: bool = true,
    b: bool = true,
    a: bool = true,
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

pub const AddressMode = enum {
    repeat,
    mirrored_repeat,
    clamp_to_edge,
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

pub const Stage = enum { vertex, fragment, compute };

pub const PresentMode = enum {
    fifo,
    mailbox,
};

pub const Composition = enum {
    sdr,
};

pub const StagingAllocatorUsage = enum {
    upload,
    download,
};

pub const Filter = enum {
    nearest,
    linear,
};

pub const TextureType = enum {
    texture_2d,
    texture_3d,
    texture_cube,
    texture_2d_array,
    texture_cube_array,
};

pub const Format = enum {
    r8g8b8a8_unorm,
    r8g8b8a8_srgb,
    r16g16b16a16_sfloat,
    r32_uint,
    s8_uint,
    d16_unorm,
    d24_unorm_s8_uint,
    d32_sfloat,
    d32_sfloat_s8_uint,
    // TODO check for other particularly useful and well supported formats
};

pub const PolygonMode = enum {
    fill,
    line,
    point,
};

pub const SampleCount = enum {
    count_1,
    count_2,
    count_4,
    count_8,
};

pub const Aspect = enum {
    depth,
    stencil,
};

pub const ViewRange = struct {
    base_mip_level: u32,
    level_count: u32,
    base_array_layer: u32,
    layer_count: u32,
    aspect: ?Aspect = null,
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

pub const ViewType = enum {
    view_2d,
    view_3d,
    view_cube,
    view_2d_array,
    view_cube_array,
};

pub const TextureRegion = struct {
    bounds: [2][3]u32,
    mip_level: u32,
};

pub const TextureCopyRegion = struct {
    src_offset: [3]u32,
    src_mip_level: u32,
    dst_offset: [3]u32,
    dst_mip_level: u32,
    extent: [3]u32,
    aspect: ?Aspect = null,
};

pub const BlitRegion = struct {
    bounds: [2][3]i32,
    mip_level: u32,
};

pub const RenderingAttachment = struct {
    view: *const View,
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

pub const DynamicState = struct {
    viewport: Viewport,
    scissor: Scissor,
    input_assembly: InputAssemblyState = .{},
    rasterization: RasterizationState = .{},
    depth_stencil: DepthStencilState = .{},
    blend_constants: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
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

pub const DrawIndexedIndirectCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    _vertex_offset: i32 = 0, // not supported
    _first_instance: u32 = 0, // not supported
};

pub const DispatchIndirectCommand = extern struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const Fence = enum(u64) { _ };

pub const Context = struct {
    pub const Error = error{
        Platform,
        OutOfMemory,
        OutOfDeviceMemory,
        Unsupported,
        Timeout,
        DeviceLost,
        Unknown,
    };

    pub const VTable = struct {
        createSwapchain: *const fn (*anyopaque, SwapchainCreateInfo, ?*const Swapchain) Error!*const Swapchain,
        destroySwapchain: *const fn (*anyopaque, *const Swapchain) void,
        acquireSwapchain: *const fn (*anyopaque, *const Swapchain, u64) Error!bool,

        createGroup: *const fn (*anyopaque, GroupCreateInfo) Error!*const Group,
        createBuffer: *const fn (*anyopaque, BufferCreateInfo) Error!*const Buffer,
        createTexture: *const fn (*anyopaque, TextureCreateInfo) Error!*const Texture,
        createSampler: *const fn (*anyopaque, SamplerCreateInfo) Error!*const Sampler,
        createShader: *const fn (*anyopaque, ShaderCreateInfo) Error!*const Shader,
        createGraphicsPipeline: *const fn (*anyopaque, GraphicsPipelineCreateInfo) Error!*const GraphicsPipeline,
        createComputePipeline: *const fn (*anyopaque, ComputePipelineCreateInfo) Error!*const ComputePipeline,

        destroyGroup: *const fn (*anyopaque, *const Group) void,
        destroyBuffer: *const fn (*anyopaque, *const Buffer) void,
        destroyTexture: *const fn (*anyopaque, *const Texture) void,
        destroySampler: *const fn (*anyopaque, *const Sampler) void,
        destroyShader: *const fn (*anyopaque, *const Shader) void,
        destroyGraphicsPipeline: *const fn (*anyopaque, *const GraphicsPipeline) void,
        destroyComputePipeline: *const fn (*anyopaque, *const ComputePipeline) void,

        stagingAllocator: *const fn (*anyopaque, StagingAllocatorUsage) std.mem.Allocator,
        invalidate: *const fn (*anyopaque, []const u8) void, // for download staging allocator, call before reading, possibly a noop

        acquireCommandList: *const fn (*anyopaque) CommandList,
        submit: *const fn (*anyopaque, []const CommandList) Error!Fence,

        wait: *const fn (*anyopaque, Fence, u64) Error!void,

        setBufferGroup: *const fn (*anyopaque, *const Buffer, ?*const Group) void,
        setTextureGroup: *const fn (*anyopaque, *const Texture, ?*const Group) void,

        // some more things to consider
        // textureSupported
    };

    pub fn createSwapchain(ctx: Context, create_info: SwapchainCreateInfo, recreate: ?*const Swapchain) Error!*const Swapchain {
        return ctx.vtable.createSwapchain(ctx.ptr, create_info, recreate);
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
    pub fn stagingAllocator(ctx: Context, usage: StagingAllocatorUsage) std.mem.Allocator {
        return ctx.vtable.stagingAllocator(ctx.ptr, usage);
    }

    ptr: *anyopaque,
    vtable: *const VTable,
};

pub const CommandList = struct {
    pub const Error = error{
        OutOfMemory,
    };

    pub const VTable = struct {
        // in principle anything could fail (from e.g. out of memory when appending the command)
        // but such failures will just error on submit instead to make the handling easier

        // copies to/from upload/download staging buffers (from a stagingAllocator)
        // (which are handled via mapped as []u8 cpu memory)
        bufferUpload: *const fn (*anyopaque, []const u8, *const Buffer, u64) void,
        bufferDownload: *const fn (*anyopaque, *const Buffer, u64, []u8) void,
        textureUpload: *const fn (*anyopaque, []const u8, *const Texture, TextureRegion) void,
        textureDownload: *const fn (*anyopaque, *const Texture, TextureRegion, []u8) void,

        // copies between gpu side buffers or textures
        bufferCopy: *const fn (*anyopaque, *const Buffer, u64, *const Buffer, u64, u64) void,
        textureCopy: *const fn (*anyopaque, *const Texture, *const Texture, TextureCopyRegion) void,
        blit: *const fn (*anyopaque, *const Texture, BlitRegion, *const Texture, BlitRegion, Filter) void,

        // put data in a temporary buffer with lifetime equal to this command buffer
        // return a device address, replaces uniforms and "single use" streamed buffers
        pushTmp: *const fn (*anyopaque, []const u8) Error!u64,

        beginRenderPass: *const fn (*anyopaque, []const RenderingAttachment, ?*RenderingAttachment, ?*RenderingAttachment) void,
        bindGraphicsPipeline: *const fn (*anyopaque, *const GraphicsPipeline, DynamicState) void,
        // takes a single gpu pointer for data (which could be in a buffer or from pushTmp)
        // we don't need to specify an instance buffer or offset, just use a device address
        drawIndexed: *const fn (*anyopaque, u64, *const Buffer, u64, u32, u32) void, // root_data index_buffer & offset, index_count instance_count
        // note that we assume stride == @sizeOf(DrawIndexedIndirectCommand), a packed buffer
        drawIndexedIndirect: *const fn (*anyopaque, u64, *const Buffer, u64, *const Buffer, u64, u32) void, // root_data, index_buffer & offset, indirect buffer & offset, draw_count
        drawIndexedIndirectCount: *const fn (*anyopaque, u64, *const Buffer, u64, *const Buffer, u64, *const Buffer, u64, u32) void, // root_data, index_buffer & offset, indirect_buffer & offset, count buffer & offset, max_count
        endRenderPass: *const fn (*anyopaque) void,

        beginComputePass: *const fn (*anyopaque) void,
        bindComputePipeline: *const fn (*anyopaque, *const ComputePipeline) void,
        dispatch: *const fn (*anyopaque, u64, u32, u32, u32) void, // root_data x y z
        dispatchIndirect: *const fn (*anyopaque, u64, *const Buffer, u64) void, // root_data indirect_buffer & offset
        endComputePass: *const fn (*anyopaque) void,

        present: *const fn (*anyopaque, *const Texture, *const Swapchain) void,

        // some more things to consider
        // debugLabel
        // timestamp
    };

    ptr: *anyopaque,
    vtable: *const VTable,
};
