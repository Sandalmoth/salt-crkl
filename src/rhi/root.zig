const std = @import("std");

pub const SwapchainComposition = enum {
    sdr,
};

pub const PresentMode = enum {
    fifo,
    mailbox,
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
    image_2d,
    image_3d,
    image_cube,
    image_2d_array,
    image_cube_array,
};

pub const TextureCreateInfo = struct {
    usage: struct {
        storage: bool = false,
        sampled: bool = false,
        transfer_src: bool = false,
        transfer_dst: bool = false,
        attachment: bool = false, // color or depth_stencil is inferred based on format
    },
    format: Format,
    texture_type: TextureType,
    mip_levels: u32,
    size: [3]u32, // x, y, z or layer_count
    samples: SampleCount = .@"1",
    views: []const TextureViewCreateInfo = &.{},
};

pub const TextureViewCreateInfo = struct {
    view_type: ?enum {
        view_2d,
        view_3d,
        view_cube,
        view_2d_array,
        view_cube_array,
    } = null,
    format: ?Format = null,
    swizzle: struct {
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
    } = .{},
    range: ?struct {
        base_mip_level: u32,
        level_count: u32,
        base_array_layer: u32,
        layer_count: u32,
        mask: ?enum { depth, stencil } = null,
    } = null,
};

pub const Texture = struct {
    default_view_index: u20,
    view_indices: []u20,

    info: struct {
        size: [3]u32,
        format: Format,
        mip_levels: u32,
        sample_count: SampleCount,
        texture_type: TextureType,
    },
};

pub const TextureGroup = struct {};

pub const BufferCreateInfo = struct {
    usage: struct {
        storage: bool = false,
        transfer_src: bool = false,
        transfer_dst: bool = false,
        index: bool = false,
        indirect: bool = false,
    },
    size: usize,
};

pub const Buffer = struct {
    buffer_device_address: u64,
    info: struct {
        size: usize,
    },
};

pub const BufferGroup = struct {};

pub const SamplerCreateInfo = struct {};

pub const Sampler = struct {
    index: u12,
};

pub const Shader = struct {
    const Stage = enum { vertex, fragment, shader };
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

pub const ComputePipelineCreateInfo = struct {};

pub const ComputePipeline = struct {};

pub const StagingAllocatorUsage = enum { upload, download };

pub const Context = struct {
    const Error = error{};

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        createBuffer: *const fn (*anyopaque, BufferCreateInfo) Error!*const Buffer,
        destroyBuffer: *const fn (*anyopaque, *const Buffer) void,

        createTexture: *const fn (*anyopaque, TextureCreateInfo) Error!*const Texture,
        destroyTexture: *const fn (*anyopaque, *const Texture) void,

        createSampler: *const fn (*anyopaque, SamplerCreateInfo) Error!*const Sampler,
        destroySampler: *const fn (*anyopaque, *const Sampler) void,

        stagingAllocator: *const fn (*anyopaque, usage: StagingAllocatorUsage) std.mem.Allocator,
    };
};

pub const CommandBuffer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        bufferUpload: *const fn (*anyopaque, *anyopaque, usize, *const Buffer, u64) void,
    };

    fn bufferUpload(
        cmdbuf: *CommandBuffer,
        src: anytype,
        buf: *const Buffer,
        offset: u64,
    ) void {
        const info = @typeInfo(@TypeOf(src));
        std.debug.assert(info == .pointer);
        const ptr: *anyopaque = switch (info.pointer.size) {
            .slice => @ptrCast(src.ptr),
            else => @ptrCast(src),
        };
        const len: usize = switch (info.pointer.size) {
            .slice => @sizeOf(info.pointer.child) * src.len,
            else => @sizeOf(info.pointer.child),
        };
        cmdbuf.vtable.bufferUpload(cmdbuf, ptr, len, buf, offset);
    }
};

test "yo" {
    const Foo = struct {
        howdy: u32 = 0,

        fn bar(foo: *anyopaque, ptr: *anyopaque, len: usize, buf: *const Buffer, offset: u64) void {
            _ = foo;
            std.debug.print("{*}, {}\n", .{ ptr, len });
            _ = buf;
            _ = offset;
        }
    };

    var foo: Foo = .{};

    const vtable: CommandBuffer.VTable = .{
        .bufferUpload = &Foo.bar,
    };

    var cmdbuf: CommandBuffer = .{
        .ptr = &foo,
        .vtable = &vtable,
    };

    var foos: [3]Foo = .{ foo, foo, foo };
    const foo_slice: []Foo = foos[0..3];

    cmdbuf.bufferUpload(&foo, undefined, 0);
    cmdbuf.bufferUpload(foo_slice, undefined, 0);
}
