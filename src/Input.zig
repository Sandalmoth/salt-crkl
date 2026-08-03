const std = @import("std");

const sdl = @import("sdl.zig");
const lin = @import("math").lin;

const Input = @This();

const log = std.log.scoped(.input);

const PhysicalButton = union(enum) {
    const MouseWheelDirection = enum { pos, neg };
    const AxisThreshold = struct { axis: sdl.c.Uint8, direction: enum { pos, neg } };

    mouse: sdl.c.Uint8,
    wheel: MouseWheelDirection,
    key: sdl.c.SDL_Scancode,
    button: sdl.c.Uint8,
    threshold: AxisThreshold,
};

const LogicalButton = enum {
    forward,
    left,
    right,
    backward,
    jump,
    crouch,
};

const ButtonBinding = struct {
    physical: PhysicalButton,
    logical: LogicalButton,
    next_physical: *ButtonBinding,
    next_logical: *ButtonBinding,
};

const ButtonState = struct {
    binding: ?*ButtonBinding = null,

    held: bool = false,
    pressed: bool = false,
    released: bool = false,
    mouse_pos_pressed: lin.V2f = .zero,
    mouse_pos_released: lin.V2f = .zero,
};

const PhysicalAxis = sdl.c.Uint8;

const LogicalAxis = enum {
    left_stick_x,
    left_stick_y,
    right_stick_x,
    right_stick_y,
    left_trigger,
    right_trigger,
};

const AxisBinding = struct {
    physical: PhysicalAxis,
    logical: LogicalAxis,
    next_physical: *AxisBinding,
    next_logical: *AxisBinding,
};

const AxisState = struct {
    binding: ?*AxisBinding = null,
    value: f32 = 0.0,
};

const AxisConfig = struct {
    threshold: f32 = 0.6,
    low: f32 = 0.2,
    high: f32 = 0.9,
    inverted: bool = false,
};

gpa: std.mem.Allocator,

button_binding_pool: std.heap.MemoryPool(ButtonBinding) = .empty,
axis_binding_pool: std.heap.MemoryPool(AxisBinding) = .empty,

button_bindings: std.AutoHashMapUnmanaged(PhysicalButton, *ButtonBinding) = .empty,
axis_bindings: std.AutoHashMapUnmanaged(PhysicalAxis, *AxisBinding) = .empty,

button_states: std.EnumArray(LogicalButton, ButtonState) = .initFill(.{}),
axis_states: std.EnumArray(LogicalAxis, AxisState) = .initFill(.{}),
axis_configs: std.EnumArray(LogicalAxis, AxisConfig) = .initFill(.{}),

mouse_pos: lin.V2f = .zero,
mouse_delta: lin.V2f = .zero,
left_stick: lin.V2f = .zero,
right_stick: lin.V2f = .zero,
left_trigger: f32 = 0.0,
right_trigger: f32 = 0.0,

pub fn init(gpa: std.mem.Allocator) Input {
    return .{
        .gpa = gpa,
    };
}

pub fn deinit(input: *Input) void {
    input.axis_bindings.deinit(input.gpa);
    input.button_bindings.deinit(input.gpa);
    input.axis_binding_pool.deinit(input.gpa);
    input.button_binding_pool.deinit(input.gpa);
    input.* = undefined;
}

pub fn peek(input: Input, logical: LogicalButton) ButtonState {
    return input.button_states.get(logical);
}

pub fn consume(input: *Input, logical: LogicalButton) ButtonState {
    const result = input.states.get(logical);
    const state = input.states.getPtr(logical);
    state.held = false;
    state.pressed = false;
    state.released = false;
    return result;
}

