const builtin = @import("builtin");
const std = @import("std");

const safe_mode = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

const BlockPoolConfig = struct {
    block_size: usize = 64 * 1024,
    n_blocks_min: usize = 1024,
};
pub const BlockPool = BlockPoolType(.{});

// TODO test
const Mutex = struct {
    const Node = struct {
        next: ?*Node = null,
        wait: bool = true,
    };

    tail: ?*Node = null,

    fn lock(mutex: *Mutex, node: *Node) void {
        const prev = @atomicRmw(?*Node, &mutex.tail, .Xchg, node, .acq_rel) orelse return;
        @atomicStore(?*Node, &prev.next, node, .release);
        while (@atomicLoad(bool, &node.wait, .acquire)) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(mutex: *Mutex, node: *Node) void {
        if (@atomicLoad(?*Node, &node.next, .acquire) == null) {
            if (@cmpxchgStrong(
                ?*Node,
                &mutex.tail,
                node,
                null,
                .release,
                .monotonic,
            ) == null) return;
            while (@atomicLoad(?*Node, &node.next, .acquire) == null) {
                std.atomic.spinLoopHint();
            }
        }
        const next = @atomicLoad(?*Node, &node.next, .acquire).?;
        @atomicStore(bool, &next.wait, false, .release);
    }
};

fn BlockPoolType(comptime config: BlockPoolConfig) type {
    std.debug.assert(std.math.isPowerOfTwo(config.block_size));
    std.debug.assert(config.n_blocks_min > 0);

    return struct {
        const Pool = @This();
        pub const block_size = config.block_size;

        const Segment = struct {
            capacity: usize,
            n_free: usize,
            free: ?*Block,
            bytes: []u8,

            fn lessThan(context: void, a: Segment, b: Segment) std.math.Order {
                _ = context;
                return std.math.order(a.n_free -% 1, b.n_free -% 1);
            }

            fn contains(segment: Segment, ptr: usize) bool {
                const base = @intFromPtr(segment.bytes.ptr);
                return ptr >= base and ptr < base + segment.bytes.len;
            }
        };

        // must be extern union, since the size must match block size even in debug mode
        const Block = extern union {
            bytes: [block_size]u8,
            next: ?*Block,
        };
        comptime {
            std.debug.assert(@sizeOf(Block) == block_size);
        }

        gpa: std.mem.Allocator,
        segments: std.PriorityQueue(Segment, void, Segment.lessThan),
        reserve: ?Segment,
        capacity: usize,
        n_free: usize,
        mutex: Mutex,

        pub fn init(gpa: std.mem.Allocator) Pool {
            return .{
                .gpa = gpa,
                .segments = .empty,
                .reserve = null,
                .capacity = 0,
                .n_free = 0,
                .mutex = .{},
            };
        }

        pub fn deinit(pool: *Pool) void {
            for (pool.segments.items) |segment| pool.gpa.free(segment.bytes);
            if (pool.reserve) |reserve| pool.gpa.free(reserve.bytes);
            pool.segments.deinit(pool.gpa);
            pool.* = undefined;
        }

        pub fn create(pool: *Pool, comptime T: type) !*T {
            var mutex_node: Mutex.Node = .{};
            pool.mutex.lock(&mutex_node);
            defer pool.mutex.unlock(&mutex_node);

            comptime std.debug.assert(@sizeOf(T) <= block_size);
            comptime std.debug.assert(@alignOf(T) <= block_size);
            if (pool.n_free == 0) try pool.expand();
            std.debug.assert(pool.segments.items.len > 0);
            var segment = pool.segments.pop().?;
            std.debug.assert(segment.n_free > 0);
            std.debug.assert(segment.free != null);
            const block = segment.free.?;
            segment.free = block.next;
            segment.n_free -= 1;
            pool.n_free -= 1;
            pool.segments.push(pool.gpa, segment) catch unreachable;
            return @ptrCast(@alignCast(block));
        }

        pub fn destroy(pool: *Pool, ptr: anytype) void {
            var mutex_node: Mutex.Node = .{};
            pool.mutex.lock(&mutex_node);
            defer pool.mutex.unlock(&mutex_node);

            std.debug.assert(pool.segments.items.len > 0);
            var ix: usize = undefined;
            for (pool.segments.items, 0..) |segment, i| {
                if (segment.contains(@intFromPtr(ptr))) {
                    ix = i;
                    break;
                }
            } else unreachable;
            var segment = pool.segments.popIndex(ix);
            const block: *Block = @ptrCast(@alignCast(ptr));
            block.next = segment.free;
            segment.free = block;
            segment.n_free += 1;
            pool.n_free += 1;

            if (segment.n_free < segment.capacity) {
                pool.segments.push(pool.gpa, segment) catch unreachable;
                return;
            }

            pool.capacity -= segment.capacity;
            pool.n_free -= segment.capacity;
            if (pool.reserve == null) {
                pool.reserve = segment;
            } else {
                const reserve = pool.reserve.?;
                if (reserve.capacity < segment.capacity) {
                    pool.gpa.free(reserve.bytes);
                    pool.reserve = segment;
                } else {
                    pool.gpa.free(segment.bytes);
                }
            }
        }

        fn expand(pool: *Pool) !void {
            try pool.segments.ensureUnusedCapacity(pool.gpa, 1);

            if (pool.reserve) |reserve| {
                std.debug.assert(reserve.n_free == reserve.capacity);
                pool.segments.push(pool.gpa, reserve) catch unreachable;
                std.debug.assert(reserve.n_free == reserve.capacity);
                pool.capacity += reserve.capacity;
                pool.n_free += reserve.capacity;
                pool.reserve = null;
                return;
            }

            // we are guaranteed to fit n blocks with the block_size alignment
            // in a continuous memory region of length (n + 1) * block_size
            const n_new = @max(config.n_blocks_min, pool.capacity);
            var segment = Segment{
                .capacity = 0,
                .n_free = 0,
                .free = null,
                .bytes = try pool.gpa.alloc(u8, block_size * (n_new + 1)),
            };
            var ptr = @intFromPtr(segment.bytes.ptr);
            for (0..n_new) |_| {
                ptr = std.mem.alignForward(usize, ptr, block_size);
                const block: *Block = @ptrFromInt(ptr);
                block.next = segment.free;
                segment.free = block;
                ptr += block_size;
                segment.capacity += 1;
            }
            segment.n_free = segment.capacity;
            pool.capacity += segment.capacity;
            pool.n_free += segment.capacity;
            pool.segments.push(pool.gpa, segment) catch unreachable;
        }
    };
}

test "block pool basic functions" {
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();

    const types = [_]type{ u8, u32, @Vector(4, f32), [1024]f64 };
    const N = 100;

    inline for (types) |T| {
        var addresses: std.AutoArrayHashMapUnmanaged(usize, void) = .empty;
        defer addresses.deinit(std.testing.allocator);

        for (0..N) |_| {
            const p = try pool.create(T);
            const a = @intFromPtr(p);
            try std.testing.expect(a % BlockPool.block_size == 0);
            try std.testing.expect(!addresses.contains(a));
            try addresses.put(std.testing.allocator, a, {});
        }

        for (addresses.keys()) |a| {
            const p: *T = @ptrFromInt(a);
            pool.destroy(p);
        }

        var addresses2: std.AutoArrayHashMapUnmanaged(usize, void) = .empty;
        defer addresses2.deinit(std.testing.allocator);

        for (0..2 * N) |_| {
            const p = try pool.create(T);
            const a = @intFromPtr(p);
            try std.testing.expect(a % BlockPool.block_size == 0);
            try std.testing.expect(!addresses2.contains(a));
            try addresses2.put(std.testing.allocator, a, {});
        }

        for (addresses2.keys()) |a| {
            const p: *T = @ptrFromInt(a);
            pool.destroy(p);
        }
    }
}
