const std = @import("std");

const min_slab = 16;

pub const Config = struct {
    block_size: usize,
};

const TaggedPointer = packed struct {
    const Self = @This();

    ptr: usize,
    tag: usize,
};

/// lock-free, block alignment is equal to the size
pub fn BlockAllocator(comptime config: Config) type {
    return struct {
        const block_size = config.block_size;

        const Self = @This();

        const Slab = struct {
            next: ?*Slab,
            bytes: []u8,
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
        slabs: TaggedPointer align(16),
        blocks: TaggedPointer align(16),
        is_expanding: bool,
        capacity: usize,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{
                .gpa = gpa,
                .slabs = .{ .ptr = 0, .tag = 0 },
                .blocks = .{ .ptr = 0, .tag = 0 },
                .is_expanding = false,
                .capacity = 0,
            };
        }

        pub fn deinit(pool: *Self) void {
            var walk: ?*Slab = @ptrFromInt(pool.slabs.ptr);
            while (walk) |slab| {
                walk = slab.next;
                std.debug.print("{*} {}\n", .{ slab.bytes.ptr, slab.bytes.len });
                pool.gpa.free(slab.bytes);
            }
        }

        fn pushBlock(pool: *Self, block: *Block) void {
            var old = @atomicLoad(TaggedPointer, &pool.blocks, .monotonic);
            while (true) {
                block.next = @ptrFromInt(old.ptr);
                const new: TaggedPointer = .{ .ptr = @intFromPtr(block), .tag = old.tag + 1 };
                old = @cmpxchgWeak(
                    TaggedPointer,
                    &pool.blocks,
                    old,
                    new,
                    .release,
                    .monotonic,
                ) orelse break;
            }
        }

        fn pushSlab(pool: *Self, slab: *Slab) void {
            std.debug.print("{*} {}\n", .{ slab.bytes.ptr, slab.bytes.len });
            var old = @atomicLoad(TaggedPointer, &pool.slabs, .monotonic);
            while (true) {
                slab.next = @ptrFromInt(old.ptr);
                const new: TaggedPointer = .{ .ptr = @intFromPtr(slab), .tag = old.tag + 1 };
                old = @cmpxchgWeak(
                    TaggedPointer,
                    &pool.slabs,
                    old,
                    new,
                    .release,
                    .monotonic,
                ) orelse break;
            }
        }

        fn popBlock(pool: *Self) ?*Block {
            var old = @atomicLoad(TaggedPointer, &pool.blocks, .acquire);
            while (old.ptr != 0) {
                const block: *Block = @ptrFromInt(old.ptr);
                const new: TaggedPointer = .{ .ptr = @intFromPtr(block.next), .tag = old.tag + 1 };
                old = @cmpxchgWeak(
                    TaggedPointer,
                    &pool.blocks,
                    old,
                    new,
                    .acquire,
                    .acquire,
                ) orelse return block;
            }
            return null;
        }

        pub fn allocator(pool: *Self) std.mem.Allocator {
            return .{
                .ptr = pool,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(
            ctx: *anyopaque,
            len: usize,
            alignment: std.mem.Alignment,
            ret_addr: usize,
        ) ?[*]u8 {
            if (len > block_size) return null;
            if (alignment.toByteUnits() > block_size) return null;

            const pool: *Self = @ptrCast(@alignCast(ctx));
            if (pool.popBlock()) |block| return @ptrCast(block);

            const ticket = @cmpxchgStrong(
                bool,
                &pool.is_expanding,
                false,
                true,
                .monotonic,
                .monotonic,
            ) == null;
            var slab_size: usize = min_slab;
            if (ticket) {
                // we have the right to do a big expansion
                slab_size = @atomicLoad(usize, &pool.capacity, .monotonic);
                slab_size = @max(min_slab, (slab_size *| 9) >> 5);
            }
            const bytes = pool.gpa.alloc(u8, (slab_size + 1) * block_size) catch return null;
            _ = @atomicRmw(usize, &pool.capacity, .Add, slab_size, .monotonic);
            var addr: usize = @intFromPtr(bytes.ptr);
            addr = std.mem.alignForward(usize, addr, block_size);
            for (0..slab_size) |_| {
                pool.pushBlock(@ptrFromInt(addr));
                addr += block_size;
            }
            std.debug.assert(addr < @intFromPtr(bytes.ptr) + bytes.len);

            var slab_addr = addr;
            if (addr + @sizeOf(Slab) > @intFromPtr(bytes.ptr) + bytes.len) {
                slab_addr = @intFromPtr(bytes.ptr);
            }
            const slab: *Slab = @ptrFromInt(slab_addr);
            slab.* = .{
                .bytes = bytes,
                .next = undefined,
            };
            pool.pushSlab(slab);

            if (ticket) @atomicStore(bool, &pool.is_expanding, false, .monotonic);

            return @call(.always_tail, alloc, .{ ctx, len, alignment, ret_addr });
        }

        fn resize(
            ctx: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            ret_addr: usize,
        ) bool {
            _ = ctx;
            _ = memory;
            _ = alignment;
            _ = ret_addr;
            return new_len <= block_size;
        }

        fn remap(
            ctx: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            new_len: usize,
            ret_addr: usize,
        ) ?[*]u8 {
            _ = ctx;
            _ = alignment;
            _ = ret_addr;
            if (new_len <= block_size) return memory.ptr;
            return null;
        }

        fn free(
            ctx: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            ret_addr: usize,
        ) void {
            _ = alignment;
            _ = ret_addr;
            std.debug.assert(memory.len <= block_size);
            std.debug.assert(std.mem.isAligned(@intFromPtr(memory.ptr), block_size));
            const pool: *Self = @ptrCast(@alignCast(ctx));
            pool.pushBlock(@ptrCast(@alignCast(memory.ptr)));
        }
    };
}

test "allocator" {
    var ba_impl: BlockAllocator(.{ .block_size = 1024 }) = .init(std.testing.allocator);
    defer ba_impl.deinit();
    const ba = ba_impl.allocator();

    const a = try ba.alloc(u32, 123);
    defer ba.free(a);
}
