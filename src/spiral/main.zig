const arenautils = @import("arenautils");
const std = @import("std");

const spiral = @import("root.zig");

const Uuid = @import("Uuid.zig");

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

    const dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, "raw", .{ .iterate = true });
    var it = try dir.walk(gpa);
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

                if (!std.mem.eql(u8, filename, "a.txt")) continue;

                const manifest_bytes =
                    try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(1024 * 1024));
                const manifest_bytes_z =
                    try std.mem.concatWithSentinel(arena, u8, &.{manifest_bytes}, 0);
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
            },
            else => continue,
        }
    }

    var buffer: [16 * 1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "data/index", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    try writer.interface.writeInt(u32, 123, .little);
    try writer.interface.flush();

    const uuid: Uuid = .random(io, rand);
    const uuid_str = uuid.stringify();
    std.debug.print("{s}\n  {}\n  {}\n", .{
        uuid_str,
        uuid,
        try Uuid.parse(&uuid_str),
    });
    std.debug.print("  {s}\n    {}\n    {}\n  {s}\n    {}\n    {}\n", .{
        &uuid.child("walk").stringify(),
        uuid.child("walk"),
        uuid.child("walk"),
        &uuid.child("albedo").stringify(),
        uuid.child("albedo"),
        uuid.child("albedo"),
    });
}

const Config = union(enum) {
    txt: void,
};

const Asset = struct {
    uuid: []const u8,
    config: Config,
};

const Manifest = struct {
    uuid: []const u8,
    assets: []Asset = &.{},
};
