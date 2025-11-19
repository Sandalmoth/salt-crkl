const std = @import("std");

const starting_block_size = 1000.0;
const adapt_rate = 0.1; // ideally we should also adapt this somehow?
const regularity = 0.05; // how can we express this in natural units, can it be adapted too?

fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        const Buffer = struct {
            top: usize,
            values: []T,
        };
        const buffer_header_size = std.mem.alignForward(usize, @sizeOf(Buffer), @alignOf(T));

        buffer: ?*Buffer,
        mutex: std.Thread.Mutex,

        const empty: Self = .{
            .buffer = null,
            .mutex = .{},
        };

        pub fn deinit(stack: *Self) void {
            stack.* = undefined;
        }

        pub fn push(stack: *Self, gpa: std.mem.Allocator, value: T) !void {
            const buffer = @atomicLoad(*Buffer, &stack.buffer, .acquire);
            const ix = @atomicRmw(usize, &buffer.top, .Add, 1, .acq_rel); // not sure about order
            if (ix < buffer.capacity) {
                buffer.values[ix] = value;
            } else {
                if (stack.mutex.tryLock()) {
                    defer stack.mutex.unlock();
                    const new_buffer_len = buffer.values.len * 13 / 8;
                    const bytes = gpa.alloc(
                        u8,
                        buffer_header_size + @sizeOf(T) * new_buffer_len,
                    ) catch |e| {
                        // restore the stack to functioning order before returning the error
                        _ = @atomicRmw(usize, &buffer.top, .Sub, 1, .acq_rel);
                        stack.mutex.unlock();
                        return e;
                    };
                    const new_buffer: *Buffer = @ptrCast(@alignCast(bytes.ptr));
                    new_buffer.top = buffer.top;
                    new_buffer.values = @as(
                        [*]T,
                        @ptrCast(@alignCast(bytes + buffer_header_size)),
                    )[0..new_buffer_len];
                    @memcpy(new_buffer.values, buffer.values);
                    new_buffer.values[ix] = value;
                } else {}
            }
        }

        pub fn pop(stack: *Self) ?T {
            _ = stack;
        }
    };
}

pub const ArenaPool = struct {
    const Node = struct {
        data: usize,
        end: usize,
        node: ?*Node = null,
    };

    const Arena = struct {
        next: std.SinglyLinkedList.Node = .{},
        nodes: ?*Node = null,

        fn allocator(arena: *Arena) std.mem.Allocator {
            _ = arena;
            return undefined;
        }
    };

    child_allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,

    nodes: ?*Node = null,

    live_arena_list: std.SinglyLinkedList = .{},
    dead_arena_list: std.SinglyLinkedList = .{},
    block_size: f64 = starting_block_size,
    mutex: std.Thread.Mutex = .{},

    pub fn acquire(pool: *ArenaPool) !std.mem.Allocator {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        if (pool.dead_arena_list.first == null) {
            const arena = try pool.child_allocator.create(Arena);
            pool.dead_arena_list.prepend(arena.next);
        }

        const arena: Arena = @fieldParentPtr("next", pool.dead_arena_list.first.?);
        arena.* = .{};
        arena.nodes = pool.popBuf() orelse try pool.newNode();
        pool.live_arena_list.prepend(pool.dead_arena_list.popFirst());

        return arena.allocator();
    }

    pub fn release(pool: *ArenaPool, alloc: std.mem.Allocator) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        const arena: *Arena = @ptrCast(alloc.ptr);
        var walk = arena.nodes;
        var total_size: f64 = 0;
        while (walk) |node| {
            walk = node.node;
            total_size += @floatFromInt(node.end);
        }

        const old_block_size: f64 = @atomicLoad(f64, &pool.block_size, .unordered);
        const block_size: f64 = (1 - adapt_rate) * old_block_size + adapt_rate * 2 * total_size;
        @atomicStore(f64, &pool.block_size, block_size, .unordered);

        walk = arena.nodes;
        while (walk) |node| {
            walk = node.node;
            const lfc = @log2(total_size / block_size);
            if (pool.rng.random().float(f64) < @exp(-regularity * lfc * lfc)) {
                pushBuf(node);
            } else {
                const bytes = @as([*]u8, @ptrCast(node))[0 .. @sizeOf(Node) + node.data];
                pool.child_allocator.free(bytes);
            }
        }
    }

    fn popBuf(pool: *ArenaPool) ?*Node {
        var old = @atomicLoad(*Node, &pool.nodes, .acquire) orelse return null;
        while (true) {
            const new = old.node;
            old = @cmpxchgWeak(
                *Node,
                &pool.nodes,
                old,
                new,
                .acquire,
                .unordered,
            ) orelse return old;
        }
    }

    fn pushBuf(pool: *ArenaPool, node: *Node) void {
        var old = @atomicLoad(*Node, &pool.nodes, .release) orelse return null;
        while (true) {
            node.node = old;
            old = @cmpxchgWeak(
                *Node,
                &pool.nodes,
                old,
                node,
                .release,
                .unordered,
            ) orelse return;
        }
    }

    /// NOTE lock before use
    fn newNode(pool: *ArenaPool, min_size: usize, alignment: usize) !Node {
        const block_size = @max(
            min_size + alignment,
            @atomicLoad(usize, &pool.block_size, .unordered),
        );

        const bytes = try pool.child_allocator.alignedAlloc(
            u8,
            .of(Node),
            @sizeOf(Node) + block_size,
        );
        const node: *Node = @ptrCast(bytes.ptr);
        node.* = .{
            .data = block_size,
        };
        return node;
    }
};
