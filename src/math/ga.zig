const std = @import("std");

/// geometric algebra point (i.e. a position in space)
pub const Point = struct {
    // x    y    z    w
    // e032 e013 e021 e123
    // w != 0
    data: @Vector(4, f32),
};

/// geometric algebra direction (i.e. a direction with magnitude)
pub const Dir = struct {
    // x    y    z    w
    // e032 e013 e021 e123
    // w == 0
    data: @Vector(4, f32),
};

/// geometric algebra line
pub const Line = struct {
    // s   e01 e02 e03
    // e12 e31 e23  ps
    data: [2]@Vector(4, f32),
};

/// geometric algebra plane
pub const Plane = struct {
    // x  y  z
    // e1 e2 e3 e0
    data: @Vector(4, f32),

    /// a plane with normal (x y z) at a given distance from the origin
    /// the vector (x y z) will be normalized and does not affect the distance
    pub fn fromNormalDistance(x: f32, y: f32, z: f32, delta: f32) Plane {
        const n = 1.0 / @sqrt(x * x + y * y + z * z);
        return .{ .data = @Vector(4, f32){ x * n, y * n, z * n, -delta } };
    }
};

/// geometric algebra motor (i.e. a transform representing translation and rotation)
/// for simplicity, also used to represent pure translators and rotors
pub const Motor = struct {
    // s   e01 e02 e03
    //     ~dx ~dy ~dz translation
    // e12 e31 e23  ps
    // z   y   x       rotation axis
    data: [2]@Vector(4, f32),

    /// a translation of delta along the normalized vector (x y z)
    /// the vector (x y z) will be normalized and does not affect the distance
    pub fn fromDirectionDistance(x: f32, y: f32, z: f32, delta: f32) Motor {
        const n = -0.5 * delta / @sqrt(x * x + y * y + z * z);
        return .{ .data = .{
            @Vector(4, f32){ 1, x, y, z } * @Vector(4, f32){ 1, n, n, n },
            @Vector(4, f32){ 0, 0, 0, 0 },
        } };
    }

    /// a rotation by rad radians around the axis (x y z)
    pub fn fromAxisAngle(x: f32, y: f32, z: f32, rad: f32) Motor {
        const norm = @sqrt(x * x + y * y + z * z);
        const half = 0.5 * rad;
        // TODO switch implementation when zig exposes sincos
        const s = @sin(half);
        const c = @cos(half);
        const scale = s / norm;
        return .{ .data = .{
            @Vector(4, f32){ c, 0, 0, 0 },
            @Vector(4, f32){ z, y, x, 0 } * @as(@Vector(4, f32), @splat(scale)),
        } };
    }
};

/// a point in space
pub fn point(x: f32, y: f32, z: f32) Point {
    return .{ .data = .{ x, y, z, 1.0 } };
}

/// a direction (i.e. an ideal point)
pub fn dir(x: f32, y: f32, z: f32) Dir {
    return .{ .data = .{ x, y, z, 0.0 } };
}

// not sure if there are a good idea, seems like constructing via joins is better?
// pub fn line(x0: f32, y0: f32, z0: f32, x1: f32, y1: f32, z1: f32) Line {
//     return join(point(x0, y0, z0), point(x1, y1, z1));
// }
// pub fn plane() Plane {}
// pub fn motor() Motor {}

fn normalizeReturnType(A: type) type {
    if (A == Point) return Point;
    if (A == Dir) return Dir;
    if (A == Plane) return Plane;
}
pub fn normalize(a: anytype) normalizeReturnType(@TypeOf(a)) {
    const A = @TypeOf(a);
    if (A == Point) return normalizePoint(a);
    if (A == Dir) return normalizeDir(a);
    if (A == Plane) return normalizePlane(a);
    @compileError("normalize not supported for types " ++ @typeName(A));
}

