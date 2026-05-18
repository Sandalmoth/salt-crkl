const arenautils = @import("arenautils");
const std = @import("std");

const spiral = @import("root.zig");

const log = std.log.scoped(.spiral);

const Uuid = @import("Uuid.zig");

var manifests: arenautils.List(Manifest) = .empty;
var content_hashes: arenautils.AutoMap(u128, struct {}) = .init();

// iterate the raw dir
// for each manifest
//   rebuild the asset list in the manifest, keep config if possible
//   hash data and config, if hash doesn't exist
//     process the file and add to content hashes
//     add content table
//   store manifest -> content hash in list
// generate index

// so, the manifest should be able to work from just the root uuid and nothing more
// and then we let the process function identify subassets and complete/update the list
// when we run add, we just always try to process the file also to build the manifest

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng: std.Random.DefaultPrng = .init(seed);
    const rand = rng.random();

    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const output_dir: std.Io.Dir = try .openDir(.cwd(), io, "data", .{});

    const input_dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, "raw", .{ .iterate = true });
    var it = try input_dir.walk(gpa);
    defer it.deinit();
    while (try it.next(io)) |entry| {
        _ = arena_impl.reset(.retain_capacity);
        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.basename, ".manifest.zon")) continue;
                std.debug.print("file {s} {s}\n", .{ entry.basename, entry.path });
                const filename = entry.basename[0 .. entry.basename.len - 13];
                const extension = std.fs.path.extension(filename);
                std.debug.print("  {s} {s}\n", .{ filename, extension });

                const manifest_bytes =
                    try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(1024 * 1024));
                const manifest_bytes_z =
                    try std.mem.concatWithSentinel(arena, u8, &.{manifest_bytes}, 0);
                std.debug.print("{s}\n", .{manifest_bytes_z});
                var diagnostics: std.zon.parse.Diagnostics = .{};
                // note that the manifests go on the permanent arena
                const manifest = std.zon.parse.fromSliceAlloc(
                    Manifest,
                    init.arena.allocator(),
                    manifest_bytes_z,
                    &diagnostics,
                    .{},
                ) catch |e| {
                    std.debug.print("failed to parse zon\n{}\n", .{diagnostics});
                    var it2 = diagnostics.iterateErrors();
                    while (it2.next()) |diag| {
                        std.debug.print("{}\n", .{diag});
                    }
                    return e;
                };
                (try manifests.addOne(init.arena.allocator())).* = manifest;
                std.debug.print("{}\n", .{manifest});

                std.debug.print("{s}\n", .{extension});
                if (std.mem.eql(u8, extension, ".txt"))
                    try processTxt(arena, io, output_dir, manifest, entry.dir, filename);
            },
            else => continue,
        }
    }

    var buffer: [16 * 1024]u8 = undefined;
    const file = try output_dir.createFile(io, "index", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    try writer.interface.writeInt(u32, @intCast(manifests.len), .little);
    for (0..manifests.len) |i| {
        const manifest = manifests.get(i);
        std.debug.print("{}\n", .{manifest});
        for (manifest.assets) |asset| {
            const uuid: Uuid = try .parse(asset.uuid);
            try writer.interface.writeInt(u128, uuid.bits, .little);
            // if in buckets: bucket, offset, size
            // if not: content hash (== filename)
            // block the asset is in, or maxint if not in block
            try writer.interface.writeInt(u32, std.math.maxInt(u32), .little);
        }
    }
    try writer.interface.flush();

    const uuid: Uuid = .random(io, rand);
    std.debug.print("{s}\n{s}\n", .{
        &uuid.stringify(),
        &uuid.child("").stringify(),
    });
}

const Config = union(enum) {
    txt,
};

const Asset = struct {
    uuid: []const u8,
    config: Config,
    name: []const u8 = "",
};

const Manifest = struct {
    uuid: []const u8,
    assets: []Asset,
};

fn processTxt(
    arena: std.mem.Allocator,
    io: std.Io,
    output_dir: std.Io.Dir,
    manifest: Manifest,
    input_dir: std.Io.Dir,
    filename: []const u8,
) !void {
    _ = arena;

    try std.Io.Dir.copyFile(input_dir, filename, output_dir, manifest.assets[0].uuid, io, .{});
}
