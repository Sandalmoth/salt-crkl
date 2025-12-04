const std = @import("std");

const log = std.log.scoped(.profiler);

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
    scope_id: i64, // NOTE zero means it's a marker, >0 is open scaope, <0 is close scope
};

const Queue = struct {
    const segment_size = 1024;
    const Segment = struct {
        next: ?*Segment,
        head: u32,
        tail: u32,
        timestamps: [segment_size]Timestamp,
        indicators: [segment_size]bool,
    };

    pool: std.heap.MemoryPool(Segment),
    head: *Segment,
    tail: *Segment,
    pool_mutex: std.Thread.Mutex,
    push_mutex: std.Thread.Mutex,

    fn init(gpa: std.mem.Allocator) !Queue {
        var q: Queue = undefined;
        q.pool = .init(gpa);
        q.pool_mutex = .{};
        q.push_mutex = .{};

        const segment = try q.pool.create();
        segment.next = null;
        segment.head = 0;
        segment.tail = 0;
        segment.indicators = .{false} ** segment_size;
        q.head = segment;
        q.tail = segment;
        return q;
    }

    fn deinit(q: *Queue) void {
        q.pool.deinit();
        q.* = undefined;
    }

    fn push(q: *Queue, ts: Timestamp) !void {
        const segment = @atomicLoad(*Segment, &q.tail, .acquire);
        const index = @atomicRmw(u32, &segment.tail, .Add, 1, .monotonic);
        if (index < segment_size) {
            // there's room for the item in the segment
            segment.timestamps[index] = ts;
            @atomicStore(bool, &segment.indicators[index], true, .release);
            return;
        }

        q.push_mutex.lock();
        defer q.push_mutex.unlock();

        // test if someone else already did the mutex part
        const maybe_new_segment = @atomicLoad(*Segment, &q.tail, .acquire);
        if (segment != maybe_new_segment) {
            try q.push(ts);
            return;
        }

        // we are first, add new segment
        q.pool_mutex.lock();
        const new_segment = try q.pool.create();
        q.pool_mutex.unlock();
        segment.next = new_segment;
        new_segment.next = null;
        new_segment.head = 0;
        new_segment.indicators = .{false} ** segment_size;
        new_segment.timestamps[0] = ts;
        new_segment.indicators[0] = true;
        new_segment.tail = 1;
        @atomicStore(*Segment, &q.tail, new_segment, .release);
    }

    fn pop(q: *Queue) ?Timestamp {
        const segment = q.head;

        if (segment.head < segment_size) {
            // there are values left in the segment
            if (!@atomicLoad(bool, &segment.indicators[segment.head], .acquire)) return null;
            const ts = segment.timestamps[segment.head];
            segment.head += 1;
            return ts;
        }

        if (@atomicLoad(?*Segment, &segment.next, .acquire)) |next| {
            // tail has already moved on, safe to remove
            q.head = next;
            q.pool_mutex.lock();
            q.pool.destroy(segment);
            q.pool_mutex.unlock();
            return q.pop();
        }

        // no more values, but at the end of the segment so cannot proceed
        return null;
    }
};

var queue: Queue = undefined;

pub fn init(gpa: std.mem.Allocator) !void {
    queue = try .init(gpa);
}

pub fn deinit() void {
    queue.deinit();
}

test "scratch" {
    try init(std.testing.allocator);
    defer deinit();

    for (0..100_000) |_| try queue.push(undefined);
    for (0..100_000) |_| {
        const ts = queue.pop();
        try std.testing.expect(ts != null);
    }
    try std.testing.expectEqual(null, queue.pop());
}

// const Timestamp = struct {
//     name: [*:0]const u8,
//     time: u64,
//     thread_id: std.Thread.Id,
//     scope_id: i64,

//     fn lessThan(ctx: void, a: Timestamp, b: Timestamp) bool {
//         _ = ctx;
//         if (a.thread_id == b.thread_id) return a.time < b.time;
//         return a.thread_id < b.thread_id;
//     }
// };

// const Frame = struct {
//     const Segment = struct {
//         prev: ?*Segment,
//         next: ?*Segment,
//         cursor: usize,
//         timestamps: [1024]Timestamp, // geometric growth would probably be better
//     };

