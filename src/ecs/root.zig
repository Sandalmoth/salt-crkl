const std = @import("std");

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

        pub fn PageView(comptime raw_query: RawQuery) type {
            return struct {
                const _PageView = @This();
                const query = raw_query.reify();

                page: *Page,
            };
        }

        pub fn EntityView(comptime raw_query: RawQuery) type {
            return struct {
                const _EntityView = @This();
                const query = raw_query.reify();

                page: *Page,
                index: usize,
            };
        }

        pub const World = struct {};
        pub const Page = struct {};
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

        gpa: std.mem.Allocator,
        keygen: KeyGenerator,

        pages: std.MultiArrayList(PageInfo), // first cache_size slots form fifo cache
        map: std.AutoHashMap(Key, EntityView(.{})),
    };
}