fn dualReturnType(A: type) type {
    _ = A;
}
pub fn dual(a: anytype) dualReturnType(@TypeOf(a)) {
    const A = @TypeOf(a);
    @compileError("dual not supported for types " ++ @typeName(A));
}

fn reverseReturnType(A: type) type {
    _ = A;
}
pub fn reverse(a: anytype) reverseReturnType(@TypeOf(a)) {
    const A = @TypeOf(a);
    @compileError("reverse not supported for types " ++ @typeName(A));
}

// fn xxxReturnType(A: type) type {
//     _ = A;
// }
// pub fn xxx(a: anytype) xxxReturnType(@TypeOf(a)) {
// const A = @TypeOf(a);
// @compileError("xxx not supported for types " ++ @typeName(A));
// }

fn applyReturnType(A: type, B: type) type {
    if (A == Motor and B == Point) return Point;
    if (A == Motor and B == Dir) return Dir;
    if (A == Motor and B == Line) return Line; // TODO
    if (A == Motor and B == Plane) return Plane; // TODO
}
pub fn apply(a: anytype, b: anytype) applyReturnType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == Motor and B == Point) return applyMotorPoint(a, b);
    if (A == Motor and B == Dir) return applyMotorDir(a, b);
    @compileError("apply not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
}

fn composeReturnType(A: type, B: type) type {
    if (A == Motor and B == Motor) return Motor;
}
pub fn compose(a: anytype, b: anytype) composeReturnType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == Motor and B == Motor) return composeMotorMotor(a, b);
    @compileError("compose not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
}

fn intersectReturnType(A: type, B: type) type {
    if (A == Plane and B == Plane) return Line; // TODO
    if ((A == Plane and B == Line) or (A == Line and B == Plane)) return Point; // TODO
}
pub fn intersect(a: anytype, b: anytype) intersectReturnType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == Plane and B == Plane) return intersectPlanePlane(a, b);
    if (A == Plane and B == Line) return intersectPlaneLine(a, b);
    if (A == Line and B == Plane) return intersectPlaneLine(b, a);
    @compileError("intersect not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
}

fn joinReturnType(A: type, B: type) type {
    if (A == Point and B == Point) return Line;
    if ((A == Point and B == Line) or (A == Line and B == Point)) return Plane;
}
pub fn join(a: anytype, b: anytype) joinReturnType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A == Point and B == Point) return joinPointPoint(a, b);
    if (A == Point and B == Line) return joinPointLine(a, b);
    if (A == Line and B == Point) return joinPointLine(b, a); // commutative
    @compileError("join not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
}

fn projectReturnType(A: type, B: type) type {
    _ = A;
    _ = B;
}
pub fn project(a: anytype, b: anytype) projectReturnType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    @compileError("project not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
}

// fn xxxReturnType(A: type, B: type) type {
//     _ = A;
//     _ = B;
// }
// pub fn xxx(a: anytype, b: anytype) xxxReturnType(@TypeOf(a), @TypeOf(b)) {
// const A = @TypeOf(a);
// const B = @TypeOf(b);
// @compileError("xxx not supported for types " ++ @typeName(A) ++ " " ++ @typeName(B));
// }

pub fn normalizePoint(a: Point) Point {
    std.debug.assert(a.data[3] != 0.0);
    const n = 1.0 / a.data[3];
    return .{ .data = a.data * @as(@Vector(4, f32), @splat(n)) };
}

pub fn normalizeDir(a: Dir) Dir {
    std.debug.assert(a.data[3] == 0.0);
    const n = 1.0 / @sqrt(@reduce(.Add, a.data * a.data));
    return .{ .data = a.data * @as(@Vector(4, f32), @splat(n)) };
}

pub fn normalizePlane(a: Plane) Plane {
    const a_123: @Vector(3, f32) = .{ a.data[0], a.data[1], a.data[2] };
    const n = 1.0 / @sqrt(@reduce(.Add, a_123 * a_123));
    return .{ .data = a.data * @as(@Vector(4, f32), @splat(n)) };
}

