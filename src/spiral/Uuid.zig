const std = @import("std");

const Uuid = @This();

bits: u128,

pub fn random(io: std.Io, rand: std.Random) Uuid {
    var l: u64 = @bitCast(std.Io.Timestamp.now(io, .real).toMicroseconds());
    var r: u64 = rand.int(u64);
    for ([_]u64{ 0xb1bcf22d4692ed5d, 0xb101cd5c53b10de1, 0xe391b47692f9a411 }) |k| {
        const x = l ^ std.hash.XxHash64.hash(k, std.mem.asBytes(&r));
        l = r;
        r = x;
    }
    const bits: u128 = (@as(u128, @intCast(l)) << 64) | @as(u128, @intCast(r));
    return .{ .bits = bits *% 0x9e3779b97f4a7c15f39cc0605cedc823 };
}

pub fn child(parent: Uuid, name: []const u8) Uuid {
    var bits: u128 = std.hash.XxHash64.hash(0xcd14f95ba90b855d, name);
    bits <<= 64;
    bits |= std.hash.XxHash64.hash(0x8f0d96c55ba5160d, name);
    bits *%= 0x9e3779b97f4a7c15f39cc0605cedc823;
    return .{ .bits = parent.bits ^ bits };
}

pub fn parse(str: []const u8) !Uuid {
    if (str.len != 26) return error.Invalid;
    var bits: u128 = 0;
    for (0..26) |i| {
        const x: u128 = switch (str[i]) {
            '0', 'O', 'o' => 0,
            '1', 'I', 'i', 'L', 'l' => 1,
            '2' => 2,
            '3' => 3,
            '4' => 4,
            '5' => 5,
            '6' => 6,
            '7' => 7,
            '8' => 8,
            '9' => 9,
            'A', 'a' => 10,
            'B', 'b' => 11,
            'C', 'c' => 12,
            'D', 'd' => 13,
            'E', 'e' => 14,
            'F', 'f' => 15,
            'G', 'g' => 16,
            'H', 'h' => 17,
            'J', 'j' => 18,
            'K', 'k' => 19,
            'M', 'm' => 20,
            'N', 'n' => 21,
            'P', 'p' => 22,
            'Q', 'q' => 23,
            'R', 'r' => 24,
            'S', 's' => 25,
            'T', 't' => 26,
            'V', 'v' => 27,
            'W', 'w' => 28,
            'X', 'x' => 29,
            'Y', 'y' => 30,
            'Z', 'z' => 31,
            else => return error.Invalid,
        };
        bits |= (x << @intCast(125 - 5 * i));
    }
    return .{ .bits = bits };
}

pub fn stringify(uuid: Uuid) [26]u8 {
    var str: [26]u8 = undefined;
    for (0..26) |i| {
        str[i] = @intCast((uuid.bits >> @intCast(125 - 5 * i)) & 0x1f);
    }
    for (0..26) |i| {
        str[i] = ([32]u8{
            '0', '1', '2', '3', '4', '5', '6', '7',
            '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
            'G', 'H', 'J', 'K', 'M', 'N', 'P', 'Q',
            'R', 'S', 'T', 'V', 'W', 'X', 'Y', 'Z',
        })[str[i]];
    }
    return str;
}
