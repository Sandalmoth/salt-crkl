const std = @import("std");
const log = std.log.scoped(.slot_pool);

top: u32,
slots: []u32,

const SlotPool = @This();

fn init(gpa: std.mem.Allocator, capacity: u32) !SlotPool {
    const slots = try gpa.alloc(u32, capacity);
    for (0..capacity) |i| slots[i] = @intCast(i);
    return .{ .top = capacity, .slots = slots };
}

fn deinit(pool: *SlotPool, gpa: std.mem.Allocator) void {
    if (pool.top != @as(u32, @intCast(pool.slots.len))) log.debug(
        "not empty on deinit expected {} actual {}",
        .{ pool.slots.len, pool.top },
    );
    gpa.free(pool.slots);
    pool.* = undefined;
}

fn acquire(pool: *SlotPool) !u32 {
    if (pool.top == 0) return error.OutOfSlots;
    pool.top -= 1;
    return pool.slots[pool.top];
}

fn release(pool: *SlotPool, slot: u32) void {
    std.debug.assert(pool.top < @as(u32, @intCast(pool.slots.len)));
    pool.slots[pool.top] = slot;
    pool.top += 1;
}