fn applyMotorPoint(a: Motor, b: Point) Point {
    const a_s_ = a.data[0][0];
    const a_01 = a.data[0][1];
    const a_02 = a.data[0][2];
    const a_03 = a.data[0][3];
    const a_12 = a.data[1][0];
    const a_31 = a.data[1][1];
    const a_23 = a.data[1][2];
    const a_ps = a.data[1][3];
    const b_032 = b.data[0];
    const b_013 = b.data[1];
    const b_021 = b.data[2];
    const b_123 = b.data[3];

    return .{
        .data = .{
            2 * a_s_ * a_12 * b_013 + 2 * a_03 * a_31 * b_123 + 2 * a_12 * a_23 * b_021 +
                2 * a_31 * a_23 * b_013 + b_032 - 2 * a_23 * a_ps * b_123 -
                2 * a_31 * a_31 * b_032 - 2 * a_12 * a_12 * b_032 -
                2 * a_02 * a_12 * b_123 - 2 * a_s_ * a_31 * b_021 - 2 * a_s_ * a_01 * b_123,
            2 * a_s_ * a_23 * b_021 + 2 * a_01 * a_12 * b_123 + 2 * a_12 * a_31 * b_021 +
                2 * a_31 * a_23 * b_032 + b_013 - 2 * a_23 * a_23 * b_013 -
                2 * a_31 * a_ps * b_123 - 2 * a_12 * a_12 * b_013 -
                2 * a_03 * a_23 * b_123 - 2 * a_s_ * a_12 * b_032 - 2 * a_s_ * a_02 * b_123,
            2 * a_s_ * a_31 * b_032 + 2 * a_02 * a_23 * b_123 + 2 * a_12 * a_31 * b_013 +
                2 * a_12 * a_23 * b_032 + b_021 - 2 * a_23 * a_23 * b_021 -
                2 * a_31 * a_31 * b_021 - 2 * a_12 * a_ps * b_123 -
                2 * a_01 * a_31 * b_123 - 2 * a_s_ * a_23 * b_013 - 2 * a_s_ * a_03 * b_123,
            b_123,
        },
    };
}

fn applyMotorDir(a: Motor, b: Dir) Dir {
    // a simplified version of applyMotorPoint
    const a_s_ = a.data[0][0];
    const a_12 = a.data[1][0];
    const a_31 = a.data[1][1];
    const a_23 = a.data[1][2];
    const b_032 = b.data[0];
    const b_013 = b.data[1];
    const b_021 = b.data[2];
    // const b_123 = b.data[3] == 0; <-- allows for some terms to be removed

    return .{
        .data = .{
            2 * a_s_ * a_12 * b_013 + 2 * a_12 * a_23 * b_021 +
                2 * a_31 * a_23 * b_013 + b_032 -
                2 * a_31 * a_31 * b_032 - 2 * a_12 * a_12 * b_032 -
                2 * a_s_ * a_31 * b_021,
            2 * a_s_ * a_23 * b_021 + 2 * a_12 * a_31 * b_021 +
                2 * a_31 * a_23 * b_032 + b_013 - 2 * a_23 * a_23 * b_013 -
                2 * a_12 * a_12 * b_013 -
                2 * a_s_ * a_12 * b_032,
            2 * a_s_ * a_31 * b_032 + 2 * a_12 * a_31 * b_013 +
                2 * a_12 * a_23 * b_032 + b_021 - 2 * a_23 * a_23 * b_021 -
                2 * a_31 * a_31 * b_021 -
                2 * a_s_ * a_23 * b_013,
            0,
        },
    };
}

