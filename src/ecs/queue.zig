const std = @import("std");

const BlockPool = @import("block_pool.zig").BlockPool;

/// either multiple threads writing to queue, or single thread reading/writing
pub const UntypedQueue = struct {
    // NOTE lock-free-ish possible?

    const Page = struct {
        const Header = struct {
            head: usize,
            tail: usize,
            capacity: usize,
            _values: usize,
            next: ?*Page,
        };
        header: Header,
        bytes: [BlockPool.block_size - @sizeOf(Header)]u8,

        fn create(pool: *BlockPool, comptime T: type) !*Page {
            const page = try pool.create(Page);
            page.header.head = 0;
            page.header.tail = 0;
            page.header.capacity = page.bytes.len / @sizeOf(T) - 1;
            page.header._values = std.mem.alignForward(usize, @intFromPtr(&page.bytes[0]), @alignOf(T));
            page.header.next = null;
            return page;
        }

        fn push(page: *Page, comptime T: type, value: T) void {
            std.debug.assert(page.header.tail < page.header.capacity);
            page.values(T)[page.header.tail] = value;
            page.header.tail += 1;
        }

        fn peek(page: *Page, comptime T: type) ?T {
            if (page.header.head == page.header.tail) return null;
            return page.values(T)[page.header.head];
        }

        fn pop(page: *Page, comptime T: type) ?T {
            if (page.header.head == page.header.tail) return null;
            const value = page.values(T)[page.header.head];
            page.header.head += 1;
            return value;
        }

        fn values(page: *Page, comptime T: type) [*]T {
            return @ptrFromInt(page.header._values);
        }

        fn full(page: *Page) bool {
            return page.header.tail == page.header.capacity;
        }
    };
    comptime {
        std.debug.assert(@sizeOf(Page) <= BlockPool.block_size);
    }

    // NOTE we have a singly linked list of pages
    // the page with the first value is at head, and is the actual head of the linked list
    // the page with the last value is at tail
    // end is the last page in the linked list
    // this setup ensures that we can ensure capacity beyond page-capacity limits

    pool: *BlockPool,
    len: usize,
    capacity: usize,
    head: ?*Page,
    tail: ?*Page,
    end: ?*Page,
    mutex: std.Thread.Mutex,

    pub fn init(pool: *BlockPool) UntypedQueue {
        return .{
            .pool = pool,
            .len = 0,
            .capacity = 0,
            .head = null,
            .tail = null,
            .end = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(queue: *UntypedQueue) void {
        var walk = queue.head;
        while (walk) |page| {
            walk = page.header.next;
            queue.pool.destroy(page);
        }
        queue.* = undefined;
    }

    pub fn reset(queue: *UntypedQueue) void {
        const pool = queue.pool;
        queue.deinit();
        queue.* = UntypedQueue.init(pool);
    }

    /// protected by mutex
    pub fn ensureCapacity(queue: *UntypedQueue, comptime T: type, n: usize) !void {
        queue.mutex.lock();
        defer queue.mutex.unlock();
        try queue.ensureCapacityUnprotected(T, n);
    }
    fn ensureCapacityUnprotected(queue: *UntypedQueue, comptime T: type, n: usize) !void {
        if (queue.end == null) {
            std.debug.assert(queue.head == null);
            std.debug.assert(queue.tail == null);
            queue.end = try Page.create(queue.pool, T);
            queue.head = queue.end;
            queue.tail = queue.end;
            queue.capacity += queue.end.?.header.capacity;
        }

        while (queue.capacity < n) {
            const end = try Page.create(queue.pool, T);
            queue.end.?.header.next = end;
            queue.end = end;
            queue.capacity += queue.end.?.header.capacity;
        }
    }

    /// protected by mutex
    pub fn push(queue: *UntypedQueue, comptime T: type, value: T) !void {
        queue.mutex.lock();
        defer queue.mutex.unlock();
        try queue.ensureCapacityUnprotected(T, 1);
        if (queue.tail.?.full()) queue.tail = queue.tail.?.header.next;
        queue.tail.?.push(T, value);
        queue.len += 1;
        queue.capacity -= 1;
    }

    /// protected by mutex
    pub fn pushAssumeCapacity(queue: *UntypedQueue, comptime T: type, value: T) void {
        queue.mutex.lock();
        defer queue.mutex.unlock();
        std.debug.assert(queue.capacity >= 1);
        if (queue.tail.?.full()) queue.tail = queue.tail.?.header.next;
        queue.tail.?.push(T, value);
        queue.len += 1;
        queue.capacity -= 1;
    }

    pub fn peek(queue: UntypedQueue, comptime T: type) ?T {
        const head = queue.head orelse return null;
        return head.peek(T);
    }

    pub fn pop(queue: *UntypedQueue, comptime T: type) ?T {
        const head = queue.head orelse return null;
        const value = head.pop(T) orelse return null;
        if (head.header.head == head.header.capacity) {
            queue.head = head.header.next;
            if (queue.head == null) {
                // if our head ran out of capacity, and it was also end, null out the tail/end
                queue.tail = null;
                queue.end = null;
            }
            queue.pool.destroy(head);
        }
        queue.len -= 1;
        return value;
    }

    pub fn count(queue: UntypedQueue) usize {
        return queue.len;
    }
};

test "queue edge cases" {
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();
    var q = UntypedQueue.init(&pool);
    defer q.deinit();
    var a: std.ArrayList(u32) = .empty;
    defer a.deinit();

    for (0..10) |i| {
        a.clearRetainingCapacity();
        for (0..4085) |j| {
            const x: u32 = @intCast(i * 1000_000 + j);
            try a.append(x);
            try q.push(u32, x);
            try std.testing.expectEqual(a.items.len, q.count());
        }
        for (a.items) |x| {
            try std.testing.expectEqual(x, q.pop(u32));
        }
        try std.testing.expectEqual(null, q.pop(u32));
    }

    for (0..10) |i| {
        a.clearRetainingCapacity();
        try q.ensureCapacity(u32, 4085);
        for (0..4085) |j| {
            const x: u32 = @intCast(i * 1000_000 + j);
            try a.append(x);
            try q.push(u32, x);
            try std.testing.expectEqual(a.items.len, q.count());
        }
        for (a.items) |x| {
            try std.testing.expectEqual(x, q.pop(u32));
        }
        try std.testing.expectEqual(null, q.pop(u32));
        a.clearRetainingCapacity();
        for (0..4085) |j| {
            const x: u32 = @intCast(i * 1000_000 + j);
            try a.append(x);
            try q.push(u32, x);
            try std.testing.expectEqual(a.items.len, q.count());
        }
        for (a.items) |x| {
            try std.testing.expectEqual(x, q.pop(u32));
        }
        try std.testing.expectEqual(null, q.pop(u32));
    }
}

test "queue fuzz" {
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();
    var q = UntypedQueue.init(&pool);
    defer q.deinit();
    var a = std.ArrayList(u32).init(std.testing.allocator);
    defer a.deinit();

    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    const rand = rng.random();

    for (0..1000) |_| {
        a.clearRetainingCapacity();
        const y = rand.uintLessThan(usize, 10000);
        try q.ensureCapacity(u32, y / 2);
        for (0..y) |_| {
            const x = rand.int(u32);
            try a.append(x);
            try q.push(u32, x);
            try std.testing.expectEqual(a.items.len, q.count());
        }
        for (a.items) |x| {
            try std.testing.expectEqual(x, q.pop(u32));
        }
        try std.testing.expectEqual(null, q.pop(u32));
    }
}

pub fn TypedQueue(comptime T: type) type {
    return struct {
        const Queue = @This();

        untyped: UntypedQueue,

        pub fn init(pool: *BlockPool) Queue {
            return .{ .untyped = UntypedQueue.init(pool) };
        }

        pub fn deinit(queue: *Queue) void {
            queue.untyped.deinit();
        }

        pub fn reset(queue: *Queue) void {
            queue.untyped.reset();
        }

        /// thread safe
        pub fn ensureCapacity(queue: *Queue, n: usize) !void {
            try queue.untyped.ensureCapacity(T, n);
        }

        /// thread safe
        pub fn push(queue: *Queue, value: T) !void {
            try queue.untyped.push(T, value);
        }

        /// thread safe
        pub fn pushAssumeCapacity(queue: *Queue, value: T) void {
            queue.untyped.pushAssumeCapacity(T, value);
        }

        pub fn peek(queue: Queue) ?T {
            queue.untyped.peek(T);
        }

        pub fn pop(queue: *Queue) ?T {
            queue.untyped.peek(T);
        }

        pub fn count(queue: Queue) usize {
            return queue.untyped.len;
        }
    };
}
