const std = @import("std");

const BlockPool = @import("block_pool.zig").BlockPool;

pub const UntypedAggregateQueue = struct {
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
            page.header._values = std.mem.alignForward(
                usize,
                @intFromPtr(&page.bytes[0]),
                @alignOf(T),
            );
            page.header.next = null;
            return page;
        }

        fn push(page: *Page, comptime T: type, value: T) void {
            std.debug.assert(page.header.tail < page.header.capacity);
            page.values(T)[page.header.tail] = value;
            page.header.tail += 1;
        }

        fn peek(page: *const Page, comptime T: type) ?T {
            if (page.header.head == page.header.tail) return null;
            return @constCast(page).values(T)[page.header.head];
        }

        fn pop(page: *Page, comptime T: type) ?T {
            if (page.header.head == page.header.tail) return null;
            const value = page.values(T)[page.header.head];
            page.header.head += 1;
            return value;
        }

        fn full(page: *const Page) bool {
            return page.header.tail == page.header.capacity;
        }

        fn values(page: *Page, comptime T: type) [*]T {
            return @ptrFromInt(page.header._values);
        }

        fn debugPrint(page: *const Page, comptime T: type) void {
            std.debug.print("  Page: ", .{});
            for (page.header.head..page.header.tail) |i| {
                std.debug.print("{} ", .{@constCast(page).values(T)[i]});
            }
            std.debug.print("\n", .{});
        }
    };
    comptime {
        std.debug.assert(@sizeOf(Page) <= BlockPool.block_size);
    }

    pub const SubQueue = struct {

        // NOTE we have a singly linked list of pages
        // the page with the first value is at head, and is the actual head of the linked list
        // the page with the last value is at tail
        // end is the last page in the linked list
        // this setup ensures that we can ensure capacity beyond page-capacity limits

        pool: *BlockPool,
        head: ?*Page,
        tail: ?*Page,
        end: ?*Page,
        capacity: usize,

        fn ensureCapacity(queue: *SubQueue, comptime T: type, n: usize) !void {
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
                queue.capacity += end.header.capacity;
            }
        }

        pub fn push(queue: *SubQueue, comptime T: type, value: T) !void {
            try queue.ensureCapacity(T, 1);
            if (queue.tail.?.full()) queue.tail = queue.tail.?.header.next;
            queue.tail.?.push(T, value);
            queue.capacity -= 1;
        }

        pub fn pushAssumeCapacity(queue: *SubQueue, comptime T: type, value: T) void {
            std.debug.assert(queue.capacity >= 1);
            if (queue.tail.?.full()) queue.tail = queue.tail.?.header.next;
            queue.tail.?.push(T, value);
            queue.capacity -= 1;
        }
    };

    pool: *BlockPool,
    head: ?*Page,
    tail: ?*Page,
    mutex: std.Thread.Mutex,

    pub fn init(pool: *BlockPool) UntypedAggregateQueue {
        return .{
            .pool = pool,
            .head = null,
            .tail = null,
            .mutex = .{},
        };
    }

    pub fn deinit(aggregate_queue: *UntypedAggregateQueue) void {
        var walk = aggregate_queue.head;
        while (walk) |page| {
            walk = page.header.next;
            aggregate_queue.pool.destroy(page);
        }
        aggregate_queue.* = undefined;
    }

    pub fn acquire(aggregate_queue: *UntypedAggregateQueue) SubQueue {
        return .{
            .pool = aggregate_queue.pool,
            .head = null,
            .tail = null,
            .end = null,
            .capacity = 0,
        };
    }

    pub fn submit(aggregate_queue: *UntypedAggregateQueue, sub_queue: *SubQueue) void {
        // ideally this should be lock-free and made so we can read concurrently
        aggregate_queue.mutex.lock();
        defer aggregate_queue.mutex.unlock();

        if (aggregate_queue.tail) |tail| {
            tail.header.next = sub_queue.head;
            aggregate_queue.tail = sub_queue.tail;
        } else {
            aggregate_queue.head = sub_queue.head;
            aggregate_queue.tail = sub_queue.tail;
        }
        sub_queue.* = undefined;
    }

    /// not thread-safe
    pub fn peek(aggregate_queue: UntypedAggregateQueue, comptime T: type) ?T {
        const head = aggregate_queue.head orelse return null;
        return head.peek(T);
    }

    /// not thread-safe
    pub fn pop(aggregate_queue: *UntypedAggregateQueue, comptime T: type) ?T {
        while (true) {
            const head = aggregate_queue.head orelse return null;
            return head.pop(T) orelse {
                // page is empty move to next
                if (head.header.next == null) {
                    aggregate_queue.head = null;
                    aggregate_queue.tail = null;
                } else {
                    aggregate_queue.head = head.header.next;
                }
                aggregate_queue.pool.destroy(head);
                continue;
            };
        }
    }

    pub fn debugPrint(aggregate_queue: UntypedAggregateQueue, comptime T: type) void {
        std.debug.print("UntypedAggregateQueue <u32>\n", .{});
        var walk: ?*Page = aggregate_queue.head;
        while (walk) |page| {
            walk = page.header.next;
            page.debugPrint(T);
        }
    }
};

test "aggregate queue fuzz" {
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();
    var aq = UntypedAggregateQueue.init(&pool);
    defer aq.deinit();

    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    const rand = rng.random();

    for (0..10) |_| {
        var q0 = aq.acquire();
        var q1 = aq.acquire();

        var acc: u32 = 0;
        for (0..BlockPool.block_size / @sizeOf(u32) + 10) |_| {
            const x = rand.int(u32);
            const h = std.hash.XxHash32.hash(1337, std.mem.asBytes(&x));
            acc ^= h;

            if (rand.boolean()) {
                try q0.push(u32, x);
            } else {
                try q1.push(u32, x);
            }
        }

        aq.submit(&q0);
        aq.submit(&q1);

        var ref: u32 = 0;
        while (aq.pop(u32)) |x| {
            const h = std.hash.XxHash32.hash(1337, std.mem.asBytes(&x));
            ref ^= h;
        }

        try std.testing.expect(ref == acc);
    }
}
