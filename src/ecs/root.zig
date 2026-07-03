const std = @import("std");

pub const BlockPool = @import("block_pool.zig").BlockPool;

const log = std.log.scoped(.ecs);

const keygen_weyl = 0xbf072894ec36014d;
var keygen_counter: u64 = keygen_weyl;
var keygen_seed: u64 = 1;

pub const Key = enum(u64) {
    nil = 0,
    _,

    /// iid random (for a set of keys) byte, could be useful for caching
    pub fn fingerprint(key: Key) u8 {
        const a: u8 = @truncate(@intFromEnum(key) >> 23);
        const b: u8 = @truncate(@intFromEnum(key) >> 43);
        return (a ^ b) *% 0x9d;
    }

    const HashContext = struct {
        pub fn hash(ctx: HashContext, key: Key) u64 {
            _ = ctx;
            return @intFromEnum(key); // *% 0x9e3779b97f4a7c55; // it's already random
        }

        pub fn eql(ctx: HashContext, a: Key, b: Key) bool {
            _ = ctx;
            return a == b;
        }
    };

    pub fn new() Key {
        var x = @atomicRmw(u64, &keygen_counter, .Add, keygen_weyl, .monotonic);
        // SplitMix64
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x ^= (x >> 31);
        return @enumFromInt(x *% keygen_seed);
    }
};

/// lowest bit is not used
pub fn seed(_seed: u64) void {
    std.debug.assert(keygen_counter == keygen_weyl); // must have generated no keys yet
    keygen_seed = _seed | 1;
}

