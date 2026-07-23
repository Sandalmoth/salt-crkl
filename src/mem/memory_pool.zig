const std = @import("std");

pub fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();

        gpa: std.mem.Allocator,
        capacity: usize,
        // OPTIMIZE create by keeping full arrays in a separate linked list
        arrays: ?*SkipArray(T, u32),

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{
                .gpa = gpa,
                .capacity = 0,
                .arrays = null,
            };
        }

        pub fn deinit(pool: *Self) void {
            var walk = pool.arrays;
            while (walk) |array| {
                walk = array.next;
                array.deinit(pool.gpa);
            }
            pool.* = undefined;
        }

        pub fn create(pool: *Self) !*T {
            var walk = pool.arrays;
            while (walk) |array| {
                walk = array.next;
                if (array.full()) continue;
                return array.insertAssumeCapacity();
            }

            const additional_capacity: u32 = @truncate(
                @max(16, (pool.capacity / 8) * 13 - pool.capacity),
            );
            const array = try pool.gpa.create(SkipArray(T, u32));
            errdefer pool.gpa.destroy(array);
            array.* = try .init(pool.gpa, additional_capacity);
            array.next = pool.arrays;
            pool.arrays = array;
            return array.insertAssumeCapacity();
        }

        pub fn destroy(pool: *Self, ptr: *T) void {
            var walk = pool.arrays;
            while (walk) |array| {
                walk = array.next;
                if (array.getIndex(ptr)) |ix| {
                    _ = array.erase(ix);
                    return;
                }
            }
            unreachable; // double free or not from this allocator
        }

        pub fn iterator(pool: *Self) Iterator {
            return .{
                .pool = pool,
                .array = if (pool.arrays) |array| array.next else null,
                .array_iterator = if (pool.arrays) |array| array.iterator() else null,
            };
        }

        pub const Iterator = struct {
            pool: *Self,
            array: ?*SkipArray(T, u32),
            array_iterator: ?SkipArray(T, u32).Iterator,

            pub fn next(it: *Iterator) ?*T {
                if (it.array_iterator) |*array_iterator| {
                    const ptr = array_iterator.next();
                    if (ptr != null) return ptr;
                    if (it.array) |array| {
                        it.array = array.next;
                        it.array_iterator = array.iterator();
                    } else {
                        it.array_iterator = null;
                    }
                    return it.next();
                }
                return null;
            }
        };
    };
}

test "MemoryPool" {
    const N = 100;
    const M = 10_000;
    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    const rand = rng.random();

    {
        // repeatedly insert and erase, making sure contents are as expected
        const Pair = struct { ptr: *usize, value: usize };
        var ixs: std.ArrayList(Pair) = .empty;
        defer ixs.deinit(std.testing.allocator);

        var a: MemoryPool(usize) = .init(std.testing.allocator);
        defer a.deinit();

        var n: usize = 0;
        var i: usize = 0;
        var it = a.iterator();

        for (0..M) |_| {
            const insert_to = rand.intRangeLessThan(usize, n + 1, N);
            // const erase_to = rand.intRangeLessThan(usize, 0, insert_to);

            while (n < insert_to) : (n += 1) {
                const ptr = try a.create();
                ptr.* = i;
                try ixs.append(std.testing.allocator, .{ .ptr = ptr, .value = i });
                i += 1;
            }

            it = a.iterator();
            while (it.next()) |value_ptr| {
                var n_found: usize = 0;
                for (ixs.items) |kv| {
                    if (value_ptr != kv.ptr) continue;
                    try std.testing.expect(value_ptr.* == kv.value);
                    n_found += 1;
                }
                try std.testing.expect(n_found == 1);
            }

            // rand.shuffle(Pair, ixs.items);

            // while (n > erase_to) : (n -= 1) {
            //     const kv = ixs.pop().?;
            //     _ = a.destroy(kv.ptr);
            // }

            // it = a.iterator();
            // while (it.next()) |value_ptr| {
            //     var n_found: usize = 0;
            //     for (ixs.items) |kv| {
            //         if (value_ptr != kv.ptr) continue;
            //         try std.testing.expect(value_ptr.* == kv.value);
            //         n_found += 1;
            //     }
            //     try std.testing.expect(n_found == 1);
            // }
        }
    }
}

