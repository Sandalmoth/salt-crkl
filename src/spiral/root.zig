const std = @import("std");

const Uuid = @import("Uuid.zig");

const log = std.log.scoped(.spiral);

pub const Error = error{
    Content,
    OutOfMemory,
    Closed,
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

const Remote = struct {
    event: std.Io.Event,
    result: Error![]u8,
};

pub fn Future(comptime T: type) type {
    return struct {
        remote: ?*Remote,
        storage: *Storage,
        result: Error![]u8,

        pub fn poll(self: @This()) bool {
            if (self.remote) |remote| return remote.event.isSet();
            return true;
        }

        pub fn await(self: *@This()) !T {
            if (self.remote) |remote| {
                try remote.event.wait(self.storage.io);
                self.result = remote.result;

                try self.storage.mutex.lock(self.storage.io);
                self.storage.events.destroy(remote);
                self.storage.mutex.unlock(self.storage.io);
                self.remote = null;
            }

            const info = @typeInfo(T);
            const result = try self.result;
            if (info == .void) return;
            std.debug.assert(info == .pointer);
            if (info.pointer.size == .one)
                return std.mem.bytesAsValue(info.pointer.child, result);
            if (info.pointer.size == .slice)
                return std.mem.bytesAsSlice(info.pointer.child, result);
            unreachable;
        }

        pub fn cancel(self: *@This()) !T {
            return self.await(); // TODO request cancellation by setting a flag in the remote?
        }
    };
}

pub const StorageConfig = struct {
    capacity: u32 = 1024,
    worker_count: u32 = 4,
};

pub const Storage = struct {
    const LoadRequest = struct {
        remote: *Remote,
        location: Location,
        gpa: std.mem.Allocator,
    };

    gpa: std.mem.Allocator,
    io: std.Io,

    mutex: std.Io.Mutex = .init,

    dir: std.Io.Dir,
    index: std.AutoHashMapUnmanaged(Uuid, Location),
    buckets: []std.Io.File,
    preload: []const u8,

    events: MemoryPool(Remote),

    workers: std.Io.Group = .init,
    queue_buffer: []LoadRequest,
    queue: std.Io.Queue(LoadRequest),

    pub fn init(
        gpa: std.mem.Allocator,
        io: std.Io,
        path: []const u8,
        config: StorageConfig,
    ) !*Storage {
        const storage = try gpa.create(Storage);
        errdefer gpa.destroy(storage);

        const dir: std.Io.Dir = try .openDir(.cwd(), io, path, .{});
        errdefer dir.close(io);

        const queue_buffer = try gpa.alloc(LoadRequest, config.capacity);
        errdefer gpa.free(queue_buffer);

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

        var events: MemoryPool(Remote) = .init(gpa);
        errdefer events.deinit();

        storage.* = .{
            .gpa = gpa,
            .io = io,
            .dir = dir,
            .index = index,
            .buckets = &.{},
            .preload = preload,
            .events = events,
            .queue_buffer = queue_buffer,
            .queue = .init(queue_buffer),
        };

        for (0..config.worker_count) |_| {
            try storage.workers.concurrent(io, worker, .{storage});
            errdefer storage.workers.cancel(io);
        }

        return storage;
    }

    pub fn deinit(storage: *Storage) void {
        storage.workers.cancel(storage.io);

        storage.gpa.free(storage.queue_buffer);
        storage.events.deinit();
        storage.gpa.free(storage.preload);
        storage.index.deinit(storage.gpa);
        storage.dir.close(storage.io);

        storage.gpa.destroy(storage);
    }

    pub fn loadMany(
        storage: *Storage,
        comptime T: type,
        gpa: std.mem.Allocator,
        uuid: Uuid,
    ) !Future([]T) {
        const src = storage.index.get(uuid) orelse {
            log.err("uuid {s} is not in index", .{&uuid.stringify()});
            return error.Uuid;
        };

        if (src.location == .preload) {
            @panic("TODO");
            // const dst = try gpa.alloc(T, @divExact(src.size, @sizeOf(T)));
            // @memcpy(dst, storage.preload[src.location.preload .. src.location.preload + src.size]);
            // return .{ .remote = null, .storage = storage };
        } else {
            const remote = try storage.events.create();
            errdefer storage.events.destroy(remote);
            remote.event.reset();
            try storage.queue.putOne(storage.io, .{
                .remote = remote,
                .location = src,
                .gpa = gpa,
            });
            return .{ .remote = remote, .storage = storage, .result = undefined };
        }
    }

    // pub fn alloc(storage: *Storage, comptime T: type, gpa: std.mem.Allocator, uuid: Uuid) ![]T {
    //     try storage.mutex.lock(storage.io);
    //     defer storage.mutex.unlock(storage.io);

    //     const src = storage.index.get(uuid) orelse {
    //         log.err("uuid {s} is not in index", .{&uuid.stringify()});
    //         return error.Invalid;
    //     };
    //     return try gpa.alloc(T, @divExact(src.size, @sizeOf(T)));
    // }

    // pub fn create(storage: *Storage, comptime T: type, gpa: std.mem.Allocator, uuid: Uuid) !*T {
    //     try storage.mutex.lock(storage.io);
    //     defer storage.mutex.unlock(storage.io);

    //     const src = storage.index.get(uuid) orelse {
    //         log.err("uuid {s} is not in index", .{&uuid.stringify()});
    //         return error.Invalid;
    //     };
    //     std.debug.assert(@sizeOf(T) == src.size);
    //     return try gpa.create(T);
    // }

    // pub fn load(
    //     storage: *Storage,
    //     uuid: Uuid,
    //     dst: []u8,
    // ) !Future {
    //     try storage.mutex.lock(storage.io);
    //     defer storage.mutex.unlock(storage.io);

    //     const src = storage.index.get(uuid) orelse {
    //         log.err("uuid {s} is not in index", .{&uuid.stringify()});
    //         return error.Invalid;
    //     };
    //     std.debug.assert(src.size == dst.len);

    //     if (src.location == .preload) {
    //         @memcpy(dst, storage.preload[src.location.preload .. src.location.preload + src.size]);
    //         return .{ .remote = null, .storage = storage };
    //     } else {
    //         const remote = try storage.events.create();
    //         errdefer storage.events.destroy(remote);
    //         remote.event.reset();
    //         remote.result = {};
    //         try storage.queue.putOne(storage.io, .{
    //             .location = src,
    //             .dst = dst,
    //             .remote = remote,
    //         });
    //         return .{ .remote = remote, .storage = storage };
    //     }

    //     unreachable;
    // }

    fn worker(storage: *Storage) !void {
        while (true) {
            const req = storage.queue.getOne(storage.io) catch return error.Canceled;
            std.debug.assert(req.location.location != .preload);

            if (req.location.location == .file) {
                // const file = req.location.location.file;
                var content_hash_str: [32]u8 = undefined;
                _ = std.fmt.bufPrint(
                    &content_hash_str,
                    "{x}",
                    .{req.location.location.file},
                ) catch unreachable;
                const dst = storage.dir.readFileAlloc(
                    storage.io,
                    &content_hash_str,
                    req.gpa,
                    .limited(req.location.size + 1), // i don't understand why we need the +1
                ) catch |e| {
                    log.err(
                        "failed to load from file {s} with error {}",
                        .{ &content_hash_str, e },
                    );
                    req.remote.result = error.Content;
                    continue;
                };
                if (dst.len != req.location.size) {
                    log.err(
                        "file {s} is size {} but expected {}",
                        .{ &content_hash_str, dst.len, req.location.size },
                    );
                    req.remote.result = error.Content;
                    continue;
                }

                req.remote.result = dst;
            }

            if (req.location.location == .bucket) {
                @panic("TODO");
            }

            req.remote.event.set(storage.io);
        }
    }
};

// literally every time i go to use std.heap.MemoryPool it has idiotic alignment issues...
fn MemoryPool(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            next: ?*Node,
            value: T,
        };

        arena_impl: std.heap.ArenaAllocator,
        free_list: ?*Node,

        fn init(gpa: std.mem.Allocator) Self {
            return .{
                .arena_impl = .init(gpa),
                .free_list = null,
            };
        }

        fn deinit(pool: *Self) void {
            pool.arena_impl.deinit();
            pool.* = undefined;
        }

        fn create(pool: *Self) !*T {
            if (pool.free_list) |node| {
                pool.free_list = node.next;
                return &node.value;
            }
            return try pool.arena_impl.allocator().create(T);
        }

        fn destroy(pool: *Self, value: *T) void {
            const node: *Node = @alignCast(@fieldParentPtr("value", value));
            node.next = pool.free_list;
            pool.free_list = node;
        }
    };
}

