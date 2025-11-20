const std = @import("std");

const BlockPool = @import("block_pool.zig").BlockPool;
const UntypedAggregateQueue = @import("aggregate_queue.zig").UntypedAggregateQueue;

const log = std.log.scoped(.ecs);

pub const Key = enum(u64) {
    nil = 0,
    _,

    /// iid random (for a set of keys) byte, could be useful for caching
    pub fn fingerprint(key: Key) u8 {
        return @truncate(@intFromEnum(key) >> 32); // TODO what are the best bits?
    }

    pub fn hash(key: Key) u64 {
        return @intFromEnum(key); // it's already random
    }
};

pub const KeyGenerator = struct {
    counter: u64 = 1,
    mutex: std.Thread.Mutex = std.Thread.Mutex{},

    pub fn next(keygen: *KeyGenerator) Key {
        // xorshift* with 2^64 - 1 period (0 is fixed point, and also the nil entity)
        keygen.mutex.lock();
        defer keygen.mutex.unlock();
        var x = keygen.counter;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        keygen.counter = x;
        return @enumFromInt(x *% 0x2545F4914F6CDD1D);
    }
};

pub fn Context(comptime Spec: type) type {
    return struct {
        const _Context = @This();

        pub const Component = std.meta.FieldEnum(Spec);
        const n_components = std.meta.fields(Component).len;
        fn ComponentType(comptime c: Component) type {
            return @FieldType(Spec, @tagName(c));
        }
        const ComponentSet = std.EnumSet(Component);

        pub const Record = blk: {
            // generate a type that has all components as optionals
            var fields: [n_components]std.builtin.Type.StructField = undefined;
            @memcpy(&fields, std.meta.fields(Spec));
            for (0..fields.len) |i| {
                fields[i].default_value = &@as(?fields[i].type, null);
                fields[i].type = ?fields[i].type;
            }
            const info: std.builtin.Type = .{ .@"struct" = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } };
            break :blk @Type(info);
        };

        pub const Reference = blk: {
            // generate a type that has all components as optional pointers
            var fields: [n_components]std.builtin.Type.StructField = undefined;
            @memcpy(&fields, std.meta.fields(Spec));
            for (0..fields.len) |i| {
                fields[i].default_value = &@as(?*fields[i].type, null);
                fields[i].type = ?*fields[i].type;
            }
            const info: std.builtin.Type = .{ .@"struct" = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } };
            break :blk @Type(info);
        };

        pub const Page = struct {
            const Header = struct {
                keys: [*]Key,
                components: [n_components]usize,
                capacity: usize,
                len: usize,
            };
            header: Header,
            data: [BlockPool.block_size - @sizeOf(Header)]u8,

            fn create(pool: *BlockPool, set: ComponentSet) !*Page {
                const page = try pool.create(Page);
                page.header.capacity = 0;
                page.header.len = 0;

                var sz: usize = @sizeOf(usize);
                inline for (0..n_components) |i| {
                    const c: Component = @enumFromInt(i);
                    if (set.contains(c)) {
                        sz += @sizeOf(ComponentType(c));
                    }
                }

                page.header.capacity = page.data.len / sz;
                while (true) {
                    var ptr = @intFromPtr(&page.data[0]);
                    ptr = std.mem.alignForward(usize, ptr, @alignOf(Key));
                    page.header.keys = @ptrFromInt(ptr);
                    ptr += @sizeOf(Key) * page.header.capacity;
                    inline for (0..n_components) |i| {
                        const c: Component = @enumFromInt(i);
                        if (set.contains(c)) {
                            const C = ComponentType(c);
                            ptr = std.mem.alignForward(usize, ptr, @alignOf(C));
                            page.header.components[i] = ptr;
                            ptr += @sizeOf(C) * page.header.capacity;
                        } else {
                            page.header.components[i] = 0;
                        }
                    }
                    if (ptr <= @intFromPtr(&page.data[0]) + page.data.len) break;
                    page.header.capacity -= 1;
                    log.debug("capacity overestimate for archetype {}", .{set});
                }

                return page;
            }

            fn append(page: *Page, key: Key, record: Record) usize {
                std.debug.assert(page.header.len < page.header.capacity);
                page.header.keys[page.header.len] = key;
                inline for (std.meta.fields(Record), 0..) |field, i| {
                    if (@field(record, field.name) != null) {
                        const c: Component = @enumFromInt(i);
                        page.component(c)[page.header.len] = @field(record, field.name).?;
                    }
                }
                const index = page.header.len;
                page.header.len += 1;
                return index;
            }

            /// returns the key to the entity that was relocated (or nil if no relocation)
            fn erase(page: *Page, index: usize) Key {
                const end = page.header.len - 1;
                if (index == end) {
                    // easy special case with no swap
                    page.header.len -= 1;
                    return .nil;
                }

                const moved = page.header.keys[end];
                page.header.keys[index] = page.header.keys[end];
                inline for (page.header.components, 0..) |a, i| {
                    if (a != 0) {
                        const c: Component = @enumFromInt(i);
                        const data = page.component(c);
                        data[index] = data[end];
                    }
                }
                page.header.len -= 1;
                return moved;
            }

            fn componentSet(page: Page) ComponentSet {
                var set = ComponentSet.initEmpty();
                for (page.header.components, 0..) |a, i| {
                    if (a != 0) set.insert(@as(Component, @enumFromInt(i)));
                }
                return set;
            }

            fn hasComponent(page: Page, c: Component) bool {
                return page.header.components[@intFromEnum(c)] != 0;
            }

            fn component(page: *Page, comptime c: Component) [*]ComponentType(c) {
                const a = page.header.components[@intFromEnum(c)];
                std.debug.assert(a != 0);
                return @ptrFromInt(a);
            }

            fn get(page: *Page, comptime c: Component, ix: usize) ComponentType(c) {
                return page.component(c)[ix];
            }

            fn getPtr(page: *Page, comptime c: Component, ix: usize) *ComponentType(c) {
                return &page.component(c)[ix];
            }

            fn getOptional(page: *Page, comptime c: Component, ix: usize) ?ComponentType(c) {
                if (page.header.components[@intFromEnum(c)] == 0) return null;
                return page.component(c)[ix];
            }

            fn getOptionalPtr(
                page: *Page,
                comptime c: Component,
                ix: usize,
            ) ?*ComponentType(c) {
                if (page.header.components[@intFromEnum(c)] == 0) return null;
                return &page.component(c)[ix];
            }
        };
        const PageInfo = struct { page: *Page, set: ComponentSet };

        const RawQuery = struct {
            include: []const Component = &.{},
            exclude: []const Component = &.{},

            fn reify(raw: RawQuery) Query {
                std.debug.assert(@inComptime()); // would be really inefficient otherwise
                var result = Query{
                    .include = ComponentSet.initEmpty(),
                    .exclude = ComponentSet.initEmpty(),
                };
                for (raw.include) |c| result.include.insert(c);
                for (raw.exclude) |c| result.exclude.insert(c);
                // assert that there are no overlaps
                const all = result.include.unionWith(result.exclude);
                const total = result.include.count() + result.exclude.count();
                std.debug.assert(all.count() == total);
                return result;
            }
        };
        const Query = struct {
            include: ComponentSet,
            exclude: ComponentSet,
        };

        pub fn PageView(comptime raw_query: RawQuery) type {
            return struct {
                const _PageView = @This();
                const query = raw_query.reify();

                page: *Page,

                pub fn keys(view: _PageView) []Key {
                    return view.page.header.keys[0..view.page.header.len];
                }

                pub fn get(
                    view: _PageView,
                    comptime component: Component,
                ) []ComponentType(component) {
                    comptime std.debug.assert(query.include.contains(component));
                    return view.page.component(component)[0..view.page.header.len];
                }

                pub fn getOptional(
                    view: _PageView,
                    comptime component: Component,
                ) ?[]ComponentType(component) {
                    if (!view.page.hasComponent(component)) return null;
                    return view.page.component(component)[0..view.page.header.len];
                }
            };
        }

        pub fn EntityView(comptime raw_query: RawQuery) type {
            return struct {
                const _EntityView = @This();
                const query = raw_query.reify();

                page: *Page,
                index: usize,

                pub fn key(view: _EntityView) Key {
                    return view.page.header.keys[view.index];
                }

                pub fn get(view: _EntityView, comptime c: Component) ComponentType(c) {
                    comptime std.debug.assert(query.include.contains(c));
                    return view.page.get(c, view.index);
                }

                pub fn getPtr(view: _EntityView, comptime c: Component) *ComponentType(c) {
                    comptime std.debug.assert(query.include.contains(c));
                    return view.page.getPtr(c, view.index);
                }

                pub fn getOptional(view: _EntityView, comptime c: Component) ?ComponentType(c) {
                    return view.page.getOptional(c, view.index);
                }

                pub fn getOptionalPtr(
                    view: _EntityView,
                    comptime c: Component,
                ) ?*ComponentType(c) {
                    return view.page.getOptionalPtr(c, view.index);
                }

                pub fn record(view: _EntityView) Record {
                    var rec = Record{};
                    inline for (0..n_components) |i| {
                        const c: Component = @enumFromInt(i);
                        @field(rec, @tagName(c)) = view.getOptional(c);
                    }
                    return rec;
                }

                pub fn reference(view: _EntityView) Reference {
                    var ref = Reference{};
                    inline for (0..n_components) |i| {
                        const c: Component = @enumFromInt(i);
                        @field(ref, @tagName(c)) = view.getOptionalPtr(c);
                    }
                    return ref;
                }
            };
        }

        pub const World = struct {
            const cache_size = 32;

            const CreateQueue = struct {
                const CreateQueueEntry = struct {
                    key: Key,
                    record: Record,
                };

                keygen: *KeyGenerator,
                queue: UntypedAggregateQueue.SubQueue,

                pub fn create(queue: *CreateQueue, record: Record) !Key {
                    const key = queue.keygen.next();
                    try queue.queue.push(CreateQueueEntry, .{ .key = key, .record = record });
                    return key;
                }
            };
            const DestroyQueue = struct {
                queue: UntypedAggregateQueue.SubQueue,

                pub fn destroy(queue: *DestroyQueue, key: Key) !void {
                    std.debug.assert(key != .nil);
                    try queue.queue.push(Key, key);
                }
            };
            fn InsertQueue(comptime component: Component) type {
                return struct {
                    const Self = @This();
                    const InsertQueueEntry = struct {
                        key: Key,
                        value: ComponentType(component),
                    };

                    queue: UntypedAggregateQueue.SubQueue,

                    pub fn insert(
                        queue: *Self,
                        key: Key,
                        value: ComponentType(component),
                    ) !void {
                        std.debug.assert(key != .nil);
                        try queue.queue.push(
                            InsertQueueEntry,
                            .{ .key = key, .value = value },
                        );
                    }
                };
            }
            const RemoveQueue = struct {
                const Self = @This();

                queue: UntypedAggregateQueue.SubQueue,

                pub fn remove(queue: *Self, key: Key) !void {
                    std.debug.assert(key != .nil);
                    try queue.queue.push(Key, key);
                }
            };

            context: *Context,

            create_queue: UntypedAggregateQueue,
            destroy_queue: UntypedAggregateQueue,
            insert_queues: std.EnumArray(Component, UntypedAggregateQueue),
            remove_queues: std.EnumArray(Component, UntypedAggregateQueue),

            cache_rng_state: u64,
            pages: std.MultiArrayList(PageInfo), // first cache_size slots form cache
            map: std.AutoHashMapUnmanaged(Key, EntityView(.{})),

            pub fn create(context: *_Context) !*World {
                const world = try context.pool.gpa.create(World);
                world.context = context;
                world.cache_rng_state = @intFromEnum(context.keygen.next()); // it's free rng
                world.pages = .empty;
                world.map = .empty;
                const empty_queue = UntypedAggregateQueue.init(context.pool); // POD when empty
                world.create_queue = empty_queue;
                world.destroy_queue = empty_queue;
                world.insert_queues = std.EnumArray(Component, UntypedAggregateQueue)
                    .initFill(empty_queue);
                world.remove_queues = std.EnumArray(Component, UntypedAggregateQueue)
                    .initFill(empty_queue);
                return world;
            }

            pub fn destroy(world: *World) void {
                world.pages.deinit(world.context.pool.gpa);
                world.map.deinit(world.context.pool.gpa);
                world.create_queue.deinit();
                world.destroy_queue.deinit();
                var it_insert = world.insert_queues.iterator();
                while (it_insert.next()) |kv| kv.value.deinit();
                var it_remove = world.remove_queues.iterator();
                while (it_remove.next()) |kv| kv.value.deinit();
                world.context.pool.gpa.destroy(world);
            }

            pub fn entity(world: *World, key: Key) ?EntityView(.{}) {
                return world.map.get(key);
            }

            // pub fn pageIterator() PageIterator(raw_query) {}
            // pub fn entityIterator() EntityIterator(raw_query) {}

            pub fn acquireCreateQueue(world: *World) CreateQueue {
                return .{
                    .keygen = world.context.keygen,
                    .queue = world.create_queue.acquire(),
                };
            }
            pub fn submitCreateQueue(world: *World, queue: *CreateQueue) void {
                world.create_queue.submit(queue.queue);
            }

            pub fn acquireDestroyQueue(world: *World) DestroyQueue {
                return .{ .queue = world.destroy_queue.acquire() };
            }
            pub fn submitDestroyQueue(world: *World, queue: *DestroyQueue) void {
                world.destroy_queue.submit(queue.queue);
            }

            pub fn acquireInsertQueue(
                world: *World,
                comptime component: Component,
            ) InsertQueue(component) {
                return .{ .queue = world.insert_queues.getPtr(component).acquire() };
            }
            pub fn submitInsertQueue(
                world: *World,
                comptime component: Component,
                queue: *InsertQueue(component),
            ) void {
                world.insert_queues.getPtr(component).submit(queue.queue);
            }

            pub fn acquireRemoveQueue(world: *World, comptime component: Component) RemoveQueue {
                return .{ .queue = world.remove_queues.getPtr(component).acquire() };
            }
            pub fn submitRemoveQueue(
                world: *World,
                comptime component: Component,
                queue: *RemoveQueue,
            ) void {
                world.remove_queues.getPtr(component).submit(queue.queue);
            }

            // maybe have a mutex-protected direct push to the queues for convenience
        };

        keygen: KeyGenerator,
        pool: BlockPool,
    };
}

// 0x9e3779b97f4a7c55;