pub fn accumulate(input: *Input, event: sdl.Event) void {
    dispatch: switch (event.type) {
        sdl.c.SDL_EVENT_MOUSE_MOTION => {
            input.mouse_pos = .init(event.motion.x, event.motion.y);
            input.mouse_delta = .add(
                input.mouse_delta,
                .init(event.motion.xrel, event.motion.yrel),
            );
        },
        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN,
        sdl.c.SDL_EVENT_KEY_DOWN,
        sdl.c.SDL_EVENT_GAMEPAD_BUTTON_DOWN,
        => {
            const binding = input.button_bindings.get(switch (event.type) {
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => .{ .mouse = event.button.button },
                sdl.c.SDL_EVENT_KEY_DOWN => .{ .key = event.key.scancode },
                sdl.c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => .{ .button = event.button.button },
                else => break :dispatch,
            }) orelse break :dispatch;
            var b = binding;
            while (true) {
                const state = input.button_states.getPtr(b.logical);
                state.held = true;
                if (!state.pressed) state.mouse_pos_pressed = input.mouse_pos;
                state.pressed = true;

                b = b.next_logical;
                if (b == binding) break;
            }
        },
        sdl.c.SDL_EVENT_MOUSE_BUTTON_UP,
        sdl.c.SDL_EVENT_KEY_UP,
        sdl.c.SDL_EVENT_GAMEPAD_BUTTON_UP,
        => {
            const binding = input.button_bindings.get(switch (event.type) {
                sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => .{ .mouse = event.button.button },
                sdl.c.SDL_EVENT_KEY_UP => .{ .key = event.key.scancode },
                sdl.c.SDL_EVENT_GAMEPAD_BUTTON_UP => .{ .button = event.button.button },
                else => break :dispatch,
            }) orelse break :dispatch;
            var b = binding;
            while (true) {
                const state = input.button_states.getPtr(b.logical);
                state.held = false;
                state.mouse_pos_released = input.mouse_pos;
                state.released = true;

                b = b.next_logical;
                if (b == binding) break;
            }
        },
        sdl.c.SDL_EVENT_MOUSE_WHEEL => {
            if (event.wheel.integer_y == 0) break :dispatch;
            const dir: PhysicalButton.MouseWheelDirection =
                if (event.wheel.integer_y < 0) .neg else .pos;
            const binding = input.button_bindings.get(
                .{ .wheel = dir },
            ) orelse break :dispatch;
            var b = binding;
            while (true) {
                const state = input.button_states.getPtr(b.logical);
                if (!state.pressed) state.mouse_pos_pressed = input.mouse_pos;
                state.mouse_pos_released = input.mouse_pos;
                state.pressed = true;
                state.released = true;

                b = b.next_logical;
                if (b == binding) break;
            }
        },
        sdl.c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
            const binding = input.axis_bindings.get(event.gaxis.axis) orelse break :dispatch;
            var b = binding;
            while (true) {
                const state = input.axis_states.getPtr(b.logical);
                const config = input.axis_configs.get(b.logical);
                const v: f32 = @floatFromInt(event.gaxis.value);
                const min: f32 = comptime -@as(f32, @floatFromInt(sdl.c.SDL_JOYSTICK_AXIS_MIN));
                const max: f32 = comptime @as(f32, @floatFromInt(sdl.c.SDL_JOYSTICK_AXIS_MAX));
                const prev_value = state.value;
                state.value = if (event.gaxis.value < 0) v / min else v / max;
                if (config.inverted) state.value = -state.value;
                // also trigger an axis threshold pressed/released event
                if (prev_value < config.threshold and state.value >= config.threshold) {
                    const binding2 = input.button_bindings.get(.{ .threshold = .{
                        .axis = event.gaxis.axis,
                        .direction = if (event.gaxis.value < 0) .neg else .pos,
                    } }) orelse break :dispatch;
                    var b2 = binding2;
                    while (true) {
                        const state2 = input.button_states.getPtr(b2.logical);
                        state2.held = true;
                        if (!state2.pressed) state2.mouse_pos_pressed = input.mouse_pos;
                        state2.pressed = true;

                        b2 = b2.next_logical;
                        if (b2 == binding2) break;
                    }
                } else if (prev_value >= config.threshold and state.value < config.threshold) {
                    const binding2 = input.button_bindings.get(.{ .threshold = .{
                        .axis = event.gaxis.axis,
                        .direction = if (event.gaxis.value < 0) .neg else .pos,
                    } }) orelse break :dispatch;
                    var b2 = binding2;
                    while (true) {
                        const state2 = input.button_states.getPtr(b2.logical);
                        state2.held = false;
                        state2.mouse_pos_released = input.mouse_pos;
                        state2.released = true;

                        b2 = b2.next_logical;
                        if (b2 == binding2) break;
                    }
                }

                b = b.next_logical;
                if (b == binding) break;
            }
        },
        else => {},
    }
}

pub fn decay(input: *Input) void {
    input.mouse_delta = @splat(0.0);
    var it = input.button_states.iterator();
    while (it.next()) |kv| {
        kv.value.pressed = false;
        kv.value.released = false;
    }
}

fn clampSingle(state: AxisState, config: AxisConfig) f32 {
    if (@abs(state.value) < config.low) return 0.0;
    if (@abs(state.value) > config.high) return std.math.sign(state.value);
    return if (state.value < 0)
        (state.value + config.low) / (config.high - config.low)
    else
        (state.value - config.low) / (config.high - config.low);
}
pub fn finalize(input: *Input) void {
    input.left_trigger = clampSingle(
        input.axis_states.get(.left_trigger),
        input.axis_configs.get(.left_trigger),
    );
    input.right_trigger = clampSingle(
        input.axis_states.get(.right_trigger),
        input.axis_configs.get(.right_trigger),
    );
    input.left_stick = lin.vec2f(
        clampSingle(input.axis_states.get(.left_stick_x), input.axis_configs.get(.left_stick_x)),
        clampSingle(input.axis_states.get(.left_stick_y), input.axis_configs.get(.left_stick_y)),
    );
    input.right_stick = lin.vec2f(
        clampSingle(input.axis_states.get(.right_stick_x), input.axis_configs.get(.right_stick_x)),
        clampSingle(input.axis_states.get(.right_stick_y), input.axis_configs.get(.right_stick_y)),
    );
}

pub fn bindButton(input: *Input, physical: PhysicalButton, logical: LogicalButton) !void {
    const new_binding = try input.button_binding_pool.create(input.gpa);
    errdefer input.button_binding_pool.destroy(new_binding);
    new_binding.physical = physical;
    new_binding.logical = logical;
    new_binding.next_physical = undefined; // TODO (mostly usedful for ui)
    if (input.button_bindings.get(physical)) |old_binding| {
        new_binding.next_logical = old_binding.next_logical;
        old_binding.next_logical = new_binding;
    } else {
        new_binding.next_logical = new_binding;
        try input.button_bindings.put(input.gpa, physical, new_binding);
    }
}

pub fn bindAxis(input: *Input, physical: PhysicalAxis, logical: LogicalAxis) !void {
    const new_binding = try input.axis_binding_pool.create(input.gpa);
    errdefer input.axis_binding_pool.destroy(new_binding);
    new_binding.physical = physical;
    new_binding.logical = logical;
    new_binding.next_physical = undefined; // TODO (mostly usedful for ui)
    if (input.axis_bindings.get(physical)) |old_binding| {
        new_binding.next_logical = old_binding.next_logical;
        old_binding.next_logical = new_binding;
    } else {
        new_binding.next_logical = new_binding;
        try input.axis_bindings.put(input.gpa, physical, new_binding);
    }
}