test "Storage" {
    const s: *Storage = try .init(std.testing.allocator, std.testing.io, "data", .{});
    defer s.deinit();

    var it = s.index.iterator();
    while (it.next()) |kv| std.debug.print(
        "{s} -> {}\n",
        .{ &kv.key_ptr.stringify(), kv.value_ptr },
    );

    const uuid_a: Uuid = try .parse("6BQN4HWA3VC8ZYQ1ZZ1BDSJ771");
    const uuid_b: Uuid = try .parse("1Y99Z3J6K45HR5S3WZKSVQ51E1");
    const uuid_c: Uuid = try .parse("37BQJ0V3J4RA73SA8QBQH8VY1Z");

    // future is designed to support the same pattern as the Io.Future
    // THINK: is there any scenario where this similarity would fail?
    var a_future = try s.loadMany(u8, std.testing.allocator, uuid_a);
    defer if (a_future.cancel()) |a| std.testing.allocator.free(a) else |_| {};
    var b_future = try s.loadMany(u8, std.testing.allocator, uuid_b);
    defer if (b_future.cancel()) |b| std.testing.allocator.free(b) else |_| {};
    var c_future = try s.loadMany(u8, std.testing.allocator, uuid_c);
    defer if (c_future.cancel()) |c| std.testing.allocator.free(c) else |_| {};

    const a = try a_future.await();
    const b = try b_future.await();
    const c = try c_future.await();

    std.debug.print("{s}\n", .{a});
    std.debug.print("{s}\n", .{b});
    std.debug.print("{s}\n", .{c});
}
