const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // dependencies
    const vulkan = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    // libraries
    const arenautils = b.addModule("math", .{
        .root_source_file = b.path("src/arenautils/root.zig"),
        .target = target,
    });
    // _ = arenautils;

    const spiral = b.addModule("spiral", .{
        .root_source_file = b.path("src/spiral/root.zig"),
        .target = target,
    });
    _ = spiral;

    const spiral_exe = b.addExecutable(.{
        .name = "spiral",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/spiral/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "arenautils", .module = arenautils },
            },
        }),
    });
    b.installArtifact(spiral_exe);

    const ecs = b.addModule("ecs", .{
        .root_source_file = b.path("src/ecs/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
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
        .optimize = optimize,
        .imports = &.{},
    });
    _ = profiler;

    const rhi = b.addModule("rhi", .{
        .root_source_file = b.path("src/rhi/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vulkan", .module = vulkan },
        },
    });

    // examples
    const example_rhi_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/examples/rhi/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const example_rhi_exe = b.addExecutable(.{
        .name = "example_rhi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/rhi/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rhi", .module = rhi },
                .{ .name = "c", .module = example_rhi_translate_c.createModule() },
            },
        }),
    });
    addSlangShader(b, "src/examples/rhi/shader.slang", "vertex", example_rhi_exe);
    addSlangShader(b, "src/examples/rhi/shader.slang", "fragment", example_rhi_exe);
    example_rhi_exe.root_module.linkLibrary(sdl_lib);
    b.installArtifact(example_rhi_exe);

    // tests
    const rhi_tests = b.addTest(.{ .root_module = rhi });
    rhi_tests.root_module.addImport("vulkan", vulkan);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(rhi_tests).step);
}

fn addSlangShader(
    b: *std.Build,
    source_path: []const u8,
    stage: []const u8,
    exe: *std.Build.Step.Compile,
) void {
    const cmd = b.addSystemCommand(&.{ "slangc", source_path });
    const stem = std.fs.path.stem(source_path);
    cmd.addArgs(&.{
        "-target", "spirv",
        "-entry",  b.fmt("{s}Main", .{stage}),
        "-stage",  stage,
        "-O3",     "-fvk-use-c-layout",
    });
    cmd.addArg("-o");
    const spv_name = b.fmt("slang_{s}_{s}.spv", .{ stem, stage });
    const spv = cmd.addOutputFileArg(spv_name);
    cmd.addArg("-reflection-json");
    const json_name = b.fmt("slang_{s}_{s}.json", .{ stem, stage });
    const json = cmd.addOutputFileArg(json_name);
    exe.root_module.addAnonymousImport(
        b.fmt("slang_{s}_{s}_spv", .{ stem, stage }),
        .{ .root_source_file = spv },
    );
    exe.root_module.addAnonymousImport(
        b.fmt("slang_{s}_{s}_json", .{ stem, stage }),
        .{ .root_source_file = json },
    );
}
