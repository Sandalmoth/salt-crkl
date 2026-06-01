const std = @import("std");

const Uuid = @import("Uuid.zig");

const log = std.log.scoped(.spiral);

pub const Error = error{
    Bucket,
    File,
    Preload,
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

pub const Future = struct {
    event: ?*std.Io.Event,
    storage: *Storage,

    pub fn poll(self: @This()) bool {
        if (self.event) |event| return event.isSet();
        return true;
    }
    pub fn await(self: *@This()) !void {
        if (self.event) |event| {
            try event.wait(self.storage.io);

            try self.storage.mutex.lock(self.storage.io);
            defer self.storage.mutex.unlock(self.storage.io);
            self.storage.events.destroy(event);
            self.event = null;
        }
    }
};

// pub const Future = enum(u64) {
//     nil = 0,
//     _,

//     const HashContext = struct {
//         pub fn hash(ctx: HashContext, future: Future) u64 {
//             _ = ctx;
//             return @intFromEnum(future); // it's already random
//         }

//         pub fn eql(ctx: HashContext, a: Future, b: Future) bool {
//             _ = ctx;
//             return a == b;
//         }
//     };
// };

pub const LoadOptions = struct {
    alignment: std.mem.Alignment = .@"1",
};

pub const StorageConfig = struct {
    capacity: u32 = 1024,
    worker_count: u32 = 4,
};

pub const Storage = struct {
    const LoadRequest = struct {
        event: *std.Io.Event,
        dst: []u8,
        location: Location,
    };

    gpa: std.mem.Allocator,
    io: std.Io,

    mutex: std.Io.Mutex = .init,

    dir: std.Io.Dir,
    index: std.AutoHashMapUnmanaged(Uuid, Location),
    buckets: []std.Io.File,
    preload: []const u8,

    // futures: std.AutoHashMapUnmanaged(Future, Error![]u8) = .empty,
    // future_counter: u64 = 1,

    events: MemoryPool(std.Io.Event),
    capacity: usize,

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

        var events: MemoryPool(std.Io.Event) = .init(gpa);
        errdefer events.deinit();

        storage.* = .{
            .gpa = gpa,
            .io = io,
            .dir = dir,
            .index = index,
            .buckets = &.{},
            .preload = preload,
            .events = events,
            .capacity = config.capacity,
            .queue_buffer = queue_buffer,
            .queue = .init(queue_buffer),
        };

        // try storage.futures.ensureTotalCapacity(gpa, config.capacity);
        // errdefer storage.futures.deinit(gpa);

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
        // storage.futures.deinit(storage.gpa);
        storage.gpa.free(storage.preload);
        storage.index.deinit(storage.gpa);
        storage.dir.close(storage.io);

        storage.gpa.destroy(storage);
    }

    // allocating load
    // - how do we pass the comptime alignment to alloc later on?
    // - i guess we have to alloc on load and fill it later (and free if it fails i guess)
    // - can poll or wait on handle, waiting returns the memory or the memory
    // - the future would have to be generic
    // - probably have a loadOne(T) -> *T and loadMany(T) -> []T

    // load to buffer
    // - user basically gets something to poll or wait, like a std.Io.Event
    // - before then, touching the memory they provided is undefined behaviour
    // - user doesn't have to wrap things in allocator if inconvenient
    // - no generic future
    // - i guess if the load fails, the await on the future would return the error

    pub fn alloc(storage: *Storage, comptime T: type, gpa: std.mem.Allocator, uuid: Uuid) ![]T {
        try storage.mutex.lock(storage.io);
        defer storage.mutex.unlock(storage.io);

        const src = storage.index.get(uuid) orelse {
            log.err("uuid {s} is not in index", .{&uuid.stringify()});
            return error.Invalid;
        };
        return try gpa.alloc(T, @divExact(src.size, @sizeOf(T)));
    }

    pub fn load(
        storage: *Storage,
        uuid: Uuid,
        dst: []u8,
    ) !Future {
        try storage.mutex.lock(storage.io);
        defer storage.mutex.unlock(storage.io);

        if (storage.capacity == 0) return error.Capacity;
        const src = storage.index.get(uuid) orelse {
            log.err("uuid {s} is not in index", .{&uuid.stringify()});
            return error.Invalid;
        };

        storage.capacity -= 1;
        // std.debug.assert(storage.futures.available > 0);
        // const future = newFuture(storage);

        if (src.location == .preload) {
            @memcpy(dst, storage.preload[src.location.preload .. src.location.preload + src.size]);
            return .{ .event = null, .storage = storage };
        } else {
            const event = try storage.events.create();
            errdefer storage.events.destroy(event);
            event.reset();
            try storage.queue.putOne(storage.io, .{
                .location = src,
                .dst = dst,
                .event = event,
            });
            return .{ .event = event, .storage = storage };
        }

        unreachable;
    }

    fn worker(storage: *Storage) !void {
        while (true) {
            const req = storage.queue.getOne(storage.io) catch return error.Canceled;
            if (req.location.location == .file) {
                const file = req.location.location.file;
                var content_hash_str: [32]u8 = undefined;
                _ = std.fmt.bufPrint(&content_hash_str, "{x}", .{file}) catch unreachable;
                _ = storage.dir.readFile(storage.io, &content_hash_str, req.dst) catch unreachable;
                // FIXME how can we provide these errors to the user?
                // catch |e| {
                //     log.err("failed to load from file {s} with error {}", .{ &content_hash_str, e });
                //     return error.File;
                // };
            }
            req.event.set(storage.io);
        }
    }

    // fn newFuture(storage: *Storage) Future {
    //     // xorshift* with 2^64 - 1 period (0 is fixed point, and also the nil entity)
    //     // NOTE could be atomic + cas instead
    //     // storage.mutex.lockUncancelable(storage.io);
    //     // defer storage.mutex.unlock(storage.io);
    //     // currently this is executed under a mutex anyway but could change in the future
    //     var x = storage.future_counter;
    //     x ^= x >> 12;
    //     x ^= x << 25;
    //     x ^= x >> 27;
    //     storage.future_counter = x;
    //     return @enumFromInt(x *% 0x2545f4914f6cdd1d);
    // }
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
    const a = try s.alloc(u8, std.testing.allocator, uuid_a);
    defer std.testing.allocator.free(a);
    var a_future = try s.load(uuid_a, a);
    try a_future.await();
    std.debug.print("{s}\n", .{a});

    // const a =

    // var a_future = try s.load(
    //     std.testing.allocator,
    //     try .parse("603HK0R1ZP89REPQDG25GGYSTW"),
    // );
    // var b_future = try s.load(
    //     std.testing.allocator,
    //     try .parse("1Y99Z3J6K45HR5S3WZKSVQ51E1"),
    // );
    // var c_future = try s.load(
    //     std.testing.allocator,
    //     try .parse("37BQJ0V3J4RA73SA8QBQH8VY1Z"),
    // );

    // const a = try a_future.await();
    // defer std.testing.allocator.free(a);
    // std.debug.print("{s}\n", .{a});

    // const b = try b_future.await();
    // defer std.testing.allocator.free(b);
    // std.debug.print("{s}\n", .{b});

    // const c = try c_future.await();
    // defer std.testing.allocator.free(c);
    // std.debug.print("{s}\n", .{c});
}

