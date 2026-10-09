const sc = @import("framework");
const std = @import("std");

const sdl = sc.sdl;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var blka_impl: sc.mem.BlockAllocator = .init(gpa);
    defer blka_impl.deinit();
    const blka = blka_impl.allocator();

    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var seed: u32 = undefined;
    io.random(std.mem.asBytes(&seed));
    var keygen: sc.KeyGen = .init(seed);

    try sc.init();
    defer sc.deinit();

    const window = try sdl.createWindow(
        "example-framework",
        800,
        600,
        sdl.c.SDL_WINDOW_RESIZABLE,
    );
    defer sdl.destroyWindow(window);

    var renderer: sc.Renderer = try .init(gpa, blka, window, .{
        .width = 800,
        .height = 600,
    });
    defer renderer.deinit();

    const W = sc.ecs.World(struct { x: u32 });
    var w: W = .init(gpa, blka, &keygen);
    defer w.deinit();

    main_loop: while (true) {
        _ = arena_impl.reset(.retain_capacity);

        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == sdl.c.SDL_EVENT_QUIT) break :main_loop;
            if (event.type == sdl.c.SDL_EVENT_KEY_DOWN) switch (event.key.key) {
                sdl.c.SDLK_ESCAPE => break :main_loop,
                else => {},
            };
        }

        try renderer.draw(arena, &.{});
    }
}
