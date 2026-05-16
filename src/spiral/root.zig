const std = @import("std");

const Storage = struct {
    const Signal = struct {
        event: ?*std.Io.Event,
        future: std.Io.Future(void),

        pub fn poll(self: @This()) bool {
            if (self.event) |event| return event.isSet();
            return true;
        }
        pub fn await(self: @This(), io: std.Io) void {
            if (self.event) |event| {
                self.future.await(io);
                DeferredMemoryPool(std.Io.Event).mark(event);
                self.event = null;
            }
        }
    };

    const Event = union(enum) {
        created: u128,
        altered: u128,
        deleted: u128,
    };

    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,

    event_pool: DeferredMemoryPool(std.Io.Event),
    buffer_memory: []u8,
    buffer_memory_memory: [][]u8, // god fucking damnit
    buffers: std.Io.Queue([]u8),

    index: std.AutoHashMap(u128, union(enum) {
        page: struct {
            ix_page: usize,
            offset: usize,
        },
        file: void,
    }),
    buckets: []std.Io.File,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Storage {
        const dir: std.Io.Dir = try .openDir(.cwd(), io, path, .{});
        errdefer dir.close(io);

        // memory buffers for readers to use. just pop it off the queue and return it after
        const buffer_memory = try gpa.alloc(u8, 32 * 64 * 1024);
        const buffer_memory_memory = try gpa.alloc([]u8, 32);
        errdefer gpa.free(buffer_memory);
        var buffers: std.Io.Queue([]u8) = .init(buffer_memory_memory);
        for (0..32) |i| {
            try buffers.putOne(io, buffer_memory[i * 32 * 1024 .. (i + 1) * 32 * 1024]);
        }

        const buffer = try buffers.getOne(io);
        const index_file = try dir.openFile(io, "index", .{ .mode = .read_only });
        var index_reader = index_file.reader(io, buffer);
        const bucket_count = try index_reader.interface.takeInt(u32, .little);
        std.debug.print("bucket_count {}\n", .{bucket_count});
        // const index_bytes = try dir.readFileAlloc(io, "index", gpa, .limited(32 * 1024 * 1024));
        try buffers.putOne(io, buffer);

        return .{
            .gpa = gpa,
            .io = io,
            .dir = dir,
            .event_pool = .empty,
            .buffer_memory = buffer_memory,
            .buffer_memory_memory = buffer_memory_memory,
            .buffers = buffers,
            .index = undefined,
            .buckets = &.{},
        };
    }

    pub fn deinit(storage: *Storage) void {
        // FIXME? shoudl we wait for outstanding tasks or something?
        storage.gpa.free(storage.buffer_memory);
        storage.gpa.free(storage.buffer_memory_memory);
        storage.dir.close(storage.io);
    }

    pub fn load(storage: *Storage, uuid: u128, dst: []u8) !Signal {
        storage.event_pool.sweep(storage.io); // a little wasteful to run this every time, but whatever
        const event = try storage.event_pool.create();
        errdefer storage.event_pool.destroy(event);
        return .{
            .event = event,
            .future = storage.io.async(loadImpl, .{ storage, uuid, dst, event }),
        };
    }

    pub fn pollEvents(storage: *Storage) ?Event {
        _ = storage;
        return null;
    }

    fn loadImpl(storage: *Storage, uuid: 128, dst: []u8, event: *std.Io.Event) void {
        _ = storage;
        _ = uuid;
        _ = dst;
        _ = event;
    }
};

test "Storage" {
    var s: Storage = try .init(std.testing.allocator, std.testing.io, "data");
    s.deinit(); // kinda silly to need try, but, i guess we can always fail to wait?
}

pub fn DeferredMemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            flag: bool,
            value: T,
            next: ?*Node,
        };

        const Segment = struct {
            nodes: []Node,
            next: ?*Segment,
        };

        mutex: std.Io.Mutex,
        segments: ?*Segment,
        free_list: ?*Node,

        const empty = Self{ .mutex = .init, .segments = null, .free_list = null };

        pub fn create(pool: *Self, gpa: std.mem.Allocator, io: std.Io) !*T {
            pool.mutex.lock(io);
            defer pool.mutex.unlock(io);

            if (pool.free_list) |node| {
                std.debug.assert(!node.flag);
                pool.free_list = node.next;
                return &node.value;
            }

            const new_segment_size =
                if (pool.segments) |segment| 2 * segment.nodes.len else 64 / @sizeOf(Node);
            const segment = try gpa.create(Segment);
            errdefer gpa.destroy(segment);
            const nodes = try gpa.alloc(Node, new_segment_size);
            errdefer gpa.free(nodes);
            segment.* = .{
                .next = pool.segments,
                .nodes = nodes,
            };
            pool.segments = segment;
            for (nodes) |*node| {
                node.* = .{
                    .flag = false,
                    .value = undefined,
                    .next = pool.free_list,
                };
                pool.free_list = node;
            }

            if (pool.free_list) |node| {
                std.debug.assert(!node.flag);
                pool.free_list = node.next;
                return &node.value;
            } else {
                unreachable;
            }
        }

        pub fn deinit(pool: *Self, gpa: std.mem.Allocator) void {
            var walk: ?*Segment = pool.segments;
            while (walk) |segment| {
                walk = segment.next;
                gpa.free(segment.nodex);
                gpa.destroy(segment);
            }
        }

        pub fn mark(value: *T) void {
            const node: *Node = @fieldParentPtr("value", value);
            node.flag = true;
        }

        pub fn sweep(pool: *Self, io: std.Io) void {
            pool.mutex.lock(io);
            defer pool.mutex.unlock(io);

            var walk: ?*Segment = pool.segments;
            while (walk) |segment| {
                walk = segment.next;
                for (segment.nodes) |*node| {
                    if (!node.flag) continue;
                    node.* = .{
                        .flag = false,
                        .value = undefined,
                        .next = pool.free_list,
                    };
                    pool.free_list = node;
                }
            }
        }
    };
}
