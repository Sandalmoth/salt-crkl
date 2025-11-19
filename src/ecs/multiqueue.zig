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

        fn full(page: *Page) bool {
            return page.header.tail == page.header.capacity;
        }

        fn values(page: *Page, comptime T: type) [*]T {
            return @ptrFromInt(page.header._values);
        }
    };
    comptime {
        std.debug.assert(@sizeOf(Page) <= BlockPool.block_size);
    }

    pub const UntypedQueue = struct {

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

        fn ensureCapacity(queue: *UntypedQueue, comptime T: type, n: usize) !void {
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

        pub fn push(queue: *UntypedQueue, comptime T: type, value: T) !void {
            try queue.ensureCapacity(T, 1);
            if (queue.tail.?.full()) queue.tail = queue.tail.?.header.next;
            queue.tail.?.push(T, value);
            queue.capacity -= 1;
        }

        pub fn pushAssumeCapacity(queue: *UntypedQueue, comptime T: type, value: T) void {
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

    pub fn acquireQueue(aggregate_queue: *UntypedAggregateQueue) UntypedQueue {
        return .{ .pool = aggregate_queue.pool, .head = null };
    }

    pub fn releaseQueue(aggregate_queue: *UntypedAggregateQueue, queue: *UntypedQueue) void {
        // ideally this should be lock-free and made so we can read concurrently
        aggregate_queue.mutex.lock();
        defer aggregate_queue.mutex.unlock();

        if (aggregate_queue.tail) |tail| {
            tail.header.next = queue.head;
        } else {
            aggregate_queue.tail = queue.head;
        }
        queue.* = undefined;
    }

    /// not thread-safe
    pub fn peek(aggregate_queue: *UntypedAggregateQueue, comptime T: type) ?T {
        const head = aggregate_queue.head orelse return null;
        return head.peek(T);
    }

    /// not thread-safe
    pub fn pop(aggregate_queue: *UntypedAggregateQueue, comptime T: type) ?T {
        const head = aggregate_queue.head orelse return null;
        const value = head.pop(T) orelse return null;
        if (head.header.head == head.header.capacity) {
            aggregate_queue.head = head.header.next;
            if (aggregate_queue.head == null) {
                // if our head ran out of capacity, and it was also end, null out the tail/end
                aggregate_queue.tail = null;
                aggregate_queue.end = null;
            }
            aggregate_queue.pool.destroy(head);
        }
        return value;
    }
};
