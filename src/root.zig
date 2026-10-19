const std = @import("std");

pub const spiral = @import("spiral");
pub const defines = @import("defines.zig");
pub const sdl = @import("sdl.zig");
pub const Renderer = @import("renderer.zig");

pub const KeyGen = @import("keygen").KeyGen;

pub const ecs = struct {
    pub const raw = @import("ecs");
    pub const Key = raw.Key;

    pub fn World(comptime Spec: type) type {
        return raw.World(.{ .block_size = defines.block_size }, Spec);
    }
};

pub const mem = struct {
    pub const raw = @import("mem");
    pub const BlockAllocator = raw.BlockAllocator(.{ .block_size = defines.block_size });
};

pub const Config = struct {
    window: struct {
        width: u32,
        height: u32,
    },
};

pub const Context = struct {
    gpa: std.mem.Allocator,
    blka_impl: mem.BlockAllocator,
    blka: std.mem.Allocator,

    io_impl: std.Io.Threaded,
    io: std.Io,

    storage: *spiral.Storage,

    window: *sdl.Window,
    renderer: Renderer,

    keygen: KeyGen,

    pub fn init(
        ctx: *Context,
        gpa: std.mem.Allocator,
        config: Config,
    ) !void {
        ctx.blka_impl = .init(gpa);
        errdefer ctx.blka_impl.deinit();
        ctx.blka = ctx.blka_impl.allocator();

        ctx.io_impl = .init(gpa, .{});
        ctx.io = ctx.io_impl.io();

        sdl.setMainReady();

        try sdl.init(sdl.c.SDL_INIT_VIDEO);
        errdefer sdl.quit();

        ctx.window = try sdl.createWindow(
            "example-framework",
            @intCast(config.window.width),
            @intCast(config.window.height),
            sdl.c.SDL_WINDOW_RESIZABLE,
        );
        errdefer sdl.destroyWindow(ctx.window);

        ctx.storage = try .init(gpa, ctx.io, .{});

        try ctx.renderer.init(gpa, ctx.blka, ctx.io, ctx.window, .{
            .width = config.window.width,
            .height = config.window.height,
        }, ctx.storage);
        errdefer ctx.renderer.deinit();

        var seed: u32 = undefined;
        ctx.io.random(std.mem.asBytes(&seed));
        ctx.keygen = .init(seed);
    }

    pub fn deinit(ctx: *Context) void {
        ctx.renderer.deinit();
        sdl.destroyWindow(ctx.window);
        sdl.quit();
    }
};
