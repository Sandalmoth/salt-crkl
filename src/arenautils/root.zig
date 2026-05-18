/// data structures designed for use with an arena allocator
/// they dont free any memory, and they dont reallocate/move anything when growing
/// in addition, appending from multiple threads at once is lock free
const std = @import("std");

/// a segmented array where each segment is 2x the size of the previous
/// basically the std.SegmentedList modification from https://github.com/ziglang/zig/issues/20491
pub fn List(comptime T: type) type {

    // (from the old std.SegmentedList source, MIT license)

    // Imagine that `fn at(self: *Self, index: usize) &T` is a customer asking for a box
    // from a warehouse, based on a flat array, boxes ordered from 0 to N - 1.
    // But the warehouse actually stores boxes in shelves of increasing powers of 2 sizes.
    // So when the customer requests a box index, we have to translate it to shelf index
    // and box index within that shelf. Illustration:
    //
    // customer indexes:
    // shelf 0:  0
    // shelf 1:  1  2
    // shelf 2:  3  4  5  6
    // shelf 3:  7  8  9 10 11 12 13 14
    // shelf 4: 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30
    // ...
    //
    // warehouse indexes:
    // shelf 0:  0
    // shelf 1:  0  1
    // shelf 2:  0  1  2  3
    // shelf 3:  0  1  2  3  4  5  6  7
    // shelf 4:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    // ...
    //
    // With this arrangement, here are the equations to get the shelf index and
    // box index based on customer box index:
    //
    // shelf_index = floor(log2(customer_index + 1))
    // shelf_count = ceil(log2(box_count + 1))
    // box_index = customer_index + 1 - 2 ** shelf
    // shelf_size = 2 ** shelf_index

    return struct {
        const Self = @This();

        segments: ?*[63]?[*]T, // hell yeah
        len: usize,

        pub const empty = Self{ .segments = null, .len = 0 };

        /// returnss element index from the list
        /// asserts that index is in range
        pub fn get(self: anytype, index: usize) T {
            std.debug.assert(index < @atomicLoad(usize, &self.len, .acquire));
            const shelf_index = shelfIndex(index);
            const box_index = boxIndex(index, shelf_index);
            // NOTE if we are in range, then the segments must exist
            // so we don't need to check for it since we've already asserted
            return self.segments.?[shelf_index].?[box_index];
        }

        /// returns a pointer to element index from the list
        /// asserts that index is in range
        pub fn getPtr(self: anytype, index: usize) *T {
            std.debug.assert(index < @atomicLoad(usize, &self.len, .acquire));
            const shelf_index = shelfIndex(index);
            const box_index = boxIndex(index, shelf_index);
            // NOTE if we are in range, then the segments must exist
            // so we don't need to check for it since we've already asserted
            return &self.segments.?[shelf_index].?[box_index];
        }

        /// increase length by 1, returning pointer to the new item
        /// thread safe, may overallocate during a race
        pub fn addOne(self: *Self, arena: std.mem.Allocator) !*T {
            // ensure that there is a segments array
            const segments = @atomicLoad(?*[63]?[*]T, &self.segments, .acquire) orelse blk: {
                const new_segments = try arena.create([63]?[*]T);
                new_segments.* = @splat(null);
                if (@cmpxchgStrong(
                    ?*[63]?[*]T,
                    &self.segments,
                    null,
                    new_segments,
                    .release,
                    .acquire,
                )) |actual| {
                    // another thread made the new shelf first
                    arena.destroy(new_segments); // might work
                    break :blk actual.?;
                }
                // we made the new shelf
                break :blk new_segments;
            };

            // get a guess at what the index will be
            var index = @atomicLoad(usize, &self.len, .acquire);
            while (true) {
                const shelf_index = shelfIndex(index);

                // ensure that the shelf exists
                const shelf = @atomicLoad(?[*]T, &segments[shelf_index], .acquire) orelse
                    blk: {
                        const new_shelf = try arena.alloc(T, shelfSize(shelf_index));
                        if (@cmpxchgStrong(
                            ?[*]T,
                            &segments[shelf_index],
                            null,
                            new_shelf.ptr,
                            .release,
                            .acquire,
                        )) |actual| {
                            // another thread made the new shelf first
                            arena.free(new_shelf); // might work
                            break :blk actual.?;
                        }
                        // we made the new shelf
                        break :blk new_shelf.ptr;
                    };

                // try to get the index we saw from the start
                if (@cmpxchgWeak(
                    usize,
                    &self.len,
                    index,
                    index + 1,
                    .acq_rel,
                    .acquire,
                )) |latest_len| {
                    // someone else took it, try again
                    index = latest_len;
                    continue;
                }

                return &shelf[boxIndex(index, shelf_index)];
            }
        }

        fn shelfIndex(list_index: usize) usize {
            return std.math.log2_int(usize, list_index + 1);
        }

        fn shelfSize(shelf_index: usize) usize {
            return @as(usize, 1) << @intCast(shelf_index);
        }

        fn boxIndex(list_index: usize, shelf_index: usize) usize {
            return list_index + 1 - (@as(usize, 1) << @intCast(shelf_index));
        }
    };
}