fn composeMotorMotor(a: Motor, b: Motor) Motor {
    // NOTE this composes as "first a then b"
    const a_s_ = a.data[0][0];
    const a_01 = a.data[0][1];
    const a_02 = a.data[0][2];
    const a_03 = a.data[0][3];
    const a_12 = a.data[1][0];
    const a_31 = a.data[1][1];
    const a_23 = a.data[1][2];
    const a_ps = a.data[1][3];
    const b_s_ = b.data[0][0];
    const b_01 = b.data[0][1];
    const b_02 = b.data[0][2];
    const b_03 = b.data[0][3];
    const b_12 = b.data[1][0];
    const b_31 = b.data[1][1];
    const b_23 = b.data[1][2];
    const b_ps = b.data[1][3];

    return .{
        .data = .{
            .{
                b_s_ * a_s_ - b_23 * a_23 - b_31 * a_31 - b_12 * a_12,
                b_s_ * a_01 + b_01 * a_s_ + b_03 * a_31 + b_12 * a_02 - b_ps * a_23 -
                    b_23 * a_ps - b_31 * a_03 - b_02 * a_12,
                b_s_ * a_02 + b_01 * a_12 + b_02 * a_s_ + b_23 * a_03 - b_ps * a_31 -
                    b_31 * a_ps - b_12 * a_01 - b_03 * a_23,
                b_s_ * a_03 + b_02 * a_23 + b_03 * a_s_ + b_31 * a_01 - b_ps * a_12 -
                    b_23 * a_02 - b_12 * a_ps - b_01 * a_31,
            },
            .{
                b_s_ * a_12 + b_12 * a_s_ + b_31 * a_23 - b_23 * a_31,
                b_s_ * a_31 + b_31 * a_s_ + b_23 * a_12 - b_12 * a_23,
                b_s_ * a_23 + b_12 * a_31 + b_23 * a_s_ - b_31 * a_12,
                b_s_ * a_ps + b_01 * a_23 + b_02 * a_31 + b_03 * a_12 + b_12 * a_03 +
                    b_31 * a_02 + b_23 * a_01 + b_ps * a_s_,
            },
        },
    };
}

fn joinPointPoint(a: Point, b: Point) Line {
    const ax = a.data[0];
    const ay = a.data[1];
    const az = a.data[2];
    const aw = a.data[3];
    const bx = b.data[0];
    const by = b.data[1];
    const bz = b.data[2];
    const bw = b.data[3];

    return .{ .data = .{
        .{
            0,
            ay * bz - by * az,
            bx * az - ax * bz,
            ax * by - bx * ay,
        },
        .{
            aw * bz - az * bw,
            aw * by - ay * bw,
            aw * bx - ax * bw,
            0,
        },
    } };
}

fn joinPointLine(a: Point, b: Line) Plane {
    const a_032 = a.data[0];
    const a_013 = a.data[1];
    const a_021 = a.data[2];
    const a_123 = a.data[3];
    // const b_s_ = b.data[0][0]; == 0
    const b_01 = b.data[0][1];
    const b_02 = b.data[0][2];
    const b_03 = b.data[0][3];
    const b_12 = b.data[1][0];
    const b_31 = b.data[1][1];
    const b_23 = b.data[1][2];
    // const b_ps = b.data[1][3]; == 0

    return .{ .data = .{
        b_01 * a_123 + b_31 * a_021 - b_12 * a_013,
        b_02 * a_123 + b_12 * a_032 - b_23 * a_021,
        b_03 * a_123 + b_23 * a_013 - b_31 * a_032,
        -b_03 * a_021 - b_02 * a_013 - b_01 * a_032,
    } };
}

fn intersectPlanePlane(a: Plane, b: Plane) Line {
    const a_1, const a_2, const a_3, const a_0 = a.data;
    const b_1, const b_2, const b_3, const b_0 = b.data;

    return .{ .data = .{
        .{
            0,
            a_3 * b_0 - a_0 * b_3,
            a_3 * b_1 - a_1 * b_3,
            a_3 * b_2 - a_2 * b_3,
        },
        .{
            a_0 * b_1 - a_1 * b_0,
            a_2 * b_0 - a_0 * b_2,
            a_1 * b_2 - a_2 * b_1,
            0,
        },
    } };
}