// pub const Storage = struct {
//     const Future = struct {
//         event: ?*std.Io.Event,
//         future: std.Io.Future(Error![]u8),
//         io: std.Io,

//         pub fn poll(self: @This()) bool {
//             if (self.event) |event| return event.isSet();
//             return true;
//         }
//         pub fn await(self: *@This()) ![]u8 {
//             const result = try self.future.await(self.io);
//             if (self.event) |event| {
//                 DeferredMemoryPool(std.Io.Event).mark(event);
//                 self.event = null;
//             }
//             return result;
//         }
//     };

//     const Event = union(enum) {
//         created: Uuid,
//         altered: Uuid,
//         deleted: Uuid,
//     };

//     pub const Location = struct {
//         size: u64, // size of the (decompressed) asset
//         location: union(enum) {
//             bucket: struct {
//                 index: u32,
//                 offset: u64,
//                 size: u64, // (maybe compressed) size in the bucket
//                 compressed: bool,
//             },
//             file: u128, // content hash, hex string is filename
//             preload: u64, // offset in preload memory
//         },

//         const Flags = packed struct(u32) {
//             compressed: bool = false,
//             in_bucket: bool = false,
//             in_file: bool = false,
//             in_preload: bool = false,
//             _pad: u28 = 0,
//         };

