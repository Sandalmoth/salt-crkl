const arenautils = @import("arenautils");
const std = @import("std");

const spiral = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    // defer arena_impl.deinit();
    // const arena = arena_impl.allocator();

    const dir: std.Io.Dir = try .openDir(std.Io.Dir.cwd(), io, "raw", .{ .iterate = true });
    var it = try dir.walk(gpa);
    defer it.deinit();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.basename, ".manifest.zon")) continue;
                std.debug.print("file {s} {s}\n", .{ entry.basename, entry.path });
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
}

const Asset = struct {
    uuid: u128,
};

const Manifest = struct {
    assets: []Asset,
};
