const std = @import("std");

const spiral = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    // const gpa = init.gpa;
    const io = init.io;

    var buffer: [16 * 1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "data/index", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    try writer.interface.writeInt(u32, 123, .little);
    try writer.interface.flush();
}