//         pub fn serialize(location: Location, writer: *std.Io.Writer) !void {
//             var flags: Flags = .{};
//             switch (location.location) {
//                 .bucket => |bucket| {
//                     flags.in_bucket = true;
//                     flags.compressed = bucket.compressed;
//                 },
//                 .file => |file| {
//                     _ = file;
//                     flags.in_file = true;
//                 },
//                 .preload => |preload| {
//                     _ = preload;
//                     flags.in_preload = true;
//                 },
//             }
//             try writer.writeInt(u32, @bitCast(flags), .little);
//             try writer.writeInt(u64, location.size, .little);
//             switch (location.location) {
//                 .bucket => |bucket| {
//                     try writer.writeInt(u32, bucket.index, .little);
//                     try writer.writeInt(u64, bucket.offset, .little);
//                     try writer.writeInt(u64, bucket.size, .little);
//                 },
//                 .file => |file| {
//                     try writer.writeInt(u128, file, .little);
//                 },
//                 .preload => |preload| {
//                     try writer.writeInt(u64, preload, .little);
//                 },
//             }
//         }

//         pub fn deserialize(reader: *std.Io.Reader) !Location {
//             const flags: Flags = @bitCast(try reader.takeInt(u32, .little));
//             var location: Location = undefined;
//             location.size = try reader.takeInt(u64, .little);
//             if (flags.in_bucket) {
//                 std.debug.assert(!flags.in_file);
//                 std.debug.assert(!flags.in_preload);
//                 location.location = .{ .bucket = .{
//                     .index = try reader.takeInt(u32, .little),
//                     .offset = try reader.takeInt(u64, .little),
//                     .size = try reader.takeInt(u64, .little),
//                     .compressed = flags.compressed,
//                 } };
//             } else if (flags.in_file) {
//                 std.debug.assert(!flags.in_bucket);
//                 std.debug.assert(!flags.in_preload);
//                 location.location = .{ .file = try reader.takeInt(u128, .little) };
//             } else if (flags.in_preload) {
//                 std.debug.assert(!flags.in_bucket);
//                 std.debug.assert(!flags.in_file);
//                 location.location = .{ .preload = try reader.takeInt(u64, .little) };
//             } else return error.Invalid;
//             return location;
//         }
//     };

//     const LoadOptions = struct {
//         alignment: std.mem.Alignment = .@"1",
//     };

//     gpa: std.mem.Allocator,
//     io: std.Io,
//     immediate_io: std.Io.Threaded = .init_single_threaded, // used to unify future interface
//     dir: std.Io.Dir,

//     event_pool: DeferredMemoryPool(std.Io.Event),

//     rwlock: std.Io.RwLock,

//     index: std.AutoHashMapUnmanaged(Uuid, Location),
//     buckets: []std.Io.File,
//     preload: []const u8,

//     last_refresh: std.Io.Timestamp,

//     pub fn init(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Storage {
//         const dir: std.Io.Dir = try .openDir(.cwd(), io, path, .{});
//         errdefer dir.close(io);

//         var buffer: [1024]u8 = undefined;
//         const index_file = try dir.openFile(io, "index", .{ .mode = .read_only });
//         var index_reader = index_file.reader(io, &buffer);
//         const asset_count = try index_reader.interface.takeInt(u32, .little);
//         var index: std.AutoHashMapUnmanaged(Uuid, Location) = .empty;
//         try index.ensureTotalCapacity(gpa, @intCast(asset_count));
//         for (0..asset_count) |_| {
//             const uuid: Uuid = .{ .bits = try index_reader.interface.takeInt(u128, .little) };
//             const location: Location = try .deserialize(&index_reader.interface);
//             std.debug.assert(!index.contains(uuid));
//             index.putAssumeCapacity(uuid, location);
//         }
//         errdefer index.deinit(gpa);

//         const preload = try dir.readFileAlloc(io, "preload", gpa, .limited(1024 * 1024 * 1024));
//         errdefer gpa.free(preload);

