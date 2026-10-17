const sc = @import("framework");
const std = @import("std");

const sdl = sc.sdl;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var arena_impl: std.heap.ArenaAllocator = .init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var ctx: sc.Context = undefined;
    try ctx.init(gpa, .{
        .window = .{ .width = 800, .height = 600 },
    });
    defer ctx.deinit();

    const W = sc.ecs.World(struct { x: u32 });
    var w: W = .init(gpa, ctx.blka, &ctx.keygen);
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

        try ctx.renderer.draw(arena, &.{});
    }
}
