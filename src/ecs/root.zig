const std = @import("std");

pub const BlockPool = @import("block_pool.zig").BlockPool;

const log = std.log.scoped(.ecs);

pub const KeyGen = struct {
    // current design produces different sequences for different seeds
    // but they are highly correlated since they're just proportional modulo 2**64
    const weyl = 0xbf072894ec36014d;

    counter: u64 = weyl,
    seed: u64,

    /// note lowest bit of seed it not used  (it must be odd))
    pub fn init(seed: u64) KeyGen {
        return .{ .seed = seed | 1 };
    }

    pub fn next(keygen: *KeyGen) Key {
        var x = @atomicRmw(u64, &keygen.counter, .Add, weyl, .monotonic);
        // SplitMix64
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x ^= (x >> 31);
        return @enumFromInt(x *% keygen.seed);
    }
};

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
};

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
            const Command = struct {
                command: enum { create, destroy, insert, remove },
                key: Key,
                next: ?*Command,
            };
            const CommandRecord = struct {
                command: Command,
                record: Record,
            };
            const CommandComponent = struct {
                command: Command,
                component: Component,
            };
            fn CommandInsert(comptime c: Component) type {
                return struct {
                    command: CommandComponent,
                    value: ComponentType(c),
                };
            }

            arena: std.mem.Allocator,
            keygen: *KeyGen,
            head: ?*Command = null,
            tail: ?*Command = null,

            pub fn create(list: *CommandList, record: Record) !Key {
                const command = try list.arena.create(CommandRecord);
                const key: Key = list.keygen.next();
                command.* = .{
                    .command = .{
                        .command = .create,
                        .key = key,
                        .next = null,
                    },
                    .record = record,
                };
                list.append(&command.command);
                return key;
            }

            pub fn destroy(list: *CommandList, key: Key) !void {
                const command = try list.arena.create(Command);
                command.* = .{
                    .command = .destroy,
                    .key = key,
                    .next = null,
                };
                list.append(command);
            }

            pub fn insert(
                list: *CommandList,
                key: Key,
                comptime component: Component,
                value: ComponentType(component),
            ) !void {
                const command = try list.arena.create(CommandInsert(component));
                command.* = .{
                    .command = .{
                        .command = .{
                            .command = .insert,
                            .key = key,
                            .next = null,
                        },
                        .component = component,
                    },
                    .value = value,
                };
                list.append(&command.command.command);
            }

            pub fn remove(list: *CommandList, key: Key, component: Component) !void {
                const command = try list.arena.create(CommandComponent);
                command.* = .{
                    .command = .{
                        .command = .remove,
                        .key = key,
                        .next = null,
                    },
                    .component = component,
                };
                list.append(&command.command);
            }

            fn append(list: *CommandList, command: *Command) void {
                if (list.head == null) {
                    std.debug.assert(list.tail == null);
                    list.head = command;
                    list.tail = command;
                } else {
                    std.debug.assert(list.tail != null);
                    list.tail.?.next = command;
                    list.tail = command;
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
            return world;
        }

        pub fn destroy(world: *_World) void {
            world.pages.deinit(world.pool.gpa);
            world.map.deinit(world.pool.gpa);
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
            return .{ .arena = arena, .keygen = world.keygen };
        }

        pub fn submit(world: *_World, command_lists: []const CommandList) !void {
            // NOTE idempotent design allows rerunning a submit twice with no extra effect
            // which makes error recovery easy, just redo the submit after fixing the oom
            for (command_lists) |command_list| {
                var walk: ?*CommandList.Command = command_list.head;
                while (walk) |command| : (walk = command.next) {
                    const key = command.key;
                    switch (command.command) {
                        .create => {
                            if (world.map.contains(key)) continue;

                            const command_record: *CommandList.CommandRecord =
                                @fieldParentPtr("command", command);
                            const record = command_record.record;

                            try world.map.ensureUnusedCapacity(world.pool.gpa, 1);
                            var set = ComponentSet.initEmpty();
                            inline for (std.meta.fields(Record), 0..) |field, i| {
                                if (@field(record, field.name) != null) set.insert(
                                    @as(Component, @enumFromInt(i)),
                                );
                            }
                            const page = try world.getPage(set);
                            const index = page.append(key, command_record.record);
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
                            const command_component: *CommandList.CommandComponent =
                                @fieldParentPtr("command", command);
                            switch (command_component.component) {
                                inline else => |c| {
                                    const command_insert: *CommandList.CommandInsert(c) =
                                        @fieldParentPtr("command", command_component);

                                    // insert into nonexisting is noop
                                    const location = world.map.get(key) orelse continue;
                                    // double insert is noop
                                    if (location.page.hasComponent(c)) continue;
                                    var set = location.page.componentSet();
                                    set.insert(c);
                                    const page = try world.getPage(set);
                                    var record = location.record();
                                    @field(record, @tagName(c)) = command_insert.value;
                                    const index = page.append(key, record);
                                    world.map.putAssumeCapacity(
                                        key,
                                        .{ .page = page, .index = index },
                                    );
                                    const moved = location.page.erase(location.index);
                                    if (moved != .nil) world.map.putAssumeCapacity(
                                        moved,
                                        .{ .page = location.page, .index = location.index },
                                    );
                                },
                            }
                        },
                        .remove => {
                            const command_component: *CommandList.CommandComponent =
                                @fieldParentPtr("command", command);
                            switch (command_component.component) {
                                inline else => |c| {
                                    // double remove is a noop
                                    const location = world.map.get(key) orelse continue;

                                    if (!location.page.hasComponent(c)) continue;
                                    var set = location.page.componentSet();
                                    set.remove(c);
                                    const page = try world.getPage(set);
                                    var record = location.record();
                                    @field(record, @tagName(c)) = null;
                                    const index = page.append(key, record);
                                    world.map.putAssumeCapacity(key, .{ .page = page, .index = index });
                                    const moved = location.page.erase(location.index);
                                    if (moved != .nil) world.map.putAssumeCapacity(
                                        moved,
                                        .{ .page = location.page, .index = location.index },
                                    );
                                },
                            }
                        },
                    }
                }
            }
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
    var arena_impl: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const W = World(struct { x: i32, y: f32 });
    var pool = BlockPool.init(std.testing.allocator);
    defer pool.deinit();
    var seed: u64 = undefined;
    std.testing.io.random(std.mem.asBytes(&seed));
    var keygen: KeyGen = .init(seed);

    const world: *W = try .create(&pool, &keygen);
    defer world.destroy();

    var q = world.acquire(arena);
    const e0 = try q.create(.{});
    const e1 = try q.create(.{ .x = 1 });
    const e2 = try q.create(.{ .y = 2.5 });
    const e3 = try q.create(.{ .x = 3, .y = 3.5 });
    try world.submit(&.{q});

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

    q = world.acquire(arena);
    try q.insert(e0, .x, 99);
    try q.insert(e0, .y, 99.5);
    try q.remove(e1, .x);
    try q.insert(e1, .y, 999.5);
    try q.insert(e2, .x, 999);
    try q.remove(e2, .y);
    try q.remove(e3, .x);
    try q.remove(e3, .y);
    try world.submit(&.{q});

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

    q = world.acquire(arena);
    try q.destroy(e0);
    try q.destroy(e1);
    try q.destroy(e2);
    try q.destroy(e3);
    try world.submit(&.{q});

    // it = world.entityIterator(.{});
    // while (it.next()) |e| std.debug.print("{} {}\n", .{ e.key(), e.record() });

    try std.testing.expectEqual(null, world.entity(e0));
    try std.testing.expectEqual(null, world.entity(e1));
    try std.testing.expectEqual(null, world.entity(e2));
    try std.testing.expectEqual(null, world.entity(e3));
}