//         return .{
//             .gpa = gpa,
//             .io = io,
//             .dir = dir,
//             .event_pool = .empty,
//             .rwlock = .init,
//             .index = index,
//             .buckets = &.{},
//             .preload = preload,
//             .last_refresh = .now(io, .real),
//         };
//     }

//     pub fn deinit(storage: *Storage) void {
//         // Q: should we wait for outstanding tasks or something?
//         // i guess ideally we should request cancellation of every load
//         // otherwise, could be a problem if we close the dir or deinit the event i think
//         // but seems kinda annoying to track, and shouldn't really be a problem
//         // and besides, i think it's also illegal to deinit an io without awaiting everything
//         // so like, we're not adding an extra complication in this case
//         storage.gpa.free(storage.preload);
//         storage.index.deinit(storage.gpa);
//         storage.dir.close(storage.io);
//         storage.event_pool.deinit(storage.gpa);
//     }

//     pub fn load(
//         storage: *Storage,
//         allocator: std.mem.Allocator,
//         uuid: Uuid,
//         options: LoadOptions,
//     ) !Future {
//         try storage.rwlock.lockShared(storage.io);
//         defer storage.rwlock.unlockShared(storage.io);

//         const location = storage.index.get(uuid) orelse return error.Invalid;
//         const dst = try allocator.alloc(u8, location.size);
//         errdefer allocator.free(dst);

//         if (location.location == .preload) {
//             // use single threaded io if preloaded,
//             // i.e. just run right away since it's already in mem
//             const io = storage.immediate_io.io();
//             return .{
//                 .event = null,
//                 .future = io.async(loadImpl, .{ storage, location, dst, null }),
//                 .io = io,
//             };
//         } else {
//             try storage.event_pool.sweep(storage.io); // noop if there are free events to use
//             const event = try storage.event_pool.create(storage.gpa, storage.io);
//             event.reset();
//             errdefer DeferredMemoryPool(std.Io.Event).mark(event);

//             const io = storage.io;
//             return .{
//                 .event = event,
//                 .future = io.async(loadImpl, .{ storage, location, dst, event }),
//                 .io = io,
//             };
//         }

//         unreachable;
//     }

//     pub fn poll(storage: *Storage) !?Event {
//         if (storage.last_refresh.untilNow(storage.io, .real).toMilliseconds() > 100) {
//             // check if index file has changed and if so reload them.
//             // note that hot-reloading always uses the file location

//             // TODO check instead of blind reloading
//             try storage.rwlock.lock();
//             defer storage.rwlock.unlock();

//             var buffer: [1024]u8 = undefined;
//             const index_file = try storage.dir.openFile(storage.io, "index", .{ .mode = .read_only });
//             var index_reader = index_file.reader(storage.io, &buffer);
//             const asset_count = try index_reader.interface.takeInt(u32, .little);
//             var index: std.AutoHashMapUnmanaged(Uuid, Location) = .empty;
//             try index.ensureTotalCapacity(storage.gpa, @intCast(asset_count));
//             for (0..asset_count) |_| {
//                 const uuid: Uuid = .{ .bits = try index_reader.interface.takeInt(u128, .little) };
//                 const location: Location = try .deserialize(&index_reader.interface);
//                 std.debug.assert(!index.contains(uuid));
//                 index.putAssumeCapacity(uuid, location);
//             }
//             errdefer index.deinit(storage.gpa);

//             // TODO somehow generate a list of events here

//             storage.index.deinit(storage.gpa);
//             storage.index = index;
//             storage.last_refresh = .now(storage.io, .real);
//         }

//         // TODO then, if there are events, pop one off the list

//         return null;
//     }

//     fn loadImpl(storage: *Storage, src: Location, dst: []u8, event: ?*std.Io.Event) Error![]u8 {
//         switch (src.location) {
//             .bucket => {
//                 @panic("TODO");
//             },
//             .file => |file| {
//                 var content_hash_str: [32]u8 = undefined;
//                 _ = std.fmt.bufPrint(&content_hash_str, "{x}", .{file}) catch unreachable;
//                 _ = storage.dir.readFile(storage.io, &content_hash_str, dst) catch |e| {
//                     log.err("failed to load from file {s} with error {}", .{ &content_hash_str, e });
//                     return error.File;
//                 };
//             },
//             .preload => |preload| {
//                 @memcpy(dst, storage.preload[preload .. preload + src.size]);
//             },
//         }
//         if (event != null) event.?.set(storage.io);

