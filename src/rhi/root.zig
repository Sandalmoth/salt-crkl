const std = @import("std");

const Window = *anyopaque;

pub const SwapchainComposition = enum {
    sdr,
    // TODO add more options
};

pub const PresentMode = enum {
    fifo,
    mailbox,
    // TODO add more options
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
    @"1",
    @"2",
    @"4",
    @"8",
    @"16",
    @"32",
    @"64",
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

pub const TextureCreateInfo = struct {
    usage: TextureUsage,
    format: Format,
    texture_type: TextureType,
    mip_levels: u32,
    size: [3]u32, // x, y, z or layer_count
    samples: SampleCount = .@"1",
    views: []const TextureViewCreateInfo = &.{},
    group: ?*const Group = null,
};

const ViewSwizzle = struct {
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

const ViewRange = struct {
    base_mip_level: u32,
    level_count: u32,
    base_array_layer: u32,
    layer_count: u32,
    mask: ?enum { depth, stencil } = null,
};

pub const TextureViewCreateInfo = struct {
    view_type: ?ViewType = null,
    format: ?Format = null,
    swizzle: ViewSwizzle = .{},
    range: ?ViewRange,
};

pub const TextureView = struct {
    // So, we wouldn't have addresses for the swapchain texture
    // because it's just more consistent to not put them in our descriptor set i think
    // it's fine for the swapchain texture to have pretty limited usages
    // but it would be kinda awkward to have to check for null everywhere
    // maybe we could make std.math.maxInt(u20) an invalid address?
    // although, seems like basically all desktop hardware supports
    // transfer_src/dst, color_attachment, sampled and storage bits
    // so maybe we should just allow all those operations on the swapchain
    // in which case it will actually have a device address
    device_address: u20,

    info: struct {
        view_type: ViewType,
        format: Format,
        swizzle: ViewSwizzle,
        range: ViewRange,
    },
};

pub const Texture = struct {
    group: *const Group,
    default_view: TextureView,
    views: TextureView,

    info: struct {
        usage: TextureUsage,
        size: [3]u32,
        format: Format,
        mip_levels: u32,
        sample_count: SampleCount,
        texture_type: TextureType,
    },
};

pub const Group = struct {};

pub const BufferUsage = struct {
    storage: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
    index: bool = false,
    indirect: bool = false,
};

pub const BufferCreateInfo = struct {
    usage: BufferUsage,
    size: usize,
    group: ?*const Group = null,
};

pub const Buffer = struct {
    group: *const Group,
    device_address: u64,

    info: struct {
        usage: BufferUsage,
        size: usize,
    },
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
    },
};

pub const ShaderCreateInfo = struct {
    stage: Shader.Stage,
    src: []const u8,
};

pub const Shader = struct {
    const Stage = enum { vertex, fragment, shader };

    info: struct {
        stage: Stage,
    },
};

const GraphicsPipelineCreateInfo = struct {
    const PolygonMode = enum {
        fill,
        line,
        point,
    };
    const MultisampleState = struct {
        sample_count: SampleCount = .@"1",
        enable_alpha_to_coverage: bool = false,
    };
    const ColorAttachment = struct {
        const ColorWriteMask = struct {
            r: bool = true,
            g: bool = true,
            b: bool = true,
            a: bool = true,
        };

        const BlendState = struct {
            const BlendFactor = enum {
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

            const BlendOp = enum {
                add,
                subtract,
                reverse_subtract,
                min,
                max,
            };

            src_color_blend_factor: BlendFactor,
            dst_color_blend_factor: BlendFactor,
            color_blend_op: BlendOp,
            src_alpha_blend_factor: BlendFactor,
            dst_alpha_blend_factor: BlendFactor,
            alpha_blend_op: BlendOp,
        };

        format: Format,
        color_write_mask: ColorWriteMask = .{},
        blend_state: ?BlendState = null,
    };

    vertex_shader: *const Shader,
    fragment_shader: ?*const Shader,
    polygon_mode: PolygonMode = .fill,
    multisample: MultisampleState = .{},
    color_attachments: []const ColorAttachment,
    depth_attachment_format: ?Format,
    stencil_attachment_format: ?Format,
};

const CompareOp = enum {
    never,
    less,
    equal,
    less_or_equal,
    greater,
    not_equal,
    greater_or_equal,
    always,
};

pub const GraphicsPipeline = struct {
    const DynamicState = struct {
        const Viewport = extern struct {
            x: f32 = 0.0,
            y: f32 = 0.0,
            width: f32,
            height: f32,
            min_depth: f32,
            max_depth: f32,
        };
        const Scissor = extern struct {
            x: i32 = 0,
            y: i32 = 0,
            width: u32,
            height: u32,
        };
        const InputAssemblyState = struct {
            const PrimitiveTopology = enum {
                point_list,
                line_list,
                line_strip,
                triangle_list,
                triangle_strip,
                triangle_fan,
            };
            primitive_topology: PrimitiveTopology = .triangle_list,
            enable_primitive_restart: bool = false,
        };
        const RasterizationState = struct {
            const CullMode = struct {
                front: bool = false,
                back: bool = false,
            };
            const FrontFace = enum {
                counter_clockwise,
                clockwise,
            };
            const DepthBias = struct {
                constant_factor: f32,
                clamp: f32,
                slope_factor: f32,
            };

            enable_rasterizer_discard: bool = false,
            cull_mode: CullMode = .{ .back = true },
            front_face: FrontFace = .counter_clockwise,
            depth_bias: ?DepthBias = null,
        };
        const DepthStencilState = struct {
            const StencilState = struct {
                const StencilOp = enum {
                    keep,
                    zero,
                    replace,
                    increment_and_clamp,
                    decrement_and_clamp,
                    invert,
                    increment_and_wrap,
                    decrement_and_wrap,
                };
                const StencilOpState = struct {
                    fail_op: StencilOp,
                    pass_op: StencilOp,
                    depth_fail_op: StencilOp,
                    compare_op: CompareOp,
                    compare_mask: u32 = 0xFFFFFFFF,
                    write_mask: u32 = 0xFFFFFFFF,
                    reference: u32 = 0x00000000,
                };

                front: StencilOpState,
                back: StencilOpState,
            };

            depth_test: ?CompareOp = .greater,
            enable_depth_write: bool = true,
            stencil_test: ?StencilState = null,
        };

        viewport: Viewport,
        scissor: Scissor,
        input_assembly: InputAssemblyState = .{},
        rasterization: RasterizationState = .{},
        depth_stencil: DepthStencilState = .{},
        blend_constants: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    info: struct {
        fragment_shader: bool,
        polygon_mode: GraphicsPipelineCreateInfo.PolygonMode,
        multisample: GraphicsPipelineCreateInfo.MultisampleState,
        color_attachments: []const GraphicsPipelineCreateInfo.ColorAttachment,
        depth_attachment_format: ?Format,
        stencil_attachment_format: ?Format,
    },
};

pub const ComputePipelineCreateInfo = struct {
    shader: *const Shader,
    local_size: [3]u32,
};

pub const ComputePipeline = struct {
    info: struct {
        local_size: [3]u32,
    },
};

pub const StagingAllocatorUsage = enum { upload, download };

pub const Queue = enum { graphics, compute, transfer };

pub const Fence = struct {
    graphics: u64,
    compute: u64,
    transfer: u64,
};

pub const Context = struct {
    const Error = error{
        OutOfHostMemory,
        OutOfDeviceMemory,
        Timeout,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        claimWindow: *const fn (*anyopaque, Window) Error!void,
        releaseWindow: *const fn (*anyopaque, Window) Error!void,

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

        acquireCommandBuffer: *const fn (*anyopaque, Queue) Error!*CommandBuffer,
        submit: *const fn (*anyopaque, []CommandBuffer) Error!Fence,
        waitQueue: *const fn (*anyopaque, Fence, Queue, u64) Error!void,
        waitFence: *const fn (*anyopaque, Fence, u64) Error!void,
        testQueue: *const fn (*anyopaque, Fence, Queue) bool,
        testFence: *const fn (*anyopaque, Fence) bool,

        setGroupBuffer: *const fn (*anyopaque, *const Buffer, ?*const Group) void,
        setGroupTexture: *const fn (*anyopaque, *const Texture, ?*const Group) void,

        readTimestamp: *const fn (*anyopaque, Timestamp) ?u64,
    };
};

pub const BlitRegion = struct {
    bounds: [2][3]i32,
    mip_level: u32,
};

pub const ResolveRegion = struct {
    src_offset: [3]i32,
    src_mip_level: u32,
    dst_offset: [3]i32,
    dst_mip_level: u32,
    extent: [3]u32,
};

const RenderingAttachment = struct {
    const LoadOp = enum {
        load,
        clear,
        dont_care,
    };
    const StoreOp = enum {
        store,
        dont_care,
        none,
    };
    const ClearValue = union(enum) {
        color: union(enum) {
            float: [4]f32,
            int: [4]i32,
            uint: [4]u32,
        },
        depth_stencil: struct {
            depth: f32,
            stencil: u8,
        },

        pub fn float(r: f32, g: f32, b: f32, a: f32) ClearValue {
            return .{ .color = .{ .float = .{ r, g, b, a } } };
        }
        pub fn int(r: i32, g: i32, b: i32, a: i32) ClearValue {
            return .{ .color = .{ .int = .{ r, g, b, a } } };
        }
        pub fn uint(r: u32, g: u32, b: u32, a: u32) ClearValue {
            return .{ .color = .{ .uint = .{ r, g, b, a } } };
        }
        pub fn depthStencil(depth: f32, stencil: u8) ClearValue {
            return .{ .depth_stencil = .{ .depth = depth, .stencil = stencil } };
        }
    };

    texture: *const Texture,
    view: ?*const TextureView = null, // defaults to default_view
    load_op: LoadOp,
    store_op: StoreOp,
    clear_value: ?ClearValue = null,
};

const RenderPassAccess = struct {
    color_attachments: []const RenderingAttachment = &.{},
    depth_attachment: ?RenderingAttachment = null,
    stencil_attachment: ?RenderingAttachment = null,
    vertex_read_groups: []const Group = &.{},
    fragment_read_groups: []const Group = &.{},
    vertex_write_groups: []const Group = &.{},
    fragment_write_groups: []const Group = &.{},
};

const ComputePassAccess = struct {
    read_groups: []const Group = &.{},
    write_groups: []const Group = &.{},
};

const Timestamp = enum(u32) { _ };

pub const CommandBuffer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        bufferUpload: *const fn (*anyopaque, *anyopaque, usize, *const Buffer, u64) void,
        bufferDownload: *const fn (*anyopaque, *const Buffer, u64, *anyopaque, usize) void,
        textureUpload: *const fn (*anyopaque, *anyopaque, usize, *const Texture, u64) void,
        textureDownload: *const fn (*anyopaque, *const Texture, u64, *anyopaque, usize) void,

        waitAndAcquireSwapchainTexture: *const fn (*anyopaque, Window) *const Texture,

        bufferCopy: *const fn (*anyopaque, *const Buffer, u64, *const Buffer, u64, u64) void,
        textureCopy: *const fn (*anyopaque, *const Texture, *const Texture) void, // TODO args
        blit: *const fn (*anyopaque, *const Texture, BlitRegion, *const Texture, BlitRegion, Filter) void,
        resolve: *const fn (*anyopaque, *const Texture, *const Texture, ResolveRegion) void,

        beginRenderPass: *const fn (*anyopaque, RenderPassAccess) *RenderPass,
        endRenderPass: *const fn (*anyopaque, *RenderPass) void,
        beginComputePass: *const fn (*anyopaque, ComputePassAccess) *RenderPass,
        endComputePass: *const fn (*anyopaque, *RenderPass) void,

        timestamp: *const fn (*anyopaque) ?Timestamp,
    };

    // generics will have to be wrapped like this
    // fn bufferUpload(
    //     cmdbuf: *CommandBuffer,
    //     src: anytype,
    //     buf: *const Buffer,
    //     offset: u64,
    // ) void {
    //     const info = @typeInfo(@TypeOf(src));
    //     std.debug.assert(info == .pointer);
    //     const ptr: *anyopaque = switch (info.pointer.size) {
    //         .slice => @ptrCast(src.ptr),
    //         else => @ptrCast(src),
    //     };
    //     const len: usize = switch (info.pointer.size) {
    //         .slice => @sizeOf(info.pointer.child) * src.len,
    //         else => @sizeOf(info.pointer.child),
    //     };
    //     cmdbuf.vtable.bufferUpload(cmdbuf, ptr, len, buf, offset);
    // }
};

pub const DrawIndexedIndirectCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
};

pub const RenderPass = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        pushConstant: *const fn (*anyopaque, *anyopaque, usize) void, // TODO generic wrap
        bindPipeline: *const fn (*anyopaque, *const GraphicsPipeline, GraphicsPipeline.DynamicState) void,
        drawIndexed: *const fn (*anyopaque, u32, u32, u32, i32, u32) void,
        drawIndexedIndirect: *const fn (*anyopaque, *const Buffer, u64, u32) void,
        drawIndexedIndirectCount: *const fn (*anyopaque, *const Buffer, u64, *const Buffer, u64, u32) void,
    };
};

pub const DispatchIndirectCommand = extern struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const ComputePass = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        pushConstant: *const fn (*anyopaque, *anyopaque, usize) void, // TODO generic wrap
        bindPipeline: *const fn (*anyopaque, *const ComputePipeline) void,
        dispatch: *const fn (*anyopaque, u32, u32, u32) void,
        dispatchIndirect: *const fn (*anyopaque, *const Buffer, u64) void,
    };
};
