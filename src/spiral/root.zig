const std = @import("std");

const Uuid = @import("Uuid.zig");

const log = std.log.scoped(.spiral);

const Error = error{
    Bucket,
    File,
    Preload,
};

pub const Storage = struct {
    const Future = struct {
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
    immediate_io: std.Io.Threaded = .init_single_threaded, // used to unify future interface
    dir: std.Io.Dir,

    event_pool: DeferredMemoryPool(std.Io.Event),

    index: std.AutoHashMapUnmanaged(Uuid, Location),
    buckets: []std.Io.File,
    preload: []const u8,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Storage {
        const dir: std.Io.Dir = try .openDir(.cwd(), io, path, .{});
        errdefer dir.close(io);

        var buffer: [1024]u8 = undefined;
        const index_file = try dir.openFile(io, "index", .{ .mode = .read_only });
        var index_reader = index_file.reader(io, &buffer);
        const asset_count = try index_reader.interface.takeInt(u32, .little);
        var index: std.AutoHashMapUnmanaged(Uuid, Location) = .empty;
        try index.ensureTotalCapacity(gpa, @intCast(asset_count));
        for (0..asset_count) |_| {
            const uuid: Uuid = .{ .bits = try index_reader.interface.takeInt(u128, .little) };
            const location: Location = try .deserialize(&index_reader.interface);
            std.debug.assert(!index.contains(uuid));
            index.putAssumeCapacity(uuid, location);
        }
        errdefer index.deinit(gpa);

        const preload = try dir.readFileAlloc(io, "preload", gpa, .limited(1024 * 1024 * 1024));
        errdefer gpa.free(preload);

        return .{
            .gpa = gpa,
            .io = io,
            .dir = dir,
            .event_pool = .empty,
            .index = index,
            .buckets = &.{},
            .preload = preload,
        };
    }

    pub fn deinit(storage: *Storage) void {
        // Q: should we wait for outstanding tasks or something?
        // i guess ideally we should request cancellation of every load
        // otherwise, could be a problem if we close the dir or deinit the event i think
        // but seems kinda annoying to track, and shouldn't really be a problem
        // and besides, i think it's also illegal to deinit an io without awaiting everything
        // so like, we're not adding an extra complication in this case
        storage.gpa.free(storage.preload);
        storage.index.deinit(storage.gpa);
        storage.dir.close(storage.io);
        storage.event_pool.deinit(storage.gpa);
    }

    pub fn load(storage: *Storage, allocator: std.mem.Allocator, uuid: Uuid) !Future {
        const location = storage.index.get(uuid) orelse return error.Invalid;
        const dst = try allocator.alloc(u8, location.size);
        errdefer allocator.free(dst);

        if (location.location == .preload) {
            // use single threaded io if preloaded,
            // i.e. just run right away since it's already in mem
            const io = storage.immediate_io.io();
            return .{
                .event = null,
                .future = io.async(loadImpl, .{ storage, location, dst, null }),
                .io = io,
            };
        } else {
            try storage.event_pool.sweep(storage.io); // noop if there are free events to use
            const event = try storage.event_pool.create(storage.gpa, storage.io);
            event.reset();
            errdefer DeferredMemoryPool(std.Io.Event).mark(event);

            const io = storage.io;
            return .{
                .event = event,
                .future = io.async(loadImpl, .{ storage, location, dst, event }),
                .io = io,
            };
        }

        unreachable;
    }

    pub fn poll(storage: *Storage) ?Event {
        _ = storage;
        return null;
    }

    fn loadImpl(storage: *Storage, src: Location, dst: []u8, event: ?*std.Io.Event) Error![]u8 {
        switch (src.location) {
            .bucket => {
                @panic("TODO");
            },
            .file => |file| {
                var content_hash_str: [32]u8 = undefined;
                _ = std.fmt.bufPrint(&content_hash_str, "{x}", .{file}) catch unreachable;
                _ = storage.dir.readFile(storage.io, &content_hash_str, dst) catch |e| {
                    log.err("failed to load from file {s} with error {}", .{ &content_hash_str, e });
                    return error.File;
                };
            },
            .preload => |preload| {
                @memcpy(dst, storage.preload[preload .. preload + src.size]);
            },
        }
        if (event != null) event.?.set(storage.io);

        return dst;
    }
};

test "Storage" {
    var s: Storage = try .init(std.testing.allocator, std.testing.io, "data");
    defer s.deinit();

    var a_future = try s.load(
        std.testing.allocator,
        try .parse("603HK0R1ZP89REPQDG25GGYSTW"),
    );
    var b_future = try s.load(
        std.testing.allocator,
        try .parse("1Y99Z3J6K45HR5S3WZKSVQ51E1"),
    );
    var c_future = try s.load(
        std.testing.allocator,
        try .parse("37BQJ0V3J4RA73SA8QBQH8VY1Z"),
    );

    const a = try a_future.await();
    defer std.testing.allocator.free(a);
    std.debug.print("{s}\n", .{a});

    const b = try b_future.await();
    defer std.testing.allocator.free(b);
    std.debug.print("{s}\n", .{b});

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
