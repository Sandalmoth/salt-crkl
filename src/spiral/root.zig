const std = @import("std");

const Uuid = @import("Uuid.zig");

const log = std.log.scoped(.spiral);

const Error = error{
    FileNotFound,
};

pub const Storage = struct {
    const Signal = struct {
        event: ?*std.Io.Event,
        future: std.Io.Future(Error![]u8),
        io: std.Io,

        pub fn poll(self: @This()) bool {
            if (self.event) |event| return event.isSet();
            return true;
        }
        pub fn await(self: *@This()) ![]u8 {
            const result = try self.future.await(self.io);
            if (self.event) |event| {
                DeferredMemoryPool(std.Io.Event).mark(event);
                self.event = null;
            }
            return result;
        }
    };

    const Event = union(enum) {
        created: Uuid,
        altered: Uuid,
        deleted: Uuid,
    };

    pub const Location = struct {
        size: u64, // size of the (decompressed) asset
        location: union(enum) {
            bucket: struct {
                index: u32,
                offset: u64,
                size: u64, // (maybe compressed) size in the bucket
                compressed: bool,
            },
            file: u128, // content hash, hex string is filename
            preload: u64, // offset in preload memory
        },

        const Flags = packed struct(u32) {
            compressed: bool = false,
            in_bucket: bool = false,
            in_file: bool = false,
            in_preload: bool = false,
            _pad: u28 = 0,
        };

        pub fn serialize(location: Location, writer: *std.Io.Writer) !void {
            var flags: Flags = .{};
            switch (location.location) {
                .bucket => |bucket| {
                    flags.in_bucket = true;
                    flags.compressed = bucket.compressed;
                },
                .file => |file| {
                    _ = file;
                    flags.in_file = true;
                },
                .preload => |preload| {
                    _ = preload;
                    flags.in_preload = true;
                },
            }
            std.debug.print("flags: {}\n", .{flags});
            try writer.writeInt(u32, @bitCast(flags), .little);
            try writer.writeInt(u64, location.size, .little);
            switch (location.location) {
                .bucket => |bucket| {
                    try writer.writeInt(u32, bucket.index, .little);
                    try writer.writeInt(u64, bucket.offset, .little);
                    try writer.writeInt(u64, bucket.size, .little);
                },
                .file => |file| {
                    try writer.writeInt(u128, file, .little);
                },
                .preload => |preload| {
                    try writer.writeInt(u64, preload, .little);
                },
            }
        }

        pub fn deserialize(reader: *std.Io.Reader) !Location {
            const flags: Flags = @bitCast(try reader.takeInt(u32, .little));
            std.debug.print("flags: {}\n", .{flags});
            var location: Location = undefined;
            location.size = try reader.takeInt(u64, .little);
            if (flags.in_bucket) {
                std.debug.assert(!flags.in_file);
                std.debug.assert(!flags.in_preload);
                location.location = .{ .bucket = .{
                    .index = try reader.takeInt(u32, .little),
                    .offset = try reader.takeInt(u64, .little),
                    .size = try reader.takeInt(u64, .little),
                    .compressed = flags.compressed,
                } };
            } else if (flags.in_file) {
                std.debug.assert(!flags.in_bucket);
                std.debug.assert(!flags.in_preload);
                location.location = .{ .file = try reader.takeInt(u128, .little) };
            } else if (flags.in_preload) {
                std.debug.assert(!flags.in_bucket);
                std.debug.assert(!flags.in_file);
                location.location = .{ .preload = try reader.takeInt(u64, .little) };
            } else return error.Invalid;
            return location;
        }
    };

    gpa: std.mem.Allocator,
    io: std.Io,
    immediate_io: std.Io.Threaded = .init_single_threaded, // used to unify signal interface
    dir: std.Io.Dir,

    event_pool: DeferredMemoryPool(std.Io.Event),
    buffer_memory: []u8,
    buffer_memory_memory: [][]u8, // god fucking damnit
    buffers: std.Io.Queue([]u8),

    index: std.AutoHashMapUnmanaged(Uuid, Location),
    buckets: []std.Io.File,
    preload: []const u8,

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
        const asset_count = try index_reader.interface.takeInt(u32, .little);
        std.debug.print("asset_count {}\n", .{asset_count});
        var index: std.AutoHashMapUnmanaged(Uuid, Location) = .empty;
        try index.ensureTotalCapacity(gpa, @intCast(asset_count));
        for (0..asset_count) |_| {
            const uuid: Uuid = .{ .bits = try index_reader.interface.takeInt(u128, .little) };
            const location: Location = try .deserialize(&index_reader.interface);
            std.debug.print("{s} {}\n", .{ &uuid.stringify(), location });
            std.debug.assert(!index.contains(uuid));
            index.putAssumeCapacity(uuid, location);
        }
        try buffers.putOne(io, buffer);

        var it = index.iterator();
        while (it.next()) |kv| std.debug.print("{}\n", .{kv});

        std.debug.print("{}\n", .{index});

        return .{
            .gpa = gpa,
            .io = io,
            .dir = dir,
            .event_pool = .empty,
            .buffer_memory = buffer_memory,
            .buffer_memory_memory = buffer_memory_memory,
            .buffers = buffers,
            .index = index,
            .buckets = &.{},
            .preload = try dir.readFileAlloc(io, "preload", gpa, .limited(1024 * 1024 * 1024)),
        };
    }

    pub fn deinit(storage: *Storage) void {
        // FIXME? shoudl we wait for outstanding tasks or something?
        storage.gpa.free(storage.preload);
        storage.index.deinit(storage.gpa);
        storage.gpa.free(storage.buffer_memory);
        storage.gpa.free(storage.buffer_memory_memory);
        storage.dir.close(storage.io);
        storage.event_pool.deinit(storage.gpa);
    }

    pub fn load(storage: *Storage, allocator: std.mem.Allocator, uuid: Uuid) !Signal {
        try storage.event_pool.sweep(storage.io); // noop if there are free events to use
        const event = try storage.event_pool.create(storage.gpa, storage.io);
        event.reset();
        errdefer DeferredMemoryPool(std.Io.Event).mark(event);

        const location = storage.index.get(uuid) orelse return error.FileNotFound;
        const dst = try allocator.alloc(u8, location.size);

        // use single threaded io if preloaded, i.e. just run right away since it's already in mem
        const io = if (location.location == .preload) storage.immediate_io.io() else storage.io;
        return .{
            .event = event,
            .future = io.async(loadImpl, .{ storage, location, dst, event }),
            .io = io,
        };
    }

    pub fn poll(storage: *Storage) ?Event {
        _ = storage;
        return null;
    }

    fn loadImpl(storage: *Storage, src: Location, dst: []u8, event: *std.Io.Event) Error![]u8 {
        switch (src.location) {
            .bucket => {
                @panic("TODO");
            },
            .file => |file| {
                var content_hash_str: [32]u8 = undefined;
                _ = std.fmt.bufPrint(&content_hash_str, "{x}", .{file}) catch unreachable;
                _ = storage.dir.readFile(storage.io, &content_hash_str, dst) catch
                    return error.FileNotFound;
            },
            .preload => |preload| {
                @memcpy(dst, storage.preload[preload .. preload + src.size]);
            },
        }
        event.set(storage.io);
        return dst;
    }
};