fn SkipArray(comptime T: type, comptime Skip: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            next: Skip,
            prev: Skip,
        };
        const Data = union {
            node: Node,
            value: T,
        };

        next: ?*Self,

        capacity: usize,
        skip: [*]Skip, // capacity + 1
        data: [*]Data, // capacity
        first_free_block: ?Skip,

        fn init(gpa: std.mem.Allocator, capacity: usize) !Self {
            std.debug.assert(capacity <= std.math.maxInt(Skip));
            const backing_memory = try gpa.alloc(Skip, size(capacity));

            // (sub)allocate and setup skiplist
            const skip: [*]Skip = backing_memory.ptr;
            skip[0] = @intCast(capacity);
            skip[capacity - 1] = @intCast(capacity);
            skip[capacity] = 0;

            // (sub)allocate data segment and setup free-block
            const data: [*]Data = @ptrFromInt(std.mem.alignForward(
                usize,
                @intFromPtr(backing_memory.ptr) + @sizeOf(Skip) * (capacity + 1),
                @alignOf(T),
            ));
            data[0] = .{ .node = .{
                .prev = 0,
                .next = 0,
            } };

            return .{
                .next = null,
                .capacity = capacity,
                .skip = skip,
                .data = data,
                .first_free_block = 0,
            };
        }

        fn deinit(array: *Self, gpa: std.mem.Allocator) void {
            const backing_memory = array.skip[0..size(array.capacity)];
            gpa.free(backing_memory);
            array.* = undefined;
        }

        fn size(capacity: usize) usize {
            const sizeof_skip = @sizeOf(Skip) * (capacity + 1) + @alignOf(Skip);
            const sizeof_data = @sizeOf(Data) * (capacity + 1) + @alignOf(Data);
            return (sizeof_skip + sizeof_data + @sizeOf(Skip) - 1) / @sizeOf(Skip);
        }

        fn full(array: Self) bool {
            return array.first_free_block == null;
        }

        fn empty(array: Self) bool {
            return array.skip[0] == array.capacity;
        }

        fn insertAssumeCapacity(array: *Self) *T {
            std.debug.assert(array.first_free_block != null);

            const ix = array.first_free_block.?;
            const skip = array.skip;
            const data = array.data;

            std.debug.assert(skip[ix] > 0);
            std.debug.assert(skip[ix] == skip[ix + skip[ix] - 1]);
            const free_block = data[ix].node;
            const free_block_len = skip[ix];

            skip[ix + 1] = skip[ix] - 1;
            if (skip[ix] > 2) skip[ix + skip[ix] - 1] -= 1;
            skip[ix] = 0;
            std.debug.assert(skip[ix + 1] < array.capacity - ix);

            data[ix] = .{ .value = undefined };

            if (free_block_len > 1) {
                data[ix + 1] = .{ .node = .{
                    .prev = ix + 1,
                    .next = if (free_block.next != ix) free_block.next else @intCast(ix + 1),
                } };
                if (free_block.next != ix) {
                    data[free_block.next].node.prev = ix + 1;
                }
                array.first_free_block.? += 1;
            } else {
                // free block is exhausted, remove from free list
                std.debug.assert(free_block.prev == ix);
                if (free_block.next != ix) {
                    data[free_block.next].node.prev = free_block.next;
                    array.first_free_block = free_block.next;
                } else {
                    // segment is completely full
                    array.first_free_block = null;
                }
            }

            return &array.data[ix].value;
        }

        fn erase(array: *Self, ix: Skip) T {
            const skip = array.skip;
            const data = array.data;

            std.debug.assert(skip[ix] == 0);
            const value = data[ix].value;

            const skip_left = if (ix == 0) 0 else skip[ix - 1];
            const skip_right = skip[ix + 1]; // NOTE may index into the padding skipfield
            // there are four options for the free block
            // a) both neighbours occupied, form new free block
            // b/c) one neighbour occupied (left/right), extend free block
            // d) both neighbours free, merge into the free block on the left
            // and the way to determine the case is to look at the skipfields
            if (skip_left == 0 and skip_right == 0) {
                skip[ix] = 1;
                data[ix] = .{ .node = .{
                    .prev = ix,
                    .next = array.first_free_block orelse ix,
                } };
                if (array.first_free_block) |first| array.data[first].node.prev = ix;
                array.first_free_block = ix;
            } else if (skip_left > 0 and skip_right == 0) {
                const new_block_len = skip_left + 1;
                skip[ix - skip[ix - 1]] = new_block_len;
                skip[ix] = new_block_len;
            } else if (skip_left == 0 and skip_right > 0) {
                const new_block_len = skip_right + 1;
                skip[ix + skip[ix + 1]] = new_block_len;
                skip[ix] = new_block_len;
                const old_block = data[ix + 1].node;
                data[ix] = .{ .node = .{
                    .prev = if (old_block.prev != ix + 1) old_block.prev else ix,
                    .next = if (old_block.next != ix + 1) old_block.next else ix,
                } };
                // since the free block has moved one step over, update the linked list
                if (old_block.prev == ix + 1) {
                    array.first_free_block = ix;
                } else {
                    data[old_block.prev].node.next = ix;
                }
                if (old_block.next != ix + 1) {
                    data[old_block.next].node.prev = ix;
                }
            } else if (skip_left > 0 and skip_right > 0) {
                const new_block_len = skip_left + skip_right + 1;
                skip[ix - skip[ix - 1]] = new_block_len;
                skip[ix + skip[ix + 1]] = new_block_len;
                // now remove the skip block on the right
                const old_block = data[ix + 1].node;
                if (old_block.prev != ix + 1) {
                    data[old_block.prev].node.next = if (old_block.next != ix + 1)
                        old_block.next
                    else
                        old_block.prev;
                } else {
                    array.first_free_block = if (old_block.next != ix + 1)
                        old_block.next
                    else
                        null;
                }
                if (old_block.next != ix + 1) {
                    data[old_block.next].node.prev = if (old_block.prev != ix + 1)
                        old_block.prev
                    else
                        old_block.next;
                }
            } else unreachable;

            return value;
        }

        fn getIndex(array: *Self, ptr: *T) ?Skip {
            const ptr_addr = @intFromPtr(ptr);
            const data_addr = @intFromPtr(array.data);
            if (ptr_addr < data_addr or
                ptr_addr >= data_addr + array.capacity * @sizeOf(T)) return null;
            return @intCast((@intFromPtr(ptr) - @intFromPtr(array.data)) / @sizeOf(T));
        }

        const Iterator = struct {
            const Cursor =
                switch (Skip) {
                    u16 => u32,
                    u32 => u64,
                    else => @compileError("unsupported skipfield size"),
                };

            cursor: Cursor,
            capacity: usize,
            data: [*]Data,
            skip: [*]Skip,

            const dummy: Iterator = .{
                .cursor = std.math.maxInt(Cursor),
                .capacity = 0,
                .data = undefined,
                .skip = undefined,
            };

            fn next(it: *Iterator) ?*T {
                if (it.cursor >= it.capacity) return null;
                const value_ptr = &it.data[it.cursor].value;
                it.cursor += 1;
                it.cursor += it.skip[it.cursor];
                return value_ptr;
            }
        };

        fn iterator(array: *Self) Iterator {
            return .{
                .cursor = array.skip[0],
                .capacity = array.capacity,
                .data = array.data,
                .skip = array.skip,
            };
        }

        fn debugPrint(array: Self) void {
            std.debug.print("SkipArray <{s}>, ", .{@typeName(T)});
            std.debug.print("skipfield size: {s}, ", .{@typeName(Skip)});
            std.debug.print("capacity: {}\n", .{array.capacity});
            std.debug.print("  skip:", .{});
            for (array.skip[0 .. array.capacity + 1]) |skip| std.debug.print(" {}", .{skip});
            std.debug.print("\n", .{});
            std.debug.print("  freelist: ", .{});
            if (array.first_free_block) |first_free_block| {
                var i = first_free_block;
                while (true) {
                    const node = array.data[i].node;
                    std.debug.print("({} [{}] {})", .{ node.prev, i, node.next });
                    if (node.next == i) break;
                    std.debug.print("->", .{});
                    i = node.next;
                }
            } else {
                std.debug.print("[skiparray is full]", .{});
            }
            std.debug.print("\n", .{});
        }
    };
}