pub fn World(comptime Spec: type) type {
    return struct {
        const cache_size = 32;
        const _World = @This();

        pub const Component = std.meta.FieldEnum(Spec);
        const n_components = std.meta.fields(Component).len;
        fn ComponentType(comptime c: Component) type {
            return @FieldType(Spec, @tagName(c));
        }
        const ComponentSet = std.EnumSet(Component);

        pub const Record = blk: {
            // generate a type that has all components as optionals

            var field_names: [n_components][]const u8 = undefined;
            var field_types: [n_components]type = undefined;
            var field_attrs: [n_components]std.builtin.Type.StructField.Attributes = undefined;
            for (std.meta.fields(Spec), 0..) |field, i| {
                field_names[i] = field.name;
                field_types[i] = ?field.type;
                field_attrs[i] = .{
                    .default_value_ptr = &@as(?field.type, null),
                };
            }
            break :blk @Struct(.auto, null, &field_names, &field_types, &field_attrs);
        };

        pub const Reference = blk: {
            // generate a type that has all components as optional pointers

            var field_names: [n_components][]const u8 = undefined;
            var field_types: [n_components]type = undefined;
            var field_attrs: [n_components]std.builtin.Type.StructField.Attributes = undefined;
            for (std.meta.fields(Spec), 0..) |field, i| {
                field_names[i] = field.name;
                field_types[i] = ?*field.type;
                field_attrs[i] = .{
                    .default_value_ptr = &@as(?*field.type, null),
                };
            }
            break :blk @Struct(.auto, null, &field_names, &field_types, &field_attrs);
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

        pub const CommandList = struct {
            const Node = struct {
                command: enum { create, destroy, insert, remove },
                key: Key,
                data: *anyopaque,
                next: ?*Node,
            };

            arena: std.mem.Allocator,
            head: ?*Node = null,
            tail: ?*Node = null,

            pub fn create(list: *CommandList, record: Record) !Key {
                const node = try list.arena.create(Node);
                const data = try list.arena.create(Record);
                const key: Key = .new();
                node.* = .{
                    .command = .create,
                    .key = key,
                    .data = data,
                    .next = null,
                };
                data.* = record;
                list.append(node);
            }

            pub fn destroy(list: *CommandList, key: Key) !void {
                const node = try list.arena.create(Node);
                node.* = .{
                    .command = .create,
                    .key = key,
                    .data = undefined,
                    .next = null,
                };
                list.append(node);
            }

            pub fn insert(
                list: *CommandList,
                key: Key,
                comptime component: Component,
                value: ComponentType(component),
            ) !void {
                const node = try list.arena.create(Node);
                const data = try list.arena.create(struct {
                    component: Component,
                    value: ComponentType(component),
                });
                node.* = .{
                    .command = .create,
                    .key = key,
                    .data = data,
                    .next = null,
                };
                data.* = .{
                    .component = component,
                    .value = value,
                };
                list.append(node);
            }

            pub fn remove(list: *CommandList, key: Key, component: Component) !void {
                const node = try list.arena.create(Node);
                const data = try list.arena.create(struct {
                    key: Key,
                    component: Component,
                });
                node.* = .{
                    .command = .create,
                    .key = key,
                    .data = data,
                    .next = null,
                };
                data.* = .{
                    .component = component,
                };
                list.append(node);
            }

            fn append(list: *CommandList, node: *Node) void {
                if (list.head == null) {
                    std.debug.assert(list.tail == null);
                    list.head = node;
                    list.tail = node;
                } else {
                    std.debug.assert(list.tail != null);
                    list.tail.?.next = node;
                    list.tail = node;
                }
            }
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

        fn PageIterator(comptime raw_query: RawQuery) type {
            return struct {
                const _PageIterator = @This();
                const query = raw_query.reify();

                world: *_World,
                cursor: usize,

                pub fn next(it: *_PageIterator) ?PageView(raw_query) {
                    while (it.cursor < it.world.pages.len) {
                        const page = it.world.pages.items(.page)[it.cursor];
                        const set = it.world.pages.items(.set)[it.cursor];
                        it.cursor += 1;
                        if (query.include.subsetOf(set) and
                            query.exclude.intersectWith(set).count() == 0)
                        {
                            return .{ .page = page };
                        }
                    }
                    return null;
                }
            };
        }

        fn EntityIterator(comptime raw_query: RawQuery) type {
            return struct {
                const _EntityIterator = @This();
                const query = raw_query.reify();

                page_iterator: PageIterator(raw_query),
                page: ?*Page,
                cursor: usize,

                pub fn next(it: *_EntityIterator) ?EntityView(raw_query) {
                    if (it.page) |page| {
                        if (it.cursor < page.header.len) {
                            const index = it.cursor;
                            it.cursor += 1;
                            return .{ .page = page, .index = index };
                        }
                        it.page = null;
                    } else {
                        it.page = (it.page_iterator.next() orelse return null).page;
                        it.cursor = 0;
                    }
                    return it.next();
                }
            };
        }

        pool: *BlockPool,
        keygen: *KeyGen,

        queue_arena: std.heap.ArenaAllocator,
        // create_queue: UntypedList,
        // destroy_queue: UntypedList,
        // insert_queues: std.EnumArray(Component, UntypedList),
        // remove_queues: std.EnumArray(Component, UntypedList),

        cache_rng_state: u64,
        pages: std.MultiArrayList(PageInfo), // first cache_size slots form cache
        map: std.HashMapUnmanaged(Key, EntityView(.{}), Key.HashContext, 80),

        pub fn create(pool: *BlockPool, keygen: *KeyGen) !*_World {
            const world = try pool.gpa.create(_World);
            world.pool = pool;
            world.keygen = keygen;
            world.cache_rng_state = @intFromEnum(keygen.next()); // it's free rng
            world.pages = .empty;
            world.map = .empty;
            world.queue_arena = .init(pool.gpa);
            world.create_queue = .empty;
            world.destroy_queue = .empty;
            world.insert_queues = .initFill(.empty);
            world.remove_queues = .initFill(.empty);
            return world;
        }

        pub fn destroy(world: *_World) void {
            world.pages.deinit(world.pool.gpa);
            world.map.deinit(world.pool.gpa);
            world.queue_arena.deinit();
            world.pool.gpa.destroy(world);
        }

        pub fn entity(world: *_World, key: Key) ?EntityView(.{}) {
            return world.map.get(key);
        }

        pub fn pageIterator(
            world: *_World,
            comptime raw_query: RawQuery,
        ) PageIterator(raw_query) {
            return .{ .world = world, .cursor = 0 };
        }

        pub fn entityIterator(
            world: *_World,
            comptime raw_query: RawQuery,
        ) EntityIterator(raw_query) {
            return .{
                .page_iterator = world.pageIterator(raw_query),
                .page = null,
                .cursor = 0,
            };
        }

        pub fn acquire(world: *_World, arena: std.mem.Allocator) CommandList {
            return .{ .arena = arena };
        }

        pub fn submit(world: *_World, command_lists: []const CommandList) !void {
            // NOTE idempotent design allows rerunning a submit twice with no extra effect
            // which makes error recovery easy, just redo the submit after fixing the oom
            for (command_list) |command_lists| {
                var walk: ?*CommandList.Node = command_list.head;
                while (walk) |command| : (walk = command.next) {
                    const key = command.key;
                    switch (command.command) {
                        .create => {
                            if (world.map.contains(key)) continue;

                            const record: *Record = @ptrCast(@alignCast(command.data));
                            try world.map.ensureUnusedCapacity(world.pool.gpa, 1);
                            var set = ComponentSet.initEmpty();
                            inline for (std.meta.fields(Record), 0..) |field, i| {
                                if (@field(q.record, field.name) != null) set.insert(
                                    @as(Component, @enumFromInt(i)),
                                );
                            }
                            const page = try world.getPage(set);
                            const index = page.append(key, record.*);
                            world.map.putAssumeCapacity(key, .{ .index = index, .page = page });
                        },
                        .destroy => {
                            const location = world.map.get(key) orelse continue;

                            _ = world.map.remove(key);
                            if (location.page.header.len > 1) {
                                const moved = location.page.erase(location.index);
                                if (moved != .nil) world.map.putAssumeCapacity(
                                    moved,
                                    .{ .page = location.page, .index = location.index },
                                ); // overwrites, hence there is capacity by definition
                            } else {
                                // page is empty, destroy entirely
                                for (world.pages.items(.page), 0..) |p, i| {
                                    if (p == location.page) {
                                        world.pool.destroy(p);
                                        world.pages.swapRemove(i);
                                        break;
                                    }
                                }
                            }
                        },
                        .insert => {
                            // so here's a problem, we cant cast to the struct
                            // since the struct depends on a comptime only type
                            // so we need to change the insert data
                            // so we can switch on the runtime component to cast the value

                            const q = insert_queue.get(
                                struct { key: Key, value: ComponentType(c) },
                                insert_queue.cursor,
                            );
                            const location = world.map.get(q.key) orelse continue;
                            if (location.page.hasComponent(c)) continue; // NOTE double insert is noop
                            var set = location.page.componentSet();
                            set.insert(c);
                            const page = try world.getPage(set);
                            var record = location.record();
                            @field(record, @tagName(c)) = q.value;
                            const index = page.append(q.key, record);
                            world.map.putAssumeCapacity(q.key, .{ .page = page, .index = index });
                            const moved = location.page.erase(location.index);
                            if (moved != .nil) world.map.putAssumeCapacity(
                                moved,
                                .{ .page = location.page, .index = location.index },
                            );
                        },
                        .remove => {},
                    }
                }
            }
            _ = world;
        }

        /// lock free thread safe
        pub fn queueCreate(world: *_World, record: Record) !Key {
            const key = world.keygen.next();
            (try world.create_queue.addOne(
                struct { key: Key, record: Record },
                world.queue_arena.allocator(),
            )).* = .{ .key = key, .record = record };
            return key;
        }

        /// lock free thread safe
        pub fn queueInsert(
            world: *_World,
            key: Key,
            comptime component: Component,
            value: ComponentType(component),
        ) !void {
            std.debug.assert(key != .nil);
            const queue = world.insert_queues.getPtr(component);
            (try queue.addOne(
                struct { key: Key, value: ComponentType(component) },
                world.queue_arena.allocator(),
            )).* = .{ .key = key, .value = value };
        }

        /// lock free thread safe
        pub fn queueDestroy(world: *_World, key: Key) !void {
            std.debug.assert(key != .nil);
            (try world.destroy_queue.addOne(Key, world.queue_arena.allocator())).* = key;
        }

        /// lock free thread safe
        pub fn queueRemove(
            world: *_World,
            key: Key,
            comptime component: Component,
        ) !void {
            std.debug.assert(key != .nil);
            const queue = world.remove_queues.getPtr(component);
            (try queue.addOne(Key, world.queue_arena.allocator())).* = key;
        }

        pub fn resolveQueues(world: *_World) !void {
            while (world.create_queue.cursor < world.create_queue.len) {
                const q = world.create_queue.get(
                    struct { key: Key, record: Record },
                    world.create_queue.cursor,
                );
                try world.map.ensureUnusedCapacity(world.pool.gpa, 1);
                var set = ComponentSet.initEmpty();
                inline for (std.meta.fields(Record), 0..) |field, i| {
                    if (@field(q.record, field.name) != null) set.insert(
                        @as(Component, @enumFromInt(i)),
                    );
                }
                const page = try world.getPage(set);
                const index = page.append(q.key, q.record);

                world.map.putAssumeCapacity(q.key, .{ .index = index, .page = page });
                world.create_queue.cursor += 1;
            }

            while (world.destroy_queue.cursor < world.destroy_queue.len) {
                const q = world.destroy_queue.get(Key, world.destroy_queue.cursor);
                const location = world.map.get(q) orelse continue;
                _ = world.map.remove(q);
                if (location.page.header.len > 1) {
                    const moved = location.page.erase(location.index);
                    if (moved != .nil) world.map.putAssumeCapacity(
                        moved,
                        .{ .page = location.page, .index = location.index },
                    ); // overwrites, hence there is capacity by definition
                } else {
                    // page is empty, destroy entirely
                    for (world.pages.items(.page), 0..) |p, i| {
                        if (p == location.page) {
                            world.pool.destroy(p);
                            world.pages.swapRemove(i);
                            break;
                        }
                    }
                }
                world.destroy_queue.cursor += 1;
            }

            inline for (0..n_components) |i| {
                const c: Component = @enumFromInt(i);
                const insert_queue = world.insert_queues.getPtr(c);
                const remove_queue = world.remove_queues.getPtr(c);

                while (insert_queue.cursor < insert_queue.len) {
                    const q = insert_queue.get(
                        struct { key: Key, value: ComponentType(c) },
                        insert_queue.cursor,
                    );
                    const location = world.map.get(q.key) orelse continue;
                    if (location.page.hasComponent(c)) continue; // NOTE double insert is noop
                    var set = location.page.componentSet();
                    set.insert(c);
                    const page = try world.getPage(set);
                    var record = location.record();
                    @field(record, @tagName(c)) = q.value;
                    const index = page.append(q.key, record);
                    world.map.putAssumeCapacity(q.key, .{ .page = page, .index = index });
                    const moved = location.page.erase(location.index);
                    if (moved != .nil) world.map.putAssumeCapacity(
                        moved,
                        .{ .page = location.page, .index = location.index },
                    );
                    insert_queue.cursor += 1;
                }

                while (remove_queue.cursor < remove_queue.len) {
                    const q = remove_queue.get(Key, remove_queue.cursor);
                    const location = world.map.get(q) orelse continue;
                    if (!location.page.hasComponent(c)) continue;
                    var set = location.page.componentSet();
                    set.remove(c);
                    const page = try world.getPage(set);
                    var record = location.record();
                    @field(record, @tagName(c)) = null;
                    const index = page.append(q, record);
                    world.map.putAssumeCapacity(q, .{ .page = page, .index = index });
                    const moved = location.page.erase(location.index);
                    if (moved != .nil) world.map.putAssumeCapacity(
                        moved,
                        .{ .page = location.page, .index = location.index },
                    );
                    remove_queue.cursor += 1;
                }
            }

            _ = world.queue_arena.reset(.retain_capacity);
            world.create_queue = .empty;
            world.destroy_queue = .empty;
            world.insert_queues = .initFill(.empty);
            world.remove_queues = .initFill(.empty);
        }

        /// find or create page that has room for another entity with set components
        fn getPage(world: *_World, set: ComponentSet) !*Page {
            const pages = world.pages.items(.page);
            const sets = world.pages.items(.set);
            for (sets, pages, 0..) |s, p, i| {
                if (s.eql(set) and p.header.len < p.header.capacity) {
                    if (i >= cache_size) {
                        // not already in cache, swap with random position in cache
                        const slot = (world.cache_rng_state >> 29) % cache_size;
                        world.cache_rng_state =
                            world.cache_rng_state *% 0x5851f42d4c957f2d +% 1;
                        std.mem.swap(*Page, &pages[i], &pages[slot]);
                        std.mem.swap(ComponentSet, &sets[i], &sets[slot]);
                    }
                    return p;
                }
            }
            // no page exists with room for an entity like this, create one
            try world.pages.ensureUnusedCapacity(world.pool.gpa, 1);
            const page = try Page.create(world.pool, set);
            world.pages.appendAssumeCapacity(.{ .page = page, .set = set });
            // add it to cache also since we just accessed it
            if (world.pages.len - 1 >= cache_size) {
                const slot = (world.cache_rng_state >> 29) % cache_size;
                world.cache_rng_state =
                    world.cache_rng_state *% 0x5851f42d4c957f2d +% 1;
                std.mem.swap(*Page, &pages[world.pages.len - 1], &pages[slot]);
                std.mem.swap(ComponentSet, &sets[world.pages.len - 1], &sets[slot]);
            }
            return page;
        }
    };
}

test "basic create insert remove destroy functionality" {
    const W = World(struct { x: i32, y: f32 });
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();
    var keygen: KeyGen = .{};

    const world: *W = try .create(&pool, &keygen);
    defer world.destroy();

    const e0 = try world.queueCreate(.{});
    const e1 = try world.queueCreate(.{ .x = 1 });
    const e2 = try world.queueCreate(.{ .y = 2.5 });
    const e3 = try world.queueCreate(.{ .x = 3, .y = 3.5 });
    try world.resolveQueues();

    // var it = world.entityIterator(.{});
    // while (it.next()) |e| std.debug.print("{} {}\n", .{ e.key(), e.record() });

    try std.testing.expectEqual(null, world.entity(e0).?.getOptional(.x));
    try std.testing.expectEqual(null, world.entity(e0).?.getOptional(.y));
    try std.testing.expectEqual(1, world.entity(e1).?.getOptional(.x).?);
    try std.testing.expectEqual(null, world.entity(e1).?.getOptional(.y));
    try std.testing.expectEqual(null, world.entity(e2).?.getOptional(.x));
    try std.testing.expectEqual(2.5, world.entity(e2).?.getOptional(.y).?);
    try std.testing.expectEqual(3, world.entity(e3).?.getOptional(.x).?);
    try std.testing.expectEqual(3.5, world.entity(e3).?.getOptional(.y).?);

    try world.queueInsert(e0, .x, 99);
    try world.queueInsert(e0, .y, 99.5);
    try world.queueRemove(e1, .x);
    try world.queueInsert(e1, .y, 999.5);
    try world.queueInsert(e2, .x, 999);
    try world.queueRemove(e2, .y);
    try world.queueRemove(e3, .x);
    try world.queueRemove(e3, .y);
    try world.resolveQueues();

    // it = world.entityIterator(.{});
    // while (it.next()) |e| std.debug.print("{} {}\n", .{ e.key(), e.record() });

    try std.testing.expectEqual(99, world.entity(e0).?.getOptional(.x).?);
    try std.testing.expectEqual(99.5, world.entity(e0).?.getOptional(.y).?);
    try std.testing.expectEqual(null, world.entity(e1).?.getOptional(.x));
    try std.testing.expectEqual(999.5, world.entity(e1).?.getOptional(.y).?);
    try std.testing.expectEqual(999, world.entity(e2).?.getOptional(.x).?);
    try std.testing.expectEqual(null, world.entity(e2).?.getOptional(.y));
    try std.testing.expectEqual(null, world.entity(e3).?.getOptional(.x));
    try std.testing.expectEqual(null, world.entity(e3).?.getOptional(.y));

    try world.queueDestroy(e0);
    try world.queueDestroy(e1);
    try world.queueDestroy(e2);
    try world.queueDestroy(e3);
    try world.resolveQueues();

    // it = world.entityIterator(.{});
    // while (it.next()) |e| std.debug.print("{} {}\n", .{ e.key(), e.record() });

    try std.testing.expectEqual(null, world.entity(e0));
    try std.testing.expectEqual(null, world.entity(e1));
    try std.testing.expectEqual(null, world.entity(e2));
    try std.testing.expectEqual(null, world.entity(e3));
}
