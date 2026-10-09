const std = @import("std");

pub const SlotAllocator = struct {
    const Node = struct {
        next: u32,
        prev: u32,
    };

    capacity: usize,
    skip: [*]u32, // .len == capacity + 1
    nodes: [*]Node, // .len == capacity
    first_free_block: ?u32,

    pub fn init(gpa: std.mem.Allocator, capacity: u32) !SlotAllocator {
        const backing_memory = try gpa.alloc(u32, size(capacity));

        // (sub)allocate and setup skiplist
        const skip: [*]u32 = backing_memory.ptr;
        skip[0] = @intCast(capacity);
        skip[capacity - 1] = @intCast(capacity);
        skip[capacity] = 0;

        // (sub)allocate nodes segment and setup free-block
        const nodes: [*]Node = @ptrFromInt(std.mem.alignForward(
            usize,
            @intFromPtr(backing_memory.ptr) + @sizeOf(u32) * (capacity + 1),
            @alignOf(Node),
        ));
        nodes[0] = .{
            .prev = 0,
            .next = 0,
        };

        return .{
            .capacity = capacity,
            .skip = skip,
            .nodes = nodes,
            .first_free_block = 0,
        };
    }

    pub fn deinit(alloc: *SlotAllocator, gpa: std.mem.Allocator) void {
        const backing_memory = alloc.skip[0..size(alloc.capacity)];
        gpa.free(backing_memory);
        alloc.* = undefined;
    }

    pub fn full(array: SlotAllocator) bool {
        return array.first_free_block == null;
    }

    pub fn empty(array: SlotAllocator) bool {
        return array.skip[0] == array.capacity;
    }

    pub fn acquire(alloc: *SlotAllocator) !u32 {
        if (alloc.first_free_block == null) return error.OutOfSlots;

        const slot = alloc.first_free_block.?;
        const skip = alloc.skip;
        const nodes = alloc.nodes;

        std.debug.assert(skip[slot] > 0);
        std.debug.assert(skip[slot] == skip[slot + skip[slot] - 1]);
        const free_block = nodes[slot];
        const free_block_len = skip[slot];

        skip[slot + 1] = skip[slot] - 1;
        if (skip[slot] > 2) skip[slot + skip[slot] - 1] -= 1;
        skip[slot] = 0;
        std.debug.assert(skip[slot + 1] < alloc.capacity - slot);

        nodes[slot] = undefined;

        if (free_block_len > 1) {
            nodes[slot + 1] = .{
                .prev = slot + 1,
                .next = if (free_block.next != slot) free_block.next else @intCast(slot + 1),
            };
            if (free_block.next != slot) {
                nodes[free_block.next].prev = slot + 1;
            }
            alloc.first_free_block.? += 1;
        } else {
            // free block is exhausted, remove from free list
            std.debug.assert(free_block.prev == slot);
            if (free_block.next != slot) {
                nodes[free_block.next].prev = free_block.next;
                alloc.first_free_block = free_block.next;
            } else {
                // segment is completely full
                alloc.first_free_block = null;
            }
        }

        return slot;
    }

    pub fn release(alloc: *SlotAllocator, slot: u32) void {
        const skip = alloc.skip;
        const nodes = alloc.nodes;

        std.debug.assert(skip[slot] == 0);

        const skip_left = if (slot == 0) 0 else skip[slot - 1];
        const skip_right = skip[slot + 1]; // NOTE may index into the padding skipfield
        // there are four options for the free block
        // a) both neighbours occupied, form new free block
        // b/c) one neighbour occupied (left/right), extend free block
        // d) both neighbours free, merge into the free block on the left
        // and the way to determine the case is to look at the skipfields
        if (skip_left == 0 and skip_right == 0) {
            skip[slot] = 1;
            nodes[slot] = .{
                .prev = slot,
                .next = alloc.first_free_block orelse slot,
            };
            if (alloc.first_free_block) |first| alloc.nodes[first].prev = slot;
            alloc.first_free_block = slot;
        } else if (skip_left > 0 and skip_right == 0) {
            const new_block_len = skip_left + 1;
            skip[slot - skip[slot - 1]] = new_block_len;
            skip[slot] = new_block_len;
        } else if (skip_left == 0 and skip_right > 0) {
            const new_block_len = skip_right + 1;
            skip[slot + skip[slot + 1]] = new_block_len;
            skip[slot] = new_block_len;
            const old_block = nodes[slot + 1];
            nodes[slot] = .{
                .prev = if (old_block.prev != slot + 1) old_block.prev else slot,
                .next = if (old_block.next != slot + 1) old_block.next else slot,
            };
            // since the free block has moved one step over, update the linked list
            if (old_block.prev == slot + 1) {
                alloc.first_free_block = slot;
            } else {
                nodes[old_block.prev].next = slot;
            }
            if (old_block.next != slot + 1) {
                nodes[old_block.next].prev = slot;
            }
        } else if (skip_left > 0 and skip_right > 0) {
            const new_block_len = skip_left + skip_right + 1;
            skip[slot - skip[slot - 1]] = new_block_len;
            skip[slot + skip[slot + 1]] = new_block_len;
            // now remove the skip block on the right
            const old_block = nodes[slot + 1];
            if (old_block.prev != slot + 1) {
                nodes[old_block.prev].next = if (old_block.next != slot + 1)
                    old_block.next
                else
                    old_block.prev;
            } else {
                alloc.first_free_block = if (old_block.next != slot + 1)
                    old_block.next
                else
                    null;
            }
            if (old_block.next != slot + 1) {
                nodes[old_block.next].prev = if (old_block.prev != slot + 1)
                    old_block.prev
                else
                    old_block.next;
            }
        } else unreachable;
    }

    pub const Iterator = struct {
        cursor: u64,
        capacity: usize,
        nodes: [*]Node,
        skip: [*]u32,

        const dummy: Iterator = .{
            .cursor = std.math.maxInt(u64),
            .capacity = 0,
            .nodes = undefined,
            .skip = undefined,
        };

        fn next(it: *Iterator) ?u32 {
            if (it.cursor >= it.capacity) return null;
            const slot = it.cursor;
            it.cursor += 1;
            it.cursor += it.skip[it.cursor];
            return @intCast(slot);
        }
    };

    pub fn iterator(alloc: *SlotAllocator) Iterator {
        return .{
            .cursor = alloc.skip[0],
            .capacity = alloc.capacity,
            .nodes = alloc.nodes,
            .skip = alloc.skip,
        };
    }

    fn size(capacity: usize) usize {
        const sizeof_skip = @sizeOf(u32) * (capacity + 1);
        const sizeof_nodes = @sizeOf(Node) * capacity + @alignOf(Node);
        return (sizeof_skip + sizeof_nodes + @sizeOf(u32) - 1) / @sizeOf(u32);
    }
};

