const std = @import("std");

const AtomicTimer = struct {
    t0: std.time.Instant,
    prev: u64,

    pub fn start() !AtomicTimer {
        return .{
            .t0 = try std.time.Instant.now(),
            .prev = 0,
        };
    }

    pub fn read(atomic_timer: *AtomicTimer) u64 {
        const now = (std.time.Instant.now() catch unreachable).since(atomic_timer.t0);
        const prev = @atomicRmw(u64, &atomic_timer.prev, .Max, now, .monotonic);
        return @max(now, prev);
    }
};

const Timestamp = struct {
    name: [*:0]const u8,
    time: u64,
    thread_id: std.Thread.Id,
    scope_id: i64,
};

const Frame = struct {
    const Segment = struct {
        next: ?*Segment,
        cursor: usize,
        timestamps: [1024]Timestamp,
    };

    arena_struct: std.heap.ArenaAllocator,
    segment: *Segment,
    mutex: std.Thread.Mutex,

    fn reset(frame: *Frame) !void {
        _ = frame.arena_struct.reset(.retain_capacity);
        frame.segment = try frame.arena_struct.allocator().create(Segment);
        frame.segment.next = null;
        frame.segment.cursor = 0;
    }

    fn append(frame: *Frame, timestamp: Timestamp) !void {
        const segment = @atomicLoad(*Segment, &frame.segment, .acquire);
        const index = @atomicRmw(usize, &segment.cursor, .Add, 1, .monotonic);
        if (index < segment.timestamps.len) {
            segment.timestamps[index] = timestamp;
            return;
        }

        frame.mutex.lock();
        defer frame.mutex.unlock();

        // test if someone else already did the mutex part
        const maybe_new_segment = @atomicLoad(*Segment, &frame.segment, .acquire);
        if (segment != maybe_new_segment) {
            try frame.append(timestamp);
            return;
        }

        // we are first, add new segment
        const new_segment = try frame.arena_struct.allocator().create(Segment);
        new_segment.next = segment;
        new_segment.cursor = 1;
        new_segment.timestamps[0] = timestamp;
        @atomicStore(*Segment, &frame.segment, new_segment, .release);
    }
};

pub const Scope = struct {
    name: [:0]const u8,
    thread_id: std.Thread.Id,
    scope_id: i64,

    pub fn end(scope: Scope) void {
        frames[cursor].append(.{
            .name = scope.name.ptr,
            .thread_id = scope.thread_id,
            .time = timer.read(),
            .scope_id = -scope.scope_id,
        }) catch {};
    }
};

var timer: AtomicTimer = undefined;
var frames: []Frame = &.{};
var cursor: usize = 0;
var scope_id: i64 = 1;

pub fn init(gpa: std.mem.Allocator, n_frames: usize) !void {
    timer = try .start();
    frames = try gpa.alloc(Frame, n_frames);
    for (0..frames.len) |i| {
        frames[i].arena_struct = .init(gpa);
        try frames[i].reset();
    }
}

pub fn deinit(gpa: std.mem.Allocator) void {
    for (0..frames.len) |i| frames[i].arena_struct.deinit();
    gpa.free(frames);
}

pub fn begin(name: [:0]const u8) Scope {
    const scope: Scope = .{
        .name = name,
        .thread_id = std.Thread.getCurrentId(),
        .scope_id = @atomicRmw(i64, &scope_id, .Add, 1, .monotonic),
    };
    frames[cursor].append(.{
        .name = scope.name.ptr,
        .thread_id = scope.thread_id,
        .time = timer.read(),
        .scope_id = scope.scope_id,
    }) catch {};
    return scope;
}

test "basic functionality" {
    try init(std.testing.allocator, 100);
    defer deinit(std.testing.allocator);

    const a = begin("a");
    std.debug.print("{}\n", .{a});
    a.end();

    const b = begin("b");
    std.debug.print("{}\n", .{b});
    b.end();

    var walk: ?*Frame.Segment = frames[cursor].segment;
    while (walk) |segment| {
        var it = std.mem.reverseIterator(
            segment.timestamps[0..@min(segment.timestamps.len, segment.cursor)],
        );
        while (it.next()) |timestamp| std.debug.print("{}\n", .{timestamp});
        walk = segment.next;
    }
}
