const std = @import("std");
const vk = @import("vulkan");

const log = std.log.scoped(.rhi);

const enable_debug = @import("builtin").mode == .Debug;

const api_version = vk.API_VERSION_1_3;
const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .createInstance = true,
        },
        .instance_commands = .{
            .createDevice = true,
            .destroyInstance = true,
        },
        .device_commands = .{
            .destroyDevice = true,
        },
    },
};

const layers = [_][*:0]const u8{};
const debug_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const instance_extensions = [_][*:0]const u8{
    "VK_KHR_surface",
};
const debug_instance_extensions = [_][*:0]const u8{};

const device_extensions = [_][*:0]const u8{
    "VK_KHR_swapchain",
};
const debug_device_extensions = [_][*:0]const u8{};

const device_properties = vk.PhysicalDeviceProperties2{};
const device_properties_1_1 = vk.PhysicalDeviceVulkan11Properties{};
const device_properties_1_2 = vk.PhysicalDeviceVulkan12Properties{
    .quad_divergent_implicit_lod = vk.TRUE,
};
const device_properties_1_3 = vk.PhysicalDeviceVulkan13Properties{};

const device_features = vk.PhysicalDeviceFeatures{
    .multi_draw_indirect = vk.TRUE,
    .draw_indirect_first_instance = vk.TRUE,
};
const device_features_1_1 = vk.PhysicalDeviceVulkan11Features{
    .p_next = @ptrCast(@constCast(&device_features_1_2)),
    .shader_draw_parameters = vk.TRUE,
};
const device_features_1_2 = vk.PhysicalDeviceVulkan12Features{
    .p_next = @ptrCast(@constCast(&device_features_1_3)),
    .descriptor_indexing = vk.TRUE,
    .buffer_device_address = vk.TRUE,
};
const device_features_1_3 = vk.PhysicalDeviceVulkan13Features{
    .dynamic_rendering = vk.TRUE,
    .synchronization_2 = vk.TRUE,
};

const swapchain_surface_formats = [_]vk.SurfaceFormatKHR{
    // ranking of preferred formats for the swapchain surfaces
    // if none are present, the first format from getPhysicalDeviceSurfaceFormats is used
    .{ .format = vk.Format.r8g8b8a8_srgb, .color_space = vk.ColorSpaceKHR.srgb_nonlinear_khr },
    .{ .format = vk.Format.b8g8r8a8_srgb, .color_space = vk.ColorSpaceKHR.srgb_nonlinear_khr },
};

const Platform = struct {
    getInstanceProcAddress: *const fn (vk.Instance, [*:0]const u8) vk.PfnVoidFunction,
    getRequiredInstanceExtensions: *const fn () anyerror![][*:0]const u8,
    createWindowSurface: *const fn (vk.Instance) anyerror!vk.SurfaceKHR,
    getFramebufferSize: *const fn () [2]u32,
};

const BaseWrapper = vk.BaseWrapper(apis);
const InstanceWrapper = vk.InstanceWrapper(apis);
const DeviceWrapper = vk.DeviceWrapper(apis);

const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);
const Queue = vk.QueueProxy(apis);
const CommandBuffer = vk.CommandBufferProxy(apis);

pub const Context = struct {
    gpa: std.mem.Allocator,

    base: BaseWrapper,
    instance: Instance,
    device: Device,

    surface: vk.SurfaceKHR,

    pub fn init(
        gpa: std.mem.Allocator,
        platform: Platform,
        app_name: [:0]const u8,
    ) !void {
        var arena_struct: std.heap.ArenaAllocator = try .init(gpa);
        defer arena_struct.deinit();
        const arena = arena_struct.allocator();

        var ctx: Context = undefined;
        ctx.gpa = gpa;

        try ctx.initInstance(arena, platform, app_name);
        errdefer ctx.deinitInstance();
    }

    pub fn deinit(ctx: Context) void {
        ctx.device.deviceWaitIdle() catch |e| {
            log.warn("Failed deviceWaitIdle in vulkan_context deinit: {}", .{e});
        };
        deinitInstance();
    }

    fn initInstance(
        ctx: Context,
        arena: std.mem.Allocator,
        platform: Platform,
        app_name: [:0]const u8,
    ) !void {
        const all_layers = if (enable_debug) layers ++ debug_layers else layers;
        const available_layers = try ctx.base.enumerateInstanceLayerPropertiesAlloc(arena);
        for (all_layers) |req| {
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
        var all_extensions = std.ArrayList([*:0]const u8).init(arena);
        try all_extensions.appendSlice(platform_extensions);
        outer: for (if (enable_debug)
            instance_extensions ++ debug_instance_extensions
        else
            instance_extensions) |ext1|
        {
            for (all_extensions.items) |ext2| if (std.mem.eql(
                u8,
                std.mem.sliceTo(ext1, 0),
                std.mem.sliceTo(ext2, 0),
            )) continue :outer;
            try all_extensions.append(ext1);
        }
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

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = 0,
            .p_engine_name = app_name,
            .engine_version = 0,
            .api_version = api_version,
        };
        const create_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(all_layers.len),
            .pp_enabled_layer_names = &all_layers,
            .enabled_extension_count = @intCast(all_extensions.items.len),
            .pp_enabled_extension_names = all_extensions.items.ptr,
        };
        const instance_handle = try ctx.base.createInstance(&create_info, null);
        const vki = try ctx.gpa.create(InstanceWrapper);
        errdefer ctx.gpa.destroy(vki);
        vki.* = try InstanceWrapper.load(instance_handle, ctx.base.dispatch.vkGetInstanceProcAddr);
        ctx.instance = Instance.init(instance_handle, vki);
    }

    fn deinitInstance(ctx: Context) !void {
        ctx.instance.destroyInstance(null);
        ctx.gpa.destroy(ctx.instance.wrapper);
    }

    fn createSurface(ctx: Context, platform: Platform) !void {
        ctx.surface = try platform.createWindowSurface(ctx.instance.handle);
    }

    fn destroySurface(ctx: Context) void {
        ctx.instance.destroySurfaceKHR(ctx.surface, null);
        ctx.surface = .null_handle;
    }
};

const PhysicalDeviceCandidate = struct {
    device: vk.PhysicalDevice,
    // TODO expand properties/memory_properties in the same way as the features?
    properties: vk.PhysicalDeviceProperties2,
    properties_1_1: vk.PhysicalDeviceVulkan11Properties,
    properties_1_2: vk.PhysicalDeviceVulkan12Properties,
    properties_1_3: vk.PhysicalDeviceVulkan13Properties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    features: vk.PhysicalDeviceFeatures,
    features_1_1: vk.PhysicalDeviceVulkan11Features,
    features_1_2: vk.PhysicalDeviceVulkan12Features,
    features_1_3: vk.PhysicalDeviceVulkan13Features,

    graphics_compute_queue_family: ?u32,
    async_compute_queue_family: ?u32,
    transfer_queue_family: ?u32,
    present_queue_family: ?u32,
};

test "scratch" {
    _ = vk;
    _ = Context;
}
