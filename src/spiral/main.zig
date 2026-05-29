const arenautils = @import("arenautils");
const std = @import("std");

const spiral = @import("root.zig");

const log = std.log.scoped(.spiral_cli);

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

    // TODO either use or make a argparse librariy or wait for stdlib to have one
    var it = try init.minimal.args.iterateAllocator(permanent_arena);
    _ = it.skip();
    while (it.next()) |arg| {
        if (std.mem.eql(u8, "add", arg)) {
            const path = it.next() orelse {
                log.err("expected filename", .{});
                return error.Args;
            };
            std.debug.assert(std.mem.eql(u8, "raw" ++ std.fs.path.sep_str, path[0..4]));
            try addFile(permanent_arena, io, path);
        } else if (std.mem.eql(u8, "pack", arg)) {
            try packAll(gpa, io);
        } else {
            log.err("unknown command {s}", .{arg});
            return error.Args;
        }
    }
}

fn addFile(arena: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng: std.Random.DefaultPrng = .init(seed);
    const rand = rng.random();

    const dirname = std.fs.path.dirname(path) orelse {
        log.err("file should be in raw/..., got {s}", .{path});
        return error.Invalid;
    };
    const basename = std.fs.path.basename(path);

    const input_dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, dirname, .{});
    const manifest_path = try std.fmt.allocPrint(arena, "{s}.manifest.zon", .{basename});

    const uuid: Uuid = .random(io, rand);
    const manifest: Manifest = .{
        .uuid = &uuid.stringify(),
        .assets = &.{},
    };
    const output_file = try input_dir.createFile(io, manifest_path, .{ .exclusive = true });
    defer output_file.close(io);
    var buffer: [1024]u8 = undefined;
    var writer = output_file.writer(io, &buffer);
    try std.zon.stringify.serialize(
        manifest,
        .{ .emit_default_optional_fields = false },
        &writer.interface,
    );
    try writer.flush();

    log.info("created {s}", .{manifest_path});

    const output_dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, "raw", .{});
    try processManifest(arena, io, input_dir, output_dir, manifest_path);
}

fn packAll(gpa: std.mem.Allocator, io: std.Io) !void {
    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const input_dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, "raw", .{ .iterate = true });
    const output_dir: std.Io.Dir = try .openDir(.cwd(), io, "data", .{});

    var it = try input_dir.walk(gpa);
    defer it.deinit();
    while (try it.next(io)) |entry| {
        _ = arena_impl.reset(.retain_capacity);

        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".manifest.zon")) continue;

        try processManifest(arena, io, entry.dir, output_dir, entry.basename);
    }

    _ = arena_impl.reset(.retain_capacity);

    var buffer: [1024]u8 = undefined;
    const file = try output_dir.createFile(io, "index", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);

    var asset_count: u32 = 0;
    var it_assets = try assets.iterator(arena);
    while (try it_assets.next()) |_| asset_count += 1;
    try writer.interface.writeInt(u32, asset_count, .little);

    it_assets = try assets.iterator(arena);
    while (try it_assets.next()) |kv| {
        const uuid = kv.key;
        const asset_info = kv.value_ptr.*;
        log.debug("{s} -> {x}", .{ &uuid.stringify(), asset_info.content_hash });
        try writer.interface.writeInt(u128, uuid.bits, .little);
        // TODO support other locations
        try (spiral.Storage.Location{
            .size = asset_info.size,
            .location = .{ .file = asset_info.content_hash },
        }).serialize(&writer.interface);
    }
    try writer.interface.flush();

    const preload_file = try output_dir.createFile(io, "preload", .{});
    // write preload files in order of their hash i guess? we want the layout to be stable
    defer preload_file.close(io);
}

fn processManifest(
    arena: std.mem.Allocator,
    io: std.Io,
    input_dir: std.Io.Dir,
    output_dir: std.Io.Dir,
    path: []const u8,
) !void {
    std.debug.assert(std.mem.endsWith(u8, path, ".manifest.zon"));

    const bytes =
        try input_dir.readFileAllocOptions(io, path, arena, .limited(1024 * 1024), .@"1", 0);
    var diagnostics: std.zon.parse.Diagnostics = .{};
    const old_manifest =
        std.zon.parse.fromSliceAlloc(Manifest, arena, bytes, &diagnostics, .{}) catch |e| {
            log.err("failed to parse manifest {s}", .{path});
            var it = diagnostics.iterateErrors();
            while (it.next()) |diag| {
                std.debug.print("  {}\n", .{diag});
            }
            return e;
        };

    const raw_path = path[0 .. path.len - 13];
    const extension = std.fs.path.extension(raw_path);

    const f = dispatch_table.get(extension) orelse {
        log.err("cannot parse {s}, unknown extension {s}", .{ raw_path, extension });
        return;
    };
    const new_manifest = try f(arena, io, input_dir, output_dir, old_manifest, raw_path);

    const output_file = try input_dir.createFile(io, path, .{});
    defer output_file.close(io);
    var buffer: [1024]u8 = undefined;
    var writer = output_file.writer(io, &buffer);
    try std.zon.stringify.serialize(
        new_manifest,
        .{ .emit_default_optional_fields = false },
        &writer.interface,
    );
    try writer.flush();
}

const Config = union(enum) {
    txt,
};

const Asset = struct {
    uuid: []const u8,
    config: Config,
    subresource_name: []const u8 = "",
    global_name: []const u8 = "",
    preload: bool = false,
};

const Manifest = struct {
    uuid: []const u8,
    assets: []Asset,
};

const dispatch_table: std.StaticStringMap(*const fn (
    std.mem.Allocator,
    std.Io,
    std.Io.Dir,
    std.Io.Dir,
    Manifest,
    []const u8,
) anyerror!Manifest) = .initComptime(&.{
    .{ ".txt", processTxt },
});

// so, the manifest should be able to work from just the root uuid and nothing more
// and then we let the process function identify subassets and complete/update the list
// when we run add, we just always try to process the file also to build the manifest

fn processTxt(
    arena: std.mem.Allocator,
    io: std.Io,
    input_dir: std.Io.Dir,
    output_dir: std.Io.Dir,
    old_manifest: Manifest,
    filename: []const u8,
) !Manifest {
    std.debug.assert(old_manifest.assets.len <= 1);

    const old_asset: ?Asset = if (old_manifest.assets.len == 0) null else old_manifest.assets[0];

    // txt has no config, so just regenerate the asset list and proceed
    const uuid: Uuid = try .parse(old_manifest.uuid);
    const child_uuid = uuid.child("");

    const new_manifest: Manifest = .{
        .uuid = old_manifest.uuid,
        .assets = try arena.alloc(Asset, 1),
    };
    new_manifest.assets[0] = .{
        .uuid = try arena.dupe(u8, &child_uuid.stringify()),
        .config = .{ .txt = {} },
        .subresource_name = "",
    };
    if (old_asset) |asset| {
        new_manifest.assets[0].global_name =
            if (asset.global_name.len > 0) try arena.dupe(u8, asset.global_name) else "";
        new_manifest.assets[0].preload = asset.preload;
    }
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

    _ = try assets.put(permanent_arena, child_uuid, .{
        .content_hash = content_hash,
        .destination = if (new_manifest.assets[0].preload) .preload else .bucket,
        .size = size,
    });

    // for simple files with no processing, i think we might as well always copy
    // but in principle, if a file with the hash is already present then we should do nothing
    try std.Io.Dir.copyFile(input_dir, filename, output_dir, &content_hash_str, io, .{});

    return new_manifest;
}