//     const Scope = struct {
//         start: u64,
//         end: u64,
//         depth: u32,
//         parent: u32,
//         name: []const u8,
//         id: i64,
//         thread_id: std.Thread.Id,
//     };

//     arena_struct: std.heap.ArenaAllocator,
//     segment: *Segment,
//     mutex: std.Thread.Mutex,

//     timestamps: std.ArrayList(Timestamp), // sorted with unpaired bedings/ends removed
//     scopes: std.ArrayList(Frame.Scope), // sorted by thread id

//     fn reset(frame: *Frame) !void {
//         _ = frame.arena_struct.reset(.retain_capacity);
//         frame.segment = try frame.arena_struct.allocator().create(Segment);
//         frame.segment.prev = null;
//         frame.segment.next = null;
//         frame.segment.cursor = 0;
//     }

//     fn append(frame: *Frame, timestamp: Timestamp) !void {
//         const segment = @atomicLoad(*Segment, &frame.segment, .acquire);
//         const index = @atomicRmw(usize, &segment.cursor, .Add, 1, .monotonic);
//         if (index < segment.timestamps.len) {
//             segment.timestamps[index] = timestamp;
//             return;
//         }

//         frame.mutex.lock();
//         defer frame.mutex.unlock();

//         // test if someone else already did the mutex part
//         const maybe_new_segment = @atomicLoad(*Segment, &frame.segment, .acquire);
//         if (segment != maybe_new_segment) {
//             try frame.append(timestamp);
//             return;
//         }

//         // we are first, add new segment
//         const new_segment = try frame.arena_struct.allocator().create(Segment);
//         segment.prev = new_segment;
//         new_segment.prev = null;
//         new_segment.next = segment;
//         new_segment.cursor = 1;
//         new_segment.timestamps[0] = timestamp;
//         @atomicStore(*Segment, &frame.segment, new_segment, .release);
//     }

//     fn finalize(frame: *Frame) !void {
//         var n_timestamps: usize = 0;
//         var walk: *Segment = frame.segment;
//         while (true) {
//             n_timestamps += @min(walk.timestamps.len, walk.cursor);
//             if (walk.next == null) break;
//             walk = walk.next.?;
//         }

//         const arena = frame.arena_struct.allocator();
//         frame.timestamps = try .initCapacity(arena, n_timestamps);
//         frame.scopes = try .initCapacity(arena, (n_timestamps + 1) / 2);
//         var stack: std.ArrayList(u32) = try .initCapacity(arena, (n_timestamps + 1) / 2);

//         while (true) {
//             for (walk.timestamps[0..@min(walk.timestamps.len, walk.cursor)]) |timestamp| {
//                 frame.timestamps.appendAssumeCapacity(timestamp);
//             }
//             if (walk.prev == null) break;
//             walk = walk.prev.?;
//         }
//         std.sort.block(Timestamp, frame.timestamps.items, {}, Timestamp.lessThan);
//         for (frame.timestamps.items) |timestamp| {
//             std.debug.print("{}\n", .{timestamp});
//         }

//         var thread_slice_begin: usize = 0;
//         while (thread_slice_begin < frame.timestamps.items.len) {
//             var thread_slice_end: usize = thread_slice_begin;
//             while (thread_slice_end < frame.timestamps.items.len and
//                 frame.timestamps.items[thread_slice_end].thread_id ==
//                     frame.timestamps.items[thread_slice_begin].thread_id) : (thread_slice_end += 1)
//             {}