fn intersectPlaneLine(a: Plane, b: Line) Point {
    const a_1, const a_2, const a_3, const a_0 = a.data;
    // const b_s_ = b.data[0][0]; == 0
    const b_01 = b.data[0][1];
    const b_02 = b.data[0][2];
    const b_03 = b.data[0][3];
    const b_12 = b.data[1][0];
    const b_31 = b.data[1][1];
    const b_23 = b.data[1][2];
    // const b_ps = b.data[1][3]; == 0

    return .{
        .data = .{
            b_01 * a_2 - b_31 * a_3 - b_03 * a_0,
            b_02 * a_0 - b_12 * a_3 - b_01 * a_1,
            b_12 * a_2 + b_31 * a_1 + b_23 * a_0,
            b_03 * a_1 - b_23 * a_3 - b_02 * a_2,
        },
    };
}

test "transformations" {
    const p = point(-1, 0, 2);

    const m0: Motor = .fromDirectionDistance(3, -4, 0, 5);
    const p0 = apply(m0, p);

    const m1: Motor = .fromAxisAngle(0, 1, 0, 0.5 * std.math.pi);
    const p1 = apply(m1, p);

    const m2 = compose(m0, m1);
    const p2 = apply(m2, p);

    const m3 = compose(m1, m0);
    const p3 = apply(m3, p);

    try std.testing.expect(approxEqAbs(p0.data, .{ 2, -4, 2, 1 }, 1e-6));
    try std.testing.expect(approxEqAbs(p1.data, .{ -2, 0, -1, 1 }, 1e-6));
    try std.testing.expect(approxEqAbs(p2.data, .{ -2, -4, 2, 1 }, 1e-6));
    try std.testing.expect(approxEqAbs(p3.data, .{ 1, -4, -1, 1 }, 1e-6));
}

test "joins" {
    const p0 = point(1, 0, 0);
    const p1 = point(0, 1, 0);
    const p2 = point(0, 0, 1);

    // it seems like if i scle the data in a point by a negative number
    // the orientation of the resulting plane changes
    // but i thought that homogenous coordinates meant scaling has no effect?

    const iq3 = 1.0 / @sqrt(3.0);
    try std.testing.expect(
        approxEqAbs(normalize(join(join(p0, p1), p2)).data, .{ iq3, iq3, iq3, -iq3 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(join(p0, join(p1, p2))).data, .{ iq3, iq3, iq3, -iq3 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(join(join(p2, p1), p0)).data, .{ -iq3, -iq3, -iq3, iq3 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(join(p2, join(p1, p0))).data, .{ -iq3, -iq3, -iq3, iq3 }, 1e-6),
    );
}

test "intersects" {
    const s0: Plane = .fromNormalDistance(1, 0, 0, 2);
    const s1: Plane = .fromNormalDistance(0, 1, 0, 3);
    const s2: Plane = .fromNormalDistance(0, 0, 1, 4);

    try std.testing.expect(
        approxEqAbs(normalize(intersect(intersect(s0, s1), s2)).data, .{ 2, 3, 4, 1 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(intersect(s0, intersect(s1, s2))).data, .{ 2, 3, 4, 1 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(intersect(intersect(s2, s1), s0)).data, .{ 2, 3, 4, 1 }, 1e-6),
    );
    try std.testing.expect(
        approxEqAbs(normalize(intersect(s2, intersect(s1, s0))).data, .{ 2, 3, 4, 1 }, 1e-6),
    );
}

fn approxEqAbs(a: @Vector(4, f32), b: @Vector(4, f32), tol: f32) bool {
    for (0..4) |i| {
        if (!std.math.approxEqAbs(f32, a[i], b[i], tol)) {
            return false;
        }
    }
    return true;
}
