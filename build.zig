const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    const pl_mod = b.addModule("packer_loader", .{
        .root_source_file = b.path("src/packer-loader/root.zig"),
        .target = target,
    });
    _ = pl_mod;

    const pl_exe = b.addExecutable(.{
        .name = "packer_loader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/packer-loader/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    _ = pl_exe;

    const ecs = b.addModule("ecs", .{
        .root_source_file = b.path("src/ecs/root.zig"),
        .target = target,
    });
    _ = ecs;

    const math = b.addModule("math", .{
        .root_source_file = b.path("src/math/root.zig"),
        .target = target,
    });
    _ = math;

    const profiler = b.addModule("profiler", .{
        .root_source_file = b.path("src/profiler/root.zig"),
        .target = target,
    });
    _ = profiler;

    const rhi = b.addModule("rhi", .{
        .root_source_file = b.path("src/rhi/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "vulkan", .module = vulkan },
        },
    });

    // tests
    const rhi_tests = b.addTest(.{ .root_module = rhi });
    rhi_tests.root_module.addImport("vulkan", vulkan);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(rhi_tests).step);
}