//             for (frame.timestamps.items[thread_slice_begin..thread_slice_end]) |timestamp| {
//                 std.debug.print("---\n{}\n", .{timestamp});
//                 std.debug.print("{any}\n", .{frame.scopes.items});
//                 std.debug.print("{any}\n", .{stack.items});
//                 std.debug.assert(timestamp.scope_id != 0);
//                 if (timestamp.scope_id > 0) {
//                     const ix_scope: u32 = @intCast(stack.items.len);
//                     frame.scopes.appendAssumeCapacity(.{
//                         .depth = @intCast(stack.items.len),
//                         .start = timestamp.time,
//                         .end = undefined,
//                         .name = std.mem.span(timestamp.name),
//                         .parent = stack.getLastOrNull() orelse @intCast(frame.scopes.items.len),
//                         .id = timestamp.scope_id,
//                         .thread_id = timestamp.thread_id,
//                     });
//                     stack.appendAssumeCapacity(ix_scope);
//                 } else {
//                     const ix_scope = stack.getLastOrNull() orelse {
//                         log.debug("missing begin scope for timestamp {}", .{timestamp});
//                         std.debug.print("1\n", .{});
//                         continue;
//                     };
//                     const scope = &frame.scopes.items[ix_scope];
//                     if (-scope.id != timestamp.scope_id) {
//                         log.debug("timestamp stack structure is corrupt", .{});
//                         std.debug.print("2\n", .{});
//                         continue;
//                     }
//                     std.debug.assert(scope.thread_id == timestamp.thread_id);
//                     scope.end = timestamp.time;
//                     _ = stack.pop();
//                 }
//             }
//             var it = std.mem.reverseIterator(stack.items);
//             while (it.next()) |ix_scope| {
//                 log.debug("missing end scope for scope {}", .{frame.scopes.items[ix_scope]});
//                 // TODO erase the unclosed scopes but: are they guaranteed to be in order?
//                 // if not, then erasing becomes very tricky
//             }

//             thread_slice_begin = thread_slice_end;
//         }
//     }
// };

// pub const Scope = struct {
//     name: [:0]const u8,
//     thread_id: std.Thread.Id,
//     scope_id: i64,
//     start_time: u64,

//     pub fn end(scope: Scope) void {
//         frames[cursor].append(.{
//             .name = scope.name.ptr,
//             .thread_id = scope.thread_id,
//             .time = @max(scope.start_time + 1, timer.read()), // guarantee begin-end order
//             .scope_id = -scope.scope_id,
//         }) catch {};
//     }
// };

// var timer: AtomicTimer = undefined;
// var frames: []Frame = &.{};
// var cursor: usize = 0;
// var scope_id: i64 = 1;

// pub fn init(gpa: std.mem.Allocator, n_frames: usize) !void {
//     timer = try .start();
//     frames = try gpa.alloc(Frame, n_frames);
//     for (0..frames.len) |i| {
//         frames[i].arena_struct = .init(gpa);
//         try frames[i].reset();
//     }
// }

// pub fn deinit(gpa: std.mem.Allocator) void {
//     for (0..frames.len) |i| frames[i].arena_struct.deinit();
//     gpa.free(frames);
// }

// pub fn begin(name: [:0]const u8) Scope {
//     const scope: Scope = .{
//         .name = name,
//         .thread_id = std.Thread.getCurrentId(),
//         .scope_id = @atomicRmw(i64, &scope_id, .Add, 1, .monotonic),
//         .start_time = timer.read(),
//     };
//     frames[cursor].append(.{
//         .name = scope.name.ptr,
//         .thread_id = scope.thread_id,
//         .time = scope.start_time,
//         .scope_id = scope.scope_id,
//     }) catch {};
//     return scope;
// }

// test "basic functionality" {
//     try init(std.testing.allocator, 100);
//     defer deinit(std.testing.allocator);

//     const A = struct {
//         fn a() void {
//             for (0..2) |_| {
//                 std.Thread.sleep(100_000_000);
//                 const scope = begin("a");
//                 defer scope.end();
//                 b();
//             }
//         }

//         fn b() void {
//             for (0..2) |_| {
//                 std.Thread.sleep(10_000_000);
//                 const scope = begin("b");
//                 defer scope.end();
//             }
//         }
//     };

//     const t0 = try std.Thread.spawn(.{}, A.a, .{});
//     A.a();
//     t0.join();

//     try frames[cursor].finalize();
//     for (frames[cursor].timestamps.items) |timestamp| {
//         std.debug.print("{}\n", .{timestamp});
//     }
//     for (frames[cursor].scopes.items) |scope| {
//         std.debug.print("{}\n", .{scope});
//     }

//     // var walk: ?*Frame.Segment = frames[cursor].segment;
//     // while (walk) |segment| {
//     //     var it = std.mem.reverseIterator(
//     //         segment.timestamps[0..@min(segment.timestamps.len, segment.cursor)],
//     //     );
//     //     while (it.next()) |timestamp| std.debug.print("{}\n", .{timestamp});
//     //     walk = segment.next;
//     // }
// }