// --- AI generated tests --- //

const testing = std.testing;

fn expectInFlightSlots(
    alloc: *SlotAllocator,
    expected: []const u32,
) !void {
    var it = alloc.iterator();
    var i: usize = 0;
    while (it.next()) |slot| : (i += 1) {
        try testing.expect(i < expected.len);
        try testing.expectEqual(expected[i], slot);
    }
    try testing.expectEqual(expected.len, i);
}

test "init: empty, not full, iterator yields nothing" {
    var alloc = try SlotAllocator.init(testing.allocator, 8);
    defer alloc.deinit(testing.allocator);

    try testing.expect(alloc.empty());
    try testing.expect(!alloc.full());
    try expectInFlightSlots(&alloc, &.{});
}

test "acquire hands out every slot once, then OutOfSlots" {
    const capacity = 8;
    var alloc = try SlotAllocator.init(testing.allocator, capacity);
    defer alloc.deinit(testing.allocator);

    for (0..capacity) |i| {
        try testing.expect(!alloc.full());
        try testing.expectEqual(@as(u32, @intCast(i)), try alloc.acquire());
    }
    try testing.expect(alloc.full());
    try testing.expect(!alloc.empty());
    try testing.expectError(error.OutOfSlots, alloc.acquire());
    try expectInFlightSlots(&alloc, &.{ 0, 1, 2, 3, 4, 5, 6, 7 });
}

