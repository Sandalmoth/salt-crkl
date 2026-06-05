const std = @import("std");

const log = std.log.scoped(.profiler);

const Timestamp = struct {
    name: [*:0]const u8,
    time: std.Io.Timestamp,
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
    pool_mutex: std.Io.Mutex,
    push_mutex: std.Io.Mutex,

    fn init() !Queue {
        var q: Queue = undefined;
        q.pool = .empty;
        q.pool_mutex = .init;
        q.push_mutex = .init;

        const segment = try q.pool.create(gpa);
        segment.next = null;
        segment.head = 0;
        segment.tail = 0;
        segment.indicators = .{false} ** segment_size;
        q.head = segment;
        q.tail = segment;
        return q;
    }

    fn deinit(q: *Queue) void {
        q.pool.deinit(gpa);
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

        q.push_mutex.lockUncancelable(io);
        defer q.push_mutex.unlock(io);

        // test if someone else already did the mutex part
        const maybe_new_segment = @atomicLoad(*Segment, &q.tail, .acquire);
        if (segment != maybe_new_segment) {
            try q.push(ts);
            return;
        }

        // we are first, add new segment
        q.pool_mutex.lockUncancelable(io);
        const new_segment = try q.pool.create(gpa);
        q.pool_mutex.unlock(io);
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
            q.pool_mutex.lockUncancelable(io);
            q.pool.destroy(segment);
            q.pool_mutex.unlock(io);
            return q.pop();
        }

        // no more values, but at the end of the segment so cannot proceed
        return null;
    }
};

pub const Handle = struct {
    name: [:0]const u8,
    thread_id: std.Thread.Id,
    scope_id: i64,
    start_time: std.Io.Timestamp,
    failed_begin: bool,

    pub fn end(handle: Handle) void {
        if (handle.failed_begin) return;
        queue.push(.{
            .name = handle.name.ptr,
            .thread_id = handle.thread_id,
            .time = .now(io, .awake),
            .scope_id = -handle.scope_id,
        }) catch {};
    }
};

pub const Scope = struct {
    name: []const u8,
    start: std.Io.Timestamp,
    end: std.Io.Timestamp,
    depth: u32,
    parent: ?*Scope,
    id: i64,
};

pub const Stats = struct {
    const Data = struct {
        mean: f32 = std.math.nan(f32),
        std: f32 = 0.0,
        min: f32 = std.math.inf(f32),
        max: f32 = -std.math.inf(f32),
        total: f32 = 0.0,
        count: f32 = 0.0,
    };

    data: std.MultiArrayList(Data) = .empty,
    cursor: usize = 0,
    last_used: usize = 0,

    fn init() !Stats {
        var s: Stats = .{};
        try s.data.ensureTotalCapacity(gpa, history);
        for (0..history) |_| s.data.appendAssumeCapacity(.{});
        return s;
    }

    fn deinit(s: *Stats) void {
        s.data.deinit(gpa);
        s.* = undefined;
    }
};

var gpa: std.mem.Allocator = undefined;
var io: std.Io = undefined;
var history: usize = undefined;

var queue: Queue = undefined;
var scope_id: i64 = 1; // used to generate a unique id, incremented on every begin

var scope_pool: std.heap.MemoryPool(Scope) = .empty;
var stacks: std.AutoHashMapUnmanaged(std.Thread.Id, std.ArrayList(*Scope)) = .empty;
pub var timelines: std.AutoHashMapUnmanaged(std.Thread.Id, std.ArrayList(*Scope)) = .empty;
pub var stats: std.StringHashMapUnmanaged(Stats) = .empty;

// so stats is a bit tricky to store?
// for each name (used for begin/end) we want to
// store the past N stats, preferably in one contiguous array per stat
// but if some name hasn't been used in the last N frames, i guess we should remove it

pub fn init(_gpa: std.mem.Allocator, _io: std.Io, _history: usize) !void {
    gpa = _gpa;
    io = _io;
    history = _history;
    queue = try .init();
}

pub fn deinit() void {
    queue.deinit();
    scope_pool.deinit(gpa);

    var it_timelines = timelines.iterator();
    while (it_timelines.next()) |kv| kv.value_ptr.deinit(gpa);
    timelines.deinit(gpa);

    var it_stacks = stacks.iterator();
    while (it_stacks.next()) |kv| kv.value_ptr.deinit(gpa);
    stacks.deinit(gpa);

    var it_stats = stats.iterator();
    while (it_stats.next()) |kv| kv.value_ptr.deinit();
    stats.deinit(gpa);
}

pub fn begin(name: [:0]const u8) Handle {
    var handle: Handle = .{
        .name = name,
        .thread_id = std.Thread.getCurrentId(),
        .scope_id = @atomicRmw(i64, &scope_id, .Add, 1, .monotonic),
        .start_time = .now(io, .awake),
        .failed_begin = false,
    };
    queue.push(.{
        .name = handle.name.ptr,
        .thread_id = handle.thread_id,
        .time = handle.start_time,
        .scope_id = handle.scope_id,
    }) catch {
        handle.failed_begin = true;
        log.debug("allocation failure in begin, timestamp discarded", .{});
    };
    return handle;
}

pub fn mark(name: [:0]const u8) void {
    queue.push(.{
        .name = name.ptr,
        .thread_id = std.Thread.getCurrentId(),
        .time = .now(io, .awake),
        .scope_id = 0,
    }) catch {
        log.debug("allocation failure in mark, timestamp discarded", .{});
    };
}