test "Storage" {
    var s: Storage = try .init(std.testing.allocator, std.testing.io, "data");
    defer s.deinit();

    std.debug.print("{}\n", .{s.index});
    var it = s.index.iterator();
    while (it.next()) |kv| std.debug.print("{}\n", .{kv});

    var a_future = try s.load(
        std.testing.allocator,
        try .parse("603HK0R1ZP89REPQDG25GGYSTW"),
    );
    const a = try a_future.await();
    defer std.testing.allocator.free(a);
    std.debug.print("{s}\n", .{a});

    var b_future = try s.load(
        std.testing.allocator,
        try .parse("1Y99Z3J6K45HR5S3WZKSVQ51E1"),
    );
    const b = try b_future.await();
    defer std.testing.allocator.free(b);
    std.debug.print("{s}\n", .{b});

    var c_future = try s.load(
        std.testing.allocator,
        try .parse("37BQJ0V3J4RA73SA8QBQH8VY1Z"),
    );
    const c = try c_future.await();
    defer std.testing.allocator.free(c);
    std.debug.print("{s}\n", .{c});
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
            try pool.mutex.lock(io);
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
                gpa.free(segment.nodes);
                gpa.destroy(segment);
            }
        }

        pub fn mark(value: *T) void {
            const node: *Node = @alignCast(@fieldParentPtr("value", value));
            node.flag = true;
        }

        pub fn sweep(pool: *Self, io: std.Io) !void {
            try pool.mutex.lock(io);
            defer pool.mutex.unlock(io);

            if (pool.free_list) |_| return; // only sweep if we actually are out of free slots

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
