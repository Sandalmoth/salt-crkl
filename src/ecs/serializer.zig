const std = @import("std");

const Key = @import("root.zig").Key;
const KeyGen = @import("root.zig").KeyGen;

pub fn serialize(writer: *std.Io.Writer, ctx: anytype, value: anytype) !void {
    const T: type = @TypeOf(value);

    switch (@typeInfo(T)) {
        .@"enum", .@"struct", .@"union" => if (@hasDecl(T, "serialize")) {
            return @call(.auto, T.serialize, .{ writer, ctx, value });
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .void => {},
        .bool => try writer.writeByte(@intFromBool(value)),
        .int => if (T == usize) {
            try writer.writeInt(u64, value, .little);
        } else {
            try writer.writeInt(std.math.ByteAlignedInt(T), value, .little);
        },
        .float => try writer.writeSliceEndian(u8, std.mem.asBytes(&value), .little),
        .array => for (value) |v| try serialize(writer, ctx, v),
        .vector => |info| for (0..info.len) |i| try serialize(writer, ctx, value[i]),
        .optional => {
            try writer.writeByte(@intFromBool(value != null));
            if (value) |v| try serialize(writer, ctx, v);
        },
        .@"enum" => try serialize(writer, ctx, @intFromEnum(value)),
        .@"struct" => |info| {
            inline for (info.fields) |field| try serialize(writer, ctx, @field(value, field.name));
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError(@typeName(T) ++ " not supported");
            try serialize(writer, ctx, std.meta.activeTag(value));
            switch (value) {
                inline else => |v| try serialize(writer, ctx, v),
            }
        },

        else => @compileError(@typeName(T) ++ " not supported"),
    }
}

pub fn deserialize(reader: *std.Io.Reader, ctx: anytype, comptime T: type) !T {
    switch (@typeInfo(T)) {
        .@"enum", .@"struct", .@"union" => if (@hasDecl(T, "deserialize")) {
            return @call(.auto, T.deserialize, .{ reader, ctx });
        },
        else => {},
    }

    return switch (@typeInfo(T)) {
        .void => {},
        .bool => (try reader.takeByte()) > 0,
        .int => if (T == usize) {
            return @intCast(try reader.takeInt(u64, .little));
        } else {
            return @intCast(try reader.takeInt(std.math.ByteAlignedInt(T), .little));
        },
        .float => std.mem.bytesAsValue(T, try reader.takeArray(@sizeOf(T))).*,
        .array => |info| {
            var result: T = undefined;
            for (0..info.len) |i| result[i] = try deserialize(reader, ctx, info.child);
            return result;
        },
        .vector => |info| {
            var result: T = undefined;
            for (0..info.len) |i| result[i] = try deserialize(reader, ctx, info.child);
            return result;
        },
        .optional => |info| {
            if ((try reader.takeByte()) == 0) return null;
            return try deserialize(reader, ctx, info.child);
        },
        .@"enum" => |info| @enumFromInt(try deserialize(reader, ctx, info.tag_type)),
        .@"struct" => |info| {
            var result: T = undefined;
            inline for (info.fields) |field| {
                if (field.type == void) continue;
                @field(result, field.name) = try deserialize(reader, ctx, field.type);
            }
            return result;
        },
        .@"union" => |info| {
            const tag_type = info.tag_type orelse @compileError(@typeName(T) ++ " not supported");
            switch (try deserialize(reader, ctx, tag_type)) {
                inline else => |tag| return @unionInit(
                    T,
                    @tagName(tag),
                    try deserialize(reader, ctx, @FieldType(T, @tagName(tag))),
                ),
            }
        },

        else => @compileError(@typeName(T) ++ " not supported"),
    };
}

test "basic (de)serialization" {
    const Custom = struct {
        x: u32,

        fn serialize(writer: *std.Io.Writer, ctx: u32, value: @This()) !void {
            try writer.writeInt(u32, value.x ^ ctx, .little);
        }

        fn deserialize(reader: *std.Io.Reader, ctx: u32) !@This() {
            return .{ .x = (try reader.takeInt(u32, .little)) ^ ctx };
        }
    };

    const Test = struct {
        a: void,
        b: bool,
        c: u32,
        d: f64,
        e: enum { p, q },
        f: enum(u64) { p, q, _ },
        g: ?bool,
        h: [2]i64,
        i: @Vector(4, f32),
        j: struct { p: u32, q: f32 },
        k: union(enum) { p: u32, q: f32 },
        l: Custom,
    };

    const t: Test = .{
        .a = {},
        .b = true,
        .c = 123,
        .d = 99.9,
        .e = .q,
        .f = @enumFromInt(1337),
        .g = false,
        .h = .{ -89, 144 },
        .i = .{ 0.0, 1.0, 2.0, 3.0 },
        .j = .{ .p = 11, .q = 11.1 },
        .k = .{ .q = 0.5 },
        .l = .{ .x = 456 },
    };

    // in this case, context is an int used to store the custom type "encrypted"

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try serialize(&writer, 0xDEADBEEF, t);

    var reader = std.Io.Reader.fixed(&buf);
    const t2 = try deserialize(&reader, 0xDEADBEEF, Test);

    try std.testing.expect(std.meta.eql(t, t2));
}
