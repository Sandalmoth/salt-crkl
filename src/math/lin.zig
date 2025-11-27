const std = @import("std");

// the linear algebra part here is influenced by zmath
// zmath is available at https://github.com/zig-gamedev/zmath under the MIT license (2025-11-27)

pub const Vec32 = @Vector(4, f32);
pub const Vec64 = @Vector(4, f64);

pub const Quat32 = struct {
    data: @Vector(4, f32),

    pub const identity: Quat32 = .{ 0, 0, 0, 1 };
};

pub const Mat32 = struct {
    data: [4]@Vector(4, f32),

    pub const identity: Mat32 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };

    pub fn perspective(fovy: f32, aspect: f32, near: f32) Mat32 {
        const s = @sin(0.5 * fovy);
        const c = @cos(0.5 * fovy);

        std.debug.assert(near > 0.0);
        std.debug.assert(!std.math.approxEqAbs(f32, s, 0.0, 0.001));
        std.debug.assert(!std.math.approxEqAbs(f32, aspect, 0.0, 0.001));

        const h = c / s;
        const w = h / aspect;
        return .{
            vec4f(w, 0.0, 0.0, 0.0),
            vec4f(0.0, h, 0.0, 0.0),
            vec4f(0.0, 0.0, 0.0, -1.0),
            vec4f(0.0, 0.0, near, 0.0),
        };
    }
};

pub fn vec3f(x: f32, y: f32, z: f32) Vec32 {
    return .{ x, y, z, 0.0 };
}

pub fn vec3d(x: f64, y: f64, z: f64) Vec64 {
    return .{ x, y, z, 0.0 };
}

pub fn vec4f(x: f32, y: f32, z: f32, w: f32) Vec32 {
    return .{ x, y, z, w };
}

pub fn vec4d(x: f64, y: f64, z: f64, w: f64) Vec64 {
    return .{ x, y, z, w };
}

// TODO think about the most practical way of doing the generic functions
// this provides at least a decent indication of the error if bad types are provided
// we could also do separate ones for each function for maximum flexibility
// or we could infer based on the first argument, but that will cause f32 -> f64 casting

fn ReturnTypeScalarA(A: type) type {
    return switch (@typeInfo(A)) {
        .vector => |info| info.child,
        else => @compileError("not a vector: " ++ @typeName(A)),
    };
}
fn ReturnTypeVectorA(A: type) type {
    return A;
}

fn ReturnTypeScalarAB(A: type, B: type) type {
    if (A != B) @compileError("type mismatch: " ++ @typeName(A) ++ " " ++ @typeName(B));
    return switch (@typeInfo(A)) {
        .vector => |info| info.child,
        else => @compileError("not a vector: " ++ @typeName(A)),
    };
}
fn ReturnTypeVectorAB(A: type, B: type) type {
    if (A != B) @compileError("type mismatch: " ++ @typeName(A) ++ " " ++ @typeName(B));
    return A;
}

pub fn dot3(a: anytype, b: anytype) ReturnTypeScalarAB(@TypeOf(a), @TypeOf(b)) {
    const x = a * b;
    return x[0] + x[1] + x[2];
}
pub fn dot3s(a: anytype, b: anytype) ReturnTypeVectorAB(@TypeOf(a), @TypeOf(b)) {
    return @splat(dot3(a, b));
}

pub fn lengthSq3(a: anytype) ReturnTypeScalarA(@TypeOf(a)) {
    return dot3(a, a);
}
pub fn lengthSq3s(a: anytype) ReturnTypeVectorA(@TypeOf(a)) {
    return @splat(dot3(a, a));
}

pub fn length3(a: anytype) ReturnTypeScalarA(@TypeOf(a)) {
    return @sqrt(dot3(a, a));
}
pub fn length3s(a: anytype) ReturnTypeVectorA(@TypeOf(a)) {
    return @splat(@sqrt(dot3(a, a)));
}

pub fn normalize3(a: anytype) ReturnTypeVectorA(@TypeOf(a)) {
    const inorm: @TypeOf(a) = @splat(1.0 / length3(a));
    return inorm * a;
}

test "scratch" {
    const a = vec3f(1, 2, 3);
    const b = vec3f(2, 3, 4);
    std.debug.print("{}\n", .{dot3s(a, b)});
    std.debug.print("{}\n", .{@TypeOf(dot3s(a, b))});
    std.debug.print("{}\n", .{lengthSq3s(a)});
    std.debug.print("{}\n", .{@TypeOf(lengthSq3s(a))});
    std.debug.print("{}\n", .{length3s(a)});
    std.debug.print("{}\n", .{@TypeOf(length3s(a))});
    std.debug.print("{}\n", .{dot3(a, b)});
    std.debug.print("{}\n", .{@TypeOf(dot3(a, b))});
    std.debug.print("{}\n", .{lengthSq3(a)});
    std.debug.print("{}\n", .{@TypeOf(lengthSq3(a))});
    std.debug.print("{}\n", .{length3(a)});
    std.debug.print("{}\n", .{@TypeOf(length3(a))});
}