//         return dst;
//     }
// };

// test "Storage" {
//     var s: Storage = try .init(std.testing.allocator, std.testing.io, "data");
//     defer s.deinit();

//     var a_future = try s.load(
//         std.testing.allocator,
//         try .parse("603HK0R1ZP89REPQDG25GGYSTW"),
//     );
//     var b_future = try s.load(
//         std.testing.allocator,
//         try .parse("1Y99Z3J6K45HR5S3WZKSVQ51E1"),
//     );
//     var c_future = try s.load(
//         std.testing.allocator,
//         try .parse("37BQJ0V3J4RA73SA8QBQH8VY1Z"),
//     );

//     const a = try a_future.await();
//     defer std.testing.allocator.free(a);
//     std.debug.print("{s}\n", .{a});

//     const b = try b_future.await();
//     defer std.testing.allocator.free(b);
//     std.debug.print("{s}\n", .{b});

//     const c = try c_future.await();
//     defer std.testing.allocator.free(c);
//     std.debug.print("{s}\n", .{c});
// }

// pub fn DeferredMemoryPool(comptime T: type) type {
//     return struct {
//         const Self = @This();

//         const Node = struct {
//             flag: bool,
//             value: T,
//             next: ?*Node,
//         };

//         const Segment = struct {
//             nodes: []Node,
//             next: ?*Segment,
//         };

//         mutex: std.Io.Mutex,
//         segments: ?*Segment,
//         free_list: ?*Node,

//         const empty = Self{ .mutex = .init, .segments = null, .free_list = null };

//         pub fn create(pool: *Self, gpa: std.mem.Allocator, io: std.Io) !*T {
//             try pool.mutex.lock(io);
//             defer pool.mutex.unlock(io);

//             if (pool.free_list) |node| {
//                 std.debug.assert(!node.flag);
//                 pool.free_list = node.next;
//                 return &node.value;
//             }

//             const new_segment_size =
//                 if (pool.segments) |segment| 2 * segment.nodes.len else 64 / @sizeOf(Node);
//             const segment = try gpa.create(Segment);
//             errdefer gpa.destroy(segment);
//             const nodes = try gpa.alloc(Node, new_segment_size);
//             errdefer gpa.free(nodes);
//             segment.* = .{
//                 .next = pool.segments,
//                 .nodes = nodes,
//             };
//             pool.segments = segment;
//             for (nodes) |*node| {
//                 node.* = .{
//                     .flag = false,
//                     .value = undefined,
//                     .next = pool.free_list,
//                 };
//                 pool.free_list = node;
//             }

//             if (pool.free_list) |node| {
//                 std.debug.assert(!node.flag);
//                 pool.free_list = node.next;
//                 return &node.value;
//             } else {
//                 unreachable;
//             }
//         }

//         pub fn deinit(pool: *Self, gpa: std.mem.Allocator) void {
//             var walk: ?*Segment = pool.segments;
//             while (walk) |segment| {
//                 walk = segment.next;
//                 gpa.free(segment.nodes);
//                 gpa.destroy(segment);
//             }
//         }

//         pub fn mark(value: *T) void {
//             const node: *Node = @alignCast(@fieldParentPtr("value", value));
//             node.flag = true;
//         }

//         pub fn sweep(pool: *Self, io: std.Io) !void {
//             try pool.mutex.lock(io);
//             defer pool.mutex.unlock(io);

//             if (pool.free_list) |_| return; // only sweep if we actually are out of free slots

//             var walk: ?*Segment = pool.segments;
//             while (walk) |segment| {
//                 walk = segment.next;
//                 for (segment.nodes) |*node| {
//                     if (!node.flag) continue;
//                     node.* = .{
//                         .flag = false,
//                         .value = undefined,
//                         .next = pool.free_list,
//                     };
//                     pool.free_list = node;
//                 }
//             }
//         }
//     };
// }
