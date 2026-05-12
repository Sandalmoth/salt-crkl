const std = @import("std");

pub fn yo() void {
    std.debug.print("yo!\n", .{});
}

const Storage = struct {
    const Signal = struct {
        storage: *Storage,
        event: *std.Io.Event,

        /// must not be called again after it returns true
        pub fn wait(signal: Signal, timeout: std.Io.Duration) bool {
            _ = signal;
            _ = timeout;
            return true;
        }
    };

    const Event = union(enum) {
        created: u128,
        altered: u128,
        deleted: u128,
    };

    const Request = struct {
        uuid: u128,
        dst: []u8,
        event: *std.Io.Event,
    };

    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,

    mutex: std.Io.Mutex,
    queue: std.Deque(Request),
    event_pool: std.heap.MemoryPool(std.Io.Event),

    daemon_task: ?std.Io.Future(void),

    index: std.AutoHashMap(u128, union(enum) {
        page: struct {
            ix_page: usize,
            offset: usize,
        },
        file: void,
    }),
    pages: []std.Io.File,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Storage {
        return .{
            .gpa = gpa,
            .io = io,
            .dir = try .openDir(.cwd(), io, path, .{}),
            .daemon_task = null,
        };
    }

    pub fn deinit(storage: *Storage) void {
        if (storage.daemon_task) |*task| task.cancel(storage.io);
        storage.dir.close(storage.io);
    }

    pub fn load(storage: *Storage, uuid: u128, dst: []u8) !Signal {
        try storage.mutex.lock(storage.io);
        defer storage.mutex.unlock(storage.io);

        const event = try storage.event_pool.create();
        errdefer storage.event_pool.destroy(event);
        try storage.queue.pushBack(storage.gpa, .{
            .uuid = uuid,
            .dst = dst,
            .event = event,
        });
        return .{
            .storage = storage,
            .event = event,
        };
    }

    pub fn pollEvents(storage: *Storage) ?Event {
        _ = storage;
        return null;
    }

    /// start daemon, idempotent
    pub fn start(storage: *Storage) !void {
        if (storage.daemon_task != null) return;
        storage.daemon_task = try storage.io.concurrent(daemon, .{storage});
    }

    /// stop daemon, idempotent
    pub fn stop(storage: *Storage) void {
        if (storage.daemon_task) |*task| task.await(storage.io);
    }
};

fn daemon(storage: *Storage) void {
    _ = storage;
    std.debug.print("howdy\n", .{});
}

test "Storage" {
    var s: Storage = try .init(std.testing.allocator, std.testing.io, "data");
    try s.start();
    s.stop();
    defer s.deinit();
}