pub fn beginFrame() !void {
    // this function allocates quite a lot with the timelines especially
    // should be no big deal but could be improved

    // delete all the old scopes
    var it_timelines = timelines.iterator();
    while (it_timelines.next()) |kv| {
        for (kv.value_ptr.items) |scope| scope_pool.destroy(scope);
        kv.value_ptr.deinit(gpa);
    }
    timelines.clearRetainingCapacity();

    // parse the timestamp stream into a hierarchy of timed scopes and marks
    while (queue.pop()) |ts| {
        const stack = blk: {
            const result = try stacks.getOrPut(gpa, ts.thread_id);
            if (!result.found_existing) result.value_ptr.* = .empty;
            break :blk result.value_ptr;
        };
        const timeline = blk: {
            const result = try timelines.getOrPut(gpa, ts.thread_id);
            if (!result.found_existing) result.value_ptr.* = .empty;
            break :blk result.value_ptr;
        };

        if (ts.scope_id == 0) {
            // just append the marker to the timeline
            const scope = try scope_pool.create(gpa);
            scope.* = .{
                .name = std.mem.span(ts.name),
                .start = ts.time,
                .end = ts.time,
                .depth = @intCast(stack.items.len),
                .parent = null,
                .id = ts.scope_id,
            };
            try timeline.append(gpa, scope);
            continue;
        }

        const top = stack.getLastOrNull();
        if (top == null or top.?.id != -ts.scope_id) {
            // open new scope
            if (top != null) std.debug.assert(top.?.id > 0);
            const scope = try scope_pool.create(gpa);
            scope.* = .{
                .name = std.mem.span(ts.name),
                .start = ts.time,
                .end = undefined,
                .depth = @intCast(stack.items.len),
                .parent = top,
                .id = ts.scope_id,
            };
            try stack.append(gpa, scope);
        } else {
            // close scope
            std.debug.assert(top.?.id > 0);
            std.debug.assert(ts.scope_id < 0);
            top.?.end = ts.time;
            _ = stack.pop();
            try timeline.append(gpa, top.?);
        }
    }

    // for each scope, compute stats
    var it_stats = stats.iterator();
    while (it_stats.next()) |kv| {
        kv.value_ptr.cursor = (kv.value_ptr.cursor + 1) % history;
        kv.value_ptr.last_used += 1;
        kv.value_ptr.data.set(kv.value_ptr.cursor, .{});
    }

    it_timelines = timelines.iterator();
    while (it_timelines.next()) |kv| {
        for (kv.value_ptr.items) |scope| {
            if (scope.id == 0) continue; // duration stats don't make sense for markers
            var stat = blk: {
                const result = try stats.getOrPut(gpa, scope.name);
                if (!result.found_existing) result.value_ptr.* = try .init();
                break :blk result.value_ptr;
            };
            const data = stat.data.slice();
            var dt: f32 = @floatFromInt(scope.start.durationTo(scope.end).toNanoseconds());
            dt *= 1e-6; // convert to ms
            data.items(.count)[stat.cursor] += 1.0;
            data.items(.total)[stat.cursor] += dt;
            data.items(.std)[stat.cursor] += dt * dt;
            data.items(.max)[stat.cursor] = @max(data.items(.max)[stat.cursor], dt);
            data.items(.min)[stat.cursor] = @min(data.items(.min)[stat.cursor], dt);
        }
    }

    it_stats = stats.iterator();
    while (it_stats.next()) |kv| {
        const cursor = kv.value_ptr.cursor;
        const data = kv.value_ptr.data.slice();
        const mean = data.items(.total)[cursor] / data.items(.count)[cursor];
        data.items(.mean)[cursor] = mean;
        data.items(.std)[cursor] = @sqrt(
            @max(data.items(.std)[cursor] / data.items(.count)[cursor] - mean * mean, 0.0),
        );
    }
}

// test "scratch" {
//     try init(std.testing.allocator, std.testing.io, 10);
//     defer deinit();

//     const A = struct {
//         fn a() !void {
//             for (0..2) |_| {
//                 const scope = begin("a");
//                 defer scope.end();
//                 try std.testing.io.sleep(.fromMilliseconds(100), .awake);
//                 try b();
//             }
//         }

//         fn b() !void {
//             for (0..2) |_| {
//                 const scope = begin("b");
//                 defer scope.end();
//                 try std.testing.io.sleep(.fromMilliseconds(100), .awake);
//             }
//         }
//     };

//     const t0 = try std.Thread.spawn(.{}, A.a, .{});
//     try A.a();
//     t0.join();

//     const z = begin("z");
//     try beginFrame();
//     z.end();
//     const t1 = try std.Thread.spawn(.{}, A.a, .{});
//     t1.join();

//     try beginFrame();
//     try beginFrame();

//     var it = timelines.iterator();
//     while (it.next()) |kv| {
//         std.debug.print("--- {} ---\n", .{kv.key_ptr.*});
//         for (kv.value_ptr.items) |scope| std.debug.print("{}\n", .{scope});
//     }

//     var it2 = stats.iterator();
//     while (it2.next()) |kv| {
//         std.debug.print("--- {s} ---\n", .{kv.key_ptr.*});
//         std.debug.print("mean {any}\n", .{kv.value_ptr.data.items(.mean)});
//         std.debug.print("std {any}\n", .{kv.value_ptr.data.items(.std)});
//         std.debug.print("min {any}\n", .{kv.value_ptr.data.items(.min)});
//         std.debug.print("max {any}\n", .{kv.value_ptr.data.items(.max)});
//         std.debug.print("total {any}\n", .{kv.value_ptr.data.items(.total)});
//         std.debug.print("count {any}\n", .{kv.value_ptr.data.items(.count)});
//     }
// }