test "List" {
    var arena_impl: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();
    var a: List(u32) = .empty;
    for (0..10) |i| {
        (try a.addOne(arena)).* = @intCast(i);
    }
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(i)), a.get(i));
        try std.testing.expectEqual(@as(u32, @intCast(i)), a.getPtr(i).*);
    }
}

pub fn AutoMap(comptime K: type, comptime V: type) type {
    return Map(K, V, std.hash_map.AutoContext(K));
}

/// hash trie based map with lock-free concurrent put
/// based on https://nullprogram.com/blog/2023/09/30/
pub fn Map(comptime K: type, comptime V: type, comptime Context: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            children: [4]?*Node,
            key: K,
            value: V,
        };

        root: ?*Node,
        ctx: Context,

        const Init = struct {
            fn init() Self {
                return .{
                    .root = null,
                    .ctx = undefined,
                };
            }
            fn initContext(ctx: Context) Self {
                return .{
                    .root = null,
                    .ctx = ctx,
                };
            }
        };
        pub const init = if (@sizeOf(Context) == 0) Init.init else Init.initContext;

        /// put key in map, if key is not present sets it to initial value, otherwise returns ptr
        /// updates using the ptr are not synchronized
        /// threadsafe, may overallocate during a race
        pub fn put(map: *Self, arena: std.mem.Allocator, key: K, initial_value: V) !*V {
            var walk: *?*Node = &map.root;
            var hash = map.ctx.hash(key);
            while (true) : (hash <<= 2) {
                const node = @atomicLoad(?*Node, walk, .acquire) orelse blk: {
                    const new_node = try arena.create(Node);
                    new_node.* = .{
                        .children = @splat(null),
                        .key = key,
                        .value = initial_value,
                    };

                    if (@cmpxchgStrong(
                        ?*Node,
                        walk,
                        null,
                        new_node,
                        .release,
                        .acquire,
                    )) |actual| {
                        // another thread inserted the new node first
                        arena.destroy(new_node); // might work
                        break :blk actual.?;
                    }
                    // we made the new shelf
                    break :blk new_node;
                };
                if (map.ctx.eql(node.key, key)) {
                    return &node.value;
                }
                walk = &node.children[hash >> 62];
            }
        }

        pub fn get(map: Map, key: K) ?V {
            var walk: *?*Node = &map.root;
            var hash = map.ctx.hash(key);
            while (true) : (hash <<= 2) {
                const node = @atomicLoad(?*Node, walk, .acquire) orelse return null;
                if (map.ctx.eql(node.key, key)) {
                    return node.value;
                }
                walk = &node.children[hash >> 62];
            }
        }

        /// updates using the ptr are not synchronized
        pub fn getPtr(map: *Map, key: K) ?*V {
            var walk: *?*Node = &map.root;
            var hash = map.ctx.hash(key);
            while (true) : (hash <<= 2) {
                const node = @atomicLoad(?*Node, walk, .acquire) orelse return null;
                if (map.ctx.eql(node.key, key)) {
                    return &node.value;
                }
                walk = &node.children[hash >> 62];
            }
        }
    };
}

test "Map" {
    var arena_impl: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();
    var a: AutoMap(u32, u32) = .init();
    for (0..10) |i| {
        _ = try a.put(arena, @intCast(i), @intCast(3 * (i + 1)));
    }
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(3 * (i + 1))), a.get(@intCast(i)).?);
        try std.testing.expectEqual(@as(u32, @intCast(3 * (i + 1))), a.getPtr(@intCast(i)).?.*);
    }
    for (10..20) |i| {
        try std.testing.expectEqual(null, a.get(@intCast(i)));
    }
}
