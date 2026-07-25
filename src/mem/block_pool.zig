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
        slabs: ?*Slab,
        blocks: TaggedPointer align(16),
        is_expanding: bool,
        capacity: usize,

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{
                .gpa = gpa,
                .slabs = null,
                .blocks = .{ .ptr = 0, .tag = 0 },
                .is_expanding = false,
                .capacity = 0,
            };
        }

        pub fn deinit(pool: *Self) void {
            var walk: ?*Slab = pool.slabs;
            while (walk) |slab| {
                walk = slab.next;
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
            var old = @atomicLoad(?*Slab, &pool.slabs, .monotonic);
            while (true) {
                slab.next = old;
                old = @cmpxchgWeak(
                    ?*Slab,
                    &pool.slabs,
                    old,
                    slab,
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

test "basics" {
    const block_size = 1024;
    var ba_impl: BlockAllocator(.{ .block_size = block_size }) = .init(std.testing.allocator);
    defer ba_impl.deinit();
    const alloc = ba_impl.allocator();

    // alignment
    const b1 = try alloc.create([block_size]u8);
    const b2 = try alloc.create([block_size]u8);
    try std.testing.expect(std.mem.isAligned(@intFromPtr(b1), block_size));
    try std.testing.expect(std.mem.isAligned(@intFromPtr(b2), block_size));

    // stack behaviour
    alloc.destroy(b1);
    alloc.destroy(b2);
    const b2_v2 = try alloc.create([block_size]u8);
    const b1_v2 = try alloc.create([block_size]u8);
    try std.testing.expectEqual(b1, b1_v2);
    try std.testing.expectEqual(b2, b2_v2);

    // make sure the blocks don't overlap
    @memset(b1, 0x01);
    @memset(b2, 0x02);
    try std.testing.expectEqual(0x01, b1[0]);
    try std.testing.expectEqual(0x01, b1[block_size - 1]);
    try std.testing.expectEqual(0x02, b2[0]);
    try std.testing.expectEqual(0x02, b2[block_size - 1]);

    // expansion
    var bs: std.ArrayList(*[block_size]u8) = .empty;
    defer bs.deinit(std.testing.allocator);
    for (0..1000) |i| {
        const b = try alloc.create([block_size]u8);
        try std.testing.expect(std.mem.isAligned(@intFromPtr(b), block_size));
        @memset(b, @intCast(i % 255));
        try bs.append(std.testing.allocator, b);
    }
    try std.testing.expect(ba_impl.capacity >= 1000);

    // deletions
    alloc.destroy(b1_v2);
    alloc.destroy(b2_v2);
    for (bs.items) |p| {
        alloc.destroy(p);
    }
}

test "failing" {
    const block_size = 1024;
    var ba_impl: BlockAllocator(.{ .block_size = block_size }) = .init(std.testing.allocator);
    defer ba_impl.deinit();
    const alloc = ba_impl.allocator();

    const large = alloc.alloc(u8, block_size + 1);
    try std.testing.expectError(error.OutOfMemory, large);
    const bad_align = alloc.alignedAlloc(u8, .fromByteUnits(block_size * 2), 1);
    try std.testing.expectError(error.OutOfMemory, bad_align);
}

test "resize and remap" {
    const block_size = 1024;
    var ba_impl: BlockAllocator(.{ .block_size = block_size }) = .init(std.testing.allocator);
    defer ba_impl.deinit();
    const alloc = ba_impl.allocator();

    const mem = try alloc.alloc(u8, 100);
    defer alloc.free(mem);

    try std.testing.expect(alloc.resize(mem, 50));
    try std.testing.expect(alloc.resize(mem, block_size));
    try std.testing.expect(!alloc.resize(mem, block_size + 1));
    try std.testing.expect(alloc.remap(mem, block_size + 1) == null);
}
