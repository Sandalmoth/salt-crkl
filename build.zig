const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
}