test "release with both neighbours occupied forms a new free block" {
    // case (a)
    var alloc = try SlotAllocator.init(testing.allocator, 4);
    defer alloc.deinit(testing.allocator);

    _ = try alloc.acquire(); // 0
    _ = try alloc.acquire(); // 1
    _ = try alloc.acquire(); // 2
    alloc.release(1);

    try expectInFlightSlots(&alloc, &.{ 0, 2 });
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expectEqual(@as(u32, 3), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release extends the free block on the left" {
    // case (b): left neighbour free, right neighbour occupied
    var alloc = try SlotAllocator.init(testing.allocator, 4);
    defer alloc.deinit(testing.allocator);

    for (0..4) |_| _ = try alloc.acquire();
    alloc.release(1); // block {1}
    alloc.release(2); // extends {1} to {1,2}

    try expectInFlightSlots(&alloc, &.{ 0, 3 });
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expectEqual(@as(u32, 2), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release extends the free block on the right (head)" {
    // case (c) where the extended block is the head of the free list
    var alloc = try SlotAllocator.init(testing.allocator, 4);
    defer alloc.deinit(testing.allocator);

    for (0..4) |_| _ = try alloc.acquire();
    alloc.release(2); // block {2}, head
    alloc.release(1); // extends to {1,2}, head moves to 1

    try expectInFlightSlots(&alloc, &.{ 0, 3 });
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expectEqual(@as(u32, 2), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release extends a non-head free block on the right" {
    // case (c) where the extended block is mid-list: exercises the
    // nodes[old_block.prev].next relink instead of the head update
    var alloc = try SlotAllocator.init(testing.allocator, 8);
    defer alloc.deinit(testing.allocator);

    for (0..8) |_| _ = try alloc.acquire();
    alloc.release(5); // list: {5}
    alloc.release(1); // list: {1} -> {5}
    alloc.release(4); // extends {5} to {4,5}, still after {1}

    try expectInFlightSlots(&alloc, &.{ 0, 2, 3, 6, 7 });
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expectEqual(@as(u32, 4), try alloc.acquire());
    try testing.expectEqual(@as(u32, 5), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release merges with free blocks on both sides" {
    // case (d) where the removed right block is the head
    var alloc = try SlotAllocator.init(testing.allocator, 5);
    defer alloc.deinit(testing.allocator);

    for (0..5) |_| _ = try alloc.acquire();
    alloc.release(1); // block {1}
    alloc.release(3); // block {3}, head
    alloc.release(2); // merges into {1,2,3}, unlinks {3}

    try expectInFlightSlots(&alloc, &.{ 0, 4 });
    // the merged block must be whole: three acquisitions, then full
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expectEqual(@as(u32, 2), try alloc.acquire());
    try testing.expectEqual(@as(u32, 3), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "merge unlinks a mid-list free block" {
    // case (d) where the removed right block is in the middle of the
    // free list: exercises both relink branches
    var alloc = try SlotAllocator.init(testing.allocator, 8);
    defer alloc.deinit(testing.allocator);

    for (0..8) |_| _ = try alloc.acquire();
    alloc.release(6); // list: {6}
    alloc.release(2); // list: {2} -> {6}
    alloc.release(4); // list: {4} -> {2} -> {6}
    alloc.release(5); // merges to {4,5,6}, {6} unlinked from the tail

    try expectInFlightSlots(&alloc, &.{ 0, 1, 3, 7 });
    try testing.expectEqual(@as(u32, 4), try alloc.acquire());
    try testing.expectEqual(@as(u32, 5), try alloc.acquire());
    try testing.expectEqual(@as(u32, 6), try alloc.acquire());
    try testing.expectEqual(@as(u32, 2), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release at the left edge" {
    var alloc = try SlotAllocator.init(testing.allocator, 4);
    defer alloc.deinit(testing.allocator);

    _ = try alloc.acquire(); // 0
    _ = try alloc.acquire(); // 1
    alloc.release(0); // case (a) at slot 0 (no left neighbour)
    try expectInFlightSlots(&alloc, &.{1});
    try testing.expectEqual(@as(u32, 0), try alloc.acquire());

    _ = try alloc.acquire(); // 2
    _ = try alloc.acquire(); // 3
    alloc.release(1);
    alloc.release(0); // case (c) at slot 0: extends block {1}
    try expectInFlightSlots(&alloc, &.{ 2, 3 });
    try testing.expectEqual(@as(u32, 0), try alloc.acquire());
    try testing.expectEqual(@as(u32, 1), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "release at the right edge" {
    var alloc = try SlotAllocator.init(testing.allocator, 4);
    defer alloc.deinit(testing.allocator);

    for (0..4) |_| _ = try alloc.acquire();
    alloc.release(3); // case (a), reads the padding skipfield
    try expectInFlightSlots(&alloc, &.{ 0, 1, 2 });
    try testing.expectEqual(@as(u32, 3), try alloc.acquire());

    alloc.release(2);
    alloc.release(3); // case (b) at the last slot: extends {2}
    try expectInFlightSlots(&alloc, &.{ 0, 1 });
    try testing.expectEqual(@as(u32, 2), try alloc.acquire());
    try testing.expectEqual(@as(u32, 3), try alloc.acquire());
    try testing.expect(alloc.full());
}

test "capacity of one" {
    var alloc = try SlotAllocator.init(testing.allocator, 1);
    defer alloc.deinit(testing.allocator);

    try testing.expect(alloc.empty());
    try testing.expectEqual(@as(u32, 0), try alloc.acquire());
    try testing.expect(alloc.full());
    try testing.expectError(error.OutOfSlots, alloc.acquire());
    alloc.release(0);
    try testing.expect(alloc.empty());
    try testing.expectEqual(@as(u32, 0), try alloc.acquire());
}

test "releasing everything coalesces back into a single block" {
    const capacity = 16;
    var alloc = try SlotAllocator.init(testing.allocator, capacity);
    defer alloc.deinit(testing.allocator);

    // ascending release: repeated case (b)
    for (0..capacity) |_| _ = try alloc.acquire();
    for (0..capacity) |i| alloc.release(@intCast(i));
    try testing.expect(alloc.empty());
    // a single well-formed block hands out 0..n in order again
    for (0..capacity) |i| {
        try testing.expectEqual(@as(u32, @intCast(i)), try alloc.acquire());
    }

    // descending release: repeated case (c)
    for (0..capacity) |i| alloc.release(@intCast(capacity - 1 - i));
    try testing.expect(alloc.empty());
    for (0..capacity) |i| {
        try testing.expectEqual(@as(u32, @intCast(i)), try alloc.acquire());
    }

    // evens then odds: isolated blocks (a), then merges (d) and (b)
    var i: u32 = 0;
    while (i < capacity) : (i += 2) alloc.release(i);
    i = 1;
    while (i < capacity) : (i += 2) alloc.release(i);
    try testing.expect(alloc.empty());
    for (0..capacity) |j| {
        try testing.expectEqual(@as(u32, @intCast(j)), try alloc.acquire());
    }
    try testing.expect(alloc.full());
}

test "iterator yields in-flight slots in ascending order" {
    var alloc = try SlotAllocator.init(testing.allocator, 8);
    defer alloc.deinit(testing.allocator);

    for (0..8) |_| _ = try alloc.acquire();
    alloc.release(1);
    alloc.release(4);
    alloc.release(5);
    alloc.release(7);

    try expectInFlightSlots(&alloc, &.{ 0, 2, 3, 6 });

    // refilling the gaps restores dense iteration
    for (0..4) |_| _ = try alloc.acquire();
    try expectInFlightSlots(&alloc, &.{ 0, 1, 2, 3, 4, 5, 6, 7 });
}

test "fuzz: random acquire/release against a model" {
    const capacity = 128;
    var alloc = try SlotAllocator.init(testing.allocator, capacity);
    defer alloc.deinit(testing.allocator);

    var occupied = [_]bool{false} ** capacity;
    var held: [capacity]u32 = undefined;
    var held_len: usize = 0;

    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rand = prng.random();

    for (0..5_000) |_| {
        if (held_len == capacity or
            (held_len > 0 and rand.uintLessThan(u8, 3) == 0))
        {
            // release a random held slot
            const i = rand.uintLessThan(usize, held_len);
            const slot = held[i];
            held[i] = held[held_len - 1];
            held_len -= 1;
            occupied[slot] = false;
            alloc.release(slot);
        } else {
            const slot = try alloc.acquire();
            try testing.expect(!occupied[slot]); // no double-allocation
            occupied[slot] = true;
            held[held_len] = slot;
            held_len += 1;
        }

        // after every step the iterator must yield exactly the
        // occupied slots, in ascending order
        var it = alloc.iterator();
        for (0..capacity) |s| {
            if (!occupied[s]) continue;
            const got = it.next() orelse return error.TestUnexpectedResult;
            try testing.expectEqual(@as(u32, @intCast(s)), got);
        }
        try testing.expect(it.next() == null);
        try testing.expectEqual(held_len == 0, alloc.empty());
        try testing.expectEqual(held_len == capacity, alloc.full());
    }
}
