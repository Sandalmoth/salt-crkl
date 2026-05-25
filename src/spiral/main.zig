const arenautils = @import("arenautils");
const std = @import("std");

const spiral = @import("root.zig");

const log = std.log.scoped(.spiral);

const Uuid = @import("Uuid.zig");

const AssetInfo = struct {
    content_hash: u128,
    destination: enum { bucket, preload },
    size: u64,
};

var permanent_arena: std.mem.Allocator = undefined;
var assets: arenautils.AutoMap(Uuid, AssetInfo) = .init();
// var content_hashes: arenautils.AutoMap(u128, struct {}) = .init();

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
    permanent_arena = init.arena.allocator();

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
                var buffer: [16 * 1024]u8 = undefined;

                if (!std.mem.endsWith(u8, entry.basename, ".manifest.zon")) continue;
                std.debug.print("file {s} {s}\n", .{ entry.basename, entry.path });
                const filename = entry.basename[0 .. entry.basename.len - 13];
                const extension = std.fs.path.extension(filename);
                std.debug.print("  {s} {s}\n", .{ filename, extension });

                const manifest_bytes =
                    try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(1024 * 1024));
                const manifest_bytes_z =
                    try std.mem.concatWithSentinel(arena, u8, &.{manifest_bytes}, 0); // silly
                std.debug.print("{s}\n", .{manifest_bytes_z});
                var diagnostics: std.zon.parse.Diagnostics = .{};
                const manifest = std.zon.parse.fromSliceAlloc(
                    Manifest,
                    arena,
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
                std.debug.print("{}\n", .{manifest});
                const new_manifest = if (std.mem.eql(u8, extension, ".txt"))
                    try processTxt(arena, io, output_dir, manifest, entry.dir, filename)
                else blk: {
                    log.err("unknown file extension {s} for {s}", .{ extension, entry.path });
                    break :blk manifest; // don't overwrite if unknown
                };

                const output_file = try entry.dir.createFile(io, entry.basename, .{}); // overwrite
                defer output_file.close(io);
                var writer = output_file.writer(io, &buffer);
                try std.zon.stringify.serialize(new_manifest, .{}, &writer.interface);
                try writer.flush();
            },
            else => continue,
        }
    }

    _ = arena_impl.reset(.retain_capacity);

    var buffer: [16 * 1024]u8 = undefined;
    const file = try output_dir.createFile(io, "index", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    // try writer.interface.writeInt(u32, @intCast(manifests.len), .little);
    // for (0..manifests.len) |i| {
    //     const manifest = manifests.get(i);
    //     std.debug.print("{}\n", .{manifest});
    //     for (manifest.assets) |asset| {
    //         const uuid: Uuid = try .parse(asset.uuid);
    //         try writer.interface.writeInt(u128, uuid.bits, .little);
    //         // if in buckets: bucket, offset, size
    //         // if not: content hash (== filename)
    //         // block the asset is in, or maxint if not in block
    //         try writer.interface.writeInt(u32, std.math.maxInt(u32), .little);
    //     }
    // }
    var it_assets = try assets.iterator(arena);
    // write index consisting of
    //
    while (try it_assets.next()) |kv| {
        const uuid = kv.key;
        const asset_info = kv.value_ptr.*;
        std.debug.print("{s} -> {}\n", .{ &uuid.stringify(), asset_info });
        try writer.interface.writeInt(u128, uuid.bits, .little);
        try (spiral.Storage.Location{
            .size = asset_info.size,
            .location = .{ .file = asset_info.content_hash },
        }).serialize(&writer.interface);
        // try writer.interface.writeInt(u64, settings, .little);
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
    name: []const u8,
};

const Manifest = struct {
    uuid: []const u8,
    assets: []const Asset,
};

// so, the manifest should be able to work from just the root uuid and nothing more
// and then we let the process function identify subassets and complete/update the list
// when we run add, we just always try to process the file also to build the manifest

fn processTxt(
    arena: std.mem.Allocator,
    io: std.Io,
    output_dir: std.Io.Dir,
    old_manifest: Manifest,
    input_dir: std.Io.Dir,
    filename: []const u8,
) !Manifest {
    std.debug.assert(old_manifest.assets.len <= 1);

    // txt has no config, so just regenerate the asset list and proceed
    const uuid: Uuid = try .parse(old_manifest.uuid);
    const child_uuid = uuid.child("");
    const new_manifest: Manifest = .{
        .uuid = old_manifest.uuid,
        .assets = &.{
            .{
                .uuid = try arena.dupe(u8, &child_uuid.stringify()),
                .config = .{ .txt = {} },
                .name = "",
            },
        },
    };
    if (old_manifest.assets.len > 0) {
        std.debug.assert(old_manifest.assets[0].config == .txt);
        std.debug.assert(std.mem.eql(u8, old_manifest.assets[0].uuid, new_manifest.assets[0].uuid));
    }

    var buffer: [16 * 1024]u8 = undefined;

    // read file and produce content hash
    const input_file = try input_dir.openFile(io, filename, .{});
    var reader = input_file.reader(io, &buffer);
    var content_hasher_a = std.hash.XxHash3.init(0xc22cc9d473e8e35b);
    var content_hasher_b = std.hash.XxHash3.init(0xa4e5461484c572b1);
    var size: u64 = 0;
    while (true) {
        reader.interface.fillMore() catch |e| {
            if (e == error.EndOfStream) break;
            return e;
        };
        const buffered = reader.interface.buffered();
        size += buffered.len;
        content_hasher_a.update(buffered);
        content_hasher_b.update(buffered);
        reader.interface.tossBuffered();
    }
    const hash_a: u128 = content_hasher_a.final();
    const hash_b: u128 = content_hasher_b.final();
    const content_hash: u128 = hash_a << 64 | hash_b;
    var content_hash_str: [32]u8 = undefined;
    _ = std.fmt.bufPrint(&content_hash_str, "{x}", .{content_hash}) catch unreachable;
    std.debug.print("{s}\n", .{content_hash_str});

    _ = try assets.put(permanent_arena, child_uuid, .{
        .content_hash = content_hash,
        .destination = .bucket,
        .size = size,
    });

    // for simple files with no processing, i think we might as well always copy
    // but in principle, if a file with the hash is already present then we should do nothing
    try std.Io.Dir.copyFile(input_dir, filename, output_dir, &content_hash_str, io, .{});

    return new_manifest;
}
