const std = @import("std");

pub fn v2f(x: f32, y: f32) V2f {
    return .{ .data = .{ x, y } };
}

pub const V2f = struct {
    data: @Vector(2, f32),

    pub const zero: V2f = .{ .data = @splat(0) };

    pub fn splat(s: f32) V2f {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [2]f32) V2f {
        return .{ .data = a };
    }
    pub fn store(v: V2f, a: *[2]f32) V2f {
        a.* = v.data;
    }

    pub fn v3f(v: V2f, _z: f32) V3f {
        return .{ .data = .{ v.data[0], v.data[1], _z } };
    }
    pub fn v4f(v: V2f, _z: f32, _w: f32) V4f {
        return .{ .data = .{ v.data[0], v.data[1], _z, _w } };
    }
    pub fn v2d(v: V2f) V2d {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V2f) V2f {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V2f) V2f {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V2f) f32 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V2f) f32 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V2f) f32 {
        const inorm: @Vector(2, f32) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V2f, b: V2f) V2f {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V2f, b: V2f) V2f {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V2f, b: V2f) V2f {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V2f, b: V2f) V2f {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V2f, b: V2f) V2f {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }

    pub fn lerp(a: V2f, b: V2f, t: V2f) V2f {
        return .{ .data = (@as(@Vector(2, f32), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V2f) f32 {
        return v.data[0];
    }
    pub fn y(v: V2f) f32 {
        return v.data[1];
    }

    pub fn xx(v: V2f) V2f {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V2f) V2f {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn yx(v: V2f) V2f {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V2f) V2f {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }

    pub fn xxx(v: V2f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V2f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xyx(v: V2f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V2f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxx(v: V2f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V2f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyx(v: V2f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V2f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }

    pub fn xxxx(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxyx(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyxx(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyyx(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V2f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yxxx(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxyx(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yyxx(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyyx(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V2f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
};

pub const M2f = struct {
    data: [2]@Vector(2, f32),

    pub const zero: M2f = .{ .data = .{
        .{ 0, 0 },
        .{ 0, 0 },
    } };
    pub const eye: M2f = .{ .data = .{
        .{ 1, 0 },
        .{ 0, 1 },
    } };


    pub fn transpose(m: M2f) M2f {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0] },
            .{ m.data[0][1], m.data[1][1] },
        } };
    }

    pub fn mulmat(a: M2f, b: M2f) M2f {
        const t = b.transpose();
        var c: M2f = undefined;
        for (0..2) |i| {
            for (0..2) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M2f, v: V2f) V2f {
        var w: V2f = undefined;
        for (0..2) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub fn v3f(x: f32, y: f32, z: f32) V3f {
    return .{ .data = .{ x, y, z } };
}

pub const V3f = struct {
    data: @Vector(3, f32),

    pub const zero: V3f = .{ .data = @splat(0) };
    pub const up: V3f = .{ .data = .{ 0, 1, 0 } };

    pub fn splat(s: f32) V3f {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [3]f32) V3f {
        return .{ .data = a };
    }
    pub fn store(v: V3f, a: *[3]f32) V3f {
        a.* = v.data;
    }

    pub fn v4f(v: V3f, _w: f32) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], _w } };
    }
    pub fn v3d(v: V3f) V3d {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V3f) V3f {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V3f) V3f {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V3f) f32 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V3f) f32 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V3f) f32 {
        const inorm: @Vector(3, f32) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V3f, b: V3f) V3f {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V3f, b: V3f) V3f {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V3f, b: V3f) V3f {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V3f, b: V3f) V3f {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V3f, b: V3f) V3f {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }
    pub fn cross(a: V3f, b: V3f) V3f {
        return .{ .data = .{
            a.data[1] * b.data[2] - a.data[2] * b.data[1],
            a.data[2] * b.data[0] - a.data[0] * b.data[2],
            a.data[0] * b.data[1] - a.data[1] * b.data[0],
        } };
    }

    pub fn lerp(a: V3f, b: V3f, t: V3f) V3f {
        return .{ .data = (@as(@Vector(3, f32), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V3f) f32 {
        return v.data[0];
    }
    pub fn y(v: V3f) f32 {
        return v.data[1];
    }
    pub fn z(v: V3f) f32 {
        return v.data[2];
    }

    pub fn xx(v: V3f) V2f {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V3f) V2f {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn xz(v: V3f) V2f {
        return .{ .data = .{ v.data[0], v.data[2] } };
    }
    pub fn yx(v: V3f) V2f {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V3f) V2f {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }
    pub fn yz(v: V3f) V2f {
        return .{ .data = .{ v.data[1], v.data[2] } };
    }
    pub fn zx(v: V3f) V2f {
        return .{ .data = .{ v.data[2], v.data[0] } };
    }
    pub fn zy(v: V3f) V2f {
        return .{ .data = .{ v.data[2], v.data[1] } };
    }
    pub fn zz(v: V3f) V2f {
        return .{ .data = .{ v.data[2], v.data[2] } };
    }

    pub fn xxx(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxz(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xyx(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyz(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xzx(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xzy(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xzz(v: V3f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yxx(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yxz(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyx(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyz(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yzx(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yzy(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yzz(v: V3f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zxx(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zxy(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zxz(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zyx(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zyy(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zyz(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzx(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzy(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzz(v: V3f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2] } };
    }

    pub fn xxxx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxxz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxyx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xxyz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xxzx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xxzy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xxzz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xyxx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyxz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn xyyx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn xyyz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn xyzx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn xyzy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn xyzz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn xzxx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn xzxy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn xzxz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn xzyx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn xzyy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn xzyz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn xzzx(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn xzzy(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn xzzz(v: V3f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn yxxx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxxz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn yxyx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxyz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn yxzx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn yxzy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn yxzz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yyxx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyxz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyyx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyyz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyzx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yyzy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yyzz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yzxx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn yzxy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn yzxz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn yzyx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn yzyy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn yzyz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn yzzx(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn yzzy(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn yzzz(v: V3f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zxxx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn zxxy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn zxxz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn zxyx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn zxyy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn zxyz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn zxzx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn zxzy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn zxzz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn zyxx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn zyxy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn zyxz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn zyyx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn zyyy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn zyyz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn zyzx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn zyzy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn zyzz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zzxx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zzxy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zzxz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zzyx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zzyy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zzyz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzzx(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzzy(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzzz(v: V3f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[2] } };
    }
};

pub const M3f = struct {
    data: [3]@Vector(3, f32),

    pub const zero: M3f = .{ .data = .{
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    } };
    pub const eye: M3f = .{ .data = .{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    } };


    pub fn transpose(m: M3f) M3f {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0], m.data[2][0] },
            .{ m.data[0][1], m.data[1][1], m.data[2][1] },
            .{ m.data[0][2], m.data[1][2], m.data[2][2] },
        } };
    }

    pub fn mulmat(a: M3f, b: M3f) M3f {
        const t = b.transpose();
        var c: M3f = undefined;
        for (0..3) |i| {
            for (0..3) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M3f, v: V3f) V3f {
        var w: V3f = undefined;
        for (0..3) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub fn v4f(x: f32, y: f32, z: f32, w: f32) V4f {
    return .{ .data = .{ x, y, z, w } };
}

pub const V4f = struct {
    data: @Vector(4, f32),

    pub const zero: V4f = .{ .data = @splat(0) };

    pub fn splat(s: f32) V4f {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [4]f32) V4f {
        return .{ .data = a };
    }
    pub fn store(v: V4f, a: *[4]f32) V4f {
        a.* = v.data;
    }

    pub fn v4d(v: V4f) V4d {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V4f) V4f {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V4f) V4f {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V4f) f32 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V4f) f32 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V4f) f32 {
        const inorm: @Vector(4, f32) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V4f, b: V4f) V4f {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V4f, b: V4f) V4f {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V4f, b: V4f) V4f {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V4f, b: V4f) V4f {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V4f, b: V4f) V4f {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }

    pub fn lerp(a: V4f, b: V4f, t: V4f) V4f {
        return .{ .data = (@as(@Vector(4, f32), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V4f) f32 {
        return v.data[0];
    }
    pub fn y(v: V4f) f32 {
        return v.data[1];
    }
    pub fn z(v: V4f) f32 {
        return v.data[2];
    }
    pub fn w(v: V4f) f32 {
        return v.data[3];
    }

    pub fn xx(v: V4f) V2f {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V4f) V2f {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn xz(v: V4f) V2f {
        return .{ .data = .{ v.data[0], v.data[2] } };
    }
    pub fn xw(v: V4f) V2f {
        return .{ .data = .{ v.data[0], v.data[3] } };
    }
    pub fn yx(v: V4f) V2f {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V4f) V2f {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }
    pub fn yz(v: V4f) V2f {
        return .{ .data = .{ v.data[1], v.data[2] } };
    }
    pub fn yw(v: V4f) V2f {
        return .{ .data = .{ v.data[1], v.data[3] } };
    }
    pub fn zx(v: V4f) V2f {
        return .{ .data = .{ v.data[2], v.data[0] } };
    }
    pub fn zy(v: V4f) V2f {
        return .{ .data = .{ v.data[2], v.data[1] } };
    }
    pub fn zz(v: V4f) V2f {
        return .{ .data = .{ v.data[2], v.data[2] } };
    }
    pub fn zw(v: V4f) V2f {
        return .{ .data = .{ v.data[2], v.data[3] } };
    }
    pub fn wx(v: V4f) V2f {
        return .{ .data = .{ v.data[3], v.data[0] } };
    }
    pub fn wy(v: V4f) V2f {
        return .{ .data = .{ v.data[3], v.data[1] } };
    }
    pub fn wz(v: V4f) V2f {
        return .{ .data = .{ v.data[3], v.data[2] } };
    }
    pub fn ww(v: V4f) V2f {
        return .{ .data = .{ v.data[3], v.data[3] } };
    }

    pub fn xxx(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxz(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxw(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3] } };
    }
    pub fn xyx(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyz(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xyw(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3] } };
    }
    pub fn xzx(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xzy(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xzz(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xzw(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3] } };
    }
    pub fn xwx(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0] } };
    }
    pub fn xwy(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1] } };
    }
    pub fn xwz(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2] } };
    }
    pub fn xww(v: V4f) V3f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3] } };
    }
    pub fn yxx(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yxz(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yxw(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3] } };
    }
    pub fn yyx(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyz(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyw(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3] } };
    }
    pub fn yzx(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yzy(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yzz(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yzw(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3] } };
    }
    pub fn ywx(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0] } };
    }
    pub fn ywy(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1] } };
    }
    pub fn ywz(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2] } };
    }
    pub fn yww(v: V4f) V3f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3] } };
    }
    pub fn zxx(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zxy(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zxz(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zxw(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3] } };
    }
    pub fn zyx(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zyy(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zyz(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zyw(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3] } };
    }
    pub fn zzx(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzy(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzz(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zzw(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3] } };
    }
    pub fn zwx(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0] } };
    }
    pub fn zwy(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1] } };
    }
    pub fn zwz(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2] } };
    }
    pub fn zww(v: V4f) V3f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3] } };
    }
    pub fn wxx(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0] } };
    }
    pub fn wxy(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1] } };
    }
    pub fn wxz(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2] } };
    }
    pub fn wxw(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3] } };
    }
    pub fn wyx(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0] } };
    }
    pub fn wyy(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1] } };
    }
    pub fn wyz(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2] } };
    }
    pub fn wyw(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3] } };
    }
    pub fn wzx(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0] } };
    }
    pub fn wzy(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1] } };
    }
    pub fn wzz(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2] } };
    }
    pub fn wzw(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3] } };
    }
    pub fn wwx(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0] } };
    }
    pub fn wwy(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1] } };
    }
    pub fn wwz(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2] } };
    }
    pub fn www(v: V4f) V3f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3] } };
    }

    pub fn xxxx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxxz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxxw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn xxyx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xxyz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xxyw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn xxzx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xxzy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xxzz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xxzw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn xxwx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn xxwy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn xxwz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn xxww(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn xyxx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyxz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn xyxw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn xyyx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn xyyz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn xyyw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn xyzx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn xyzy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn xyzz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn xyzw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn xywx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn xywy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn xywz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn xyww(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn xzxx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn xzxy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn xzxz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn xzxw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn xzyx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn xzyy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn xzyz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn xzyw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn xzzx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn xzzy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn xzzz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn xzzw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn xzwx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn xzwy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn xzwz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn xzww(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn xwxx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn xwxy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn xwxz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn xwxw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn xwyx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn xwyy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn xwyz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn xwyw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn xwzx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn xwzy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn xwzz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn xwzw(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn xwwx(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn xwwy(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn xwwz(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn xwww(v: V4f) V4f {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn yxxx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxxz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn yxxw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn yxyx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxyz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn yxyw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn yxzx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn yxzy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn yxzz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yxzw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn yxwx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn yxwy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn yxwz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn yxww(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn yyxx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyxz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyxw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn yyyx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyyz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyyw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn yyzx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yyzy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yyzz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yyzw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn yywx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn yywy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn yywz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn yyww(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn yzxx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn yzxy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn yzxz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn yzxw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn yzyx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn yzyy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn yzyz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn yzyw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn yzzx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn yzzy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn yzzz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn yzzw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn yzwx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn yzwy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn yzwz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn yzww(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn ywxx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn ywxy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn ywxz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn ywxw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn ywyx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn ywyy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn ywyz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn ywyw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn ywzx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn ywzy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn ywzz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn ywzw(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn ywwx(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn ywwy(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn ywwz(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn ywww(v: V4f) V4f {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn zxxx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn zxxy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn zxxz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn zxxw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn zxyx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn zxyy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn zxyz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn zxyw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn zxzx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn zxzy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn zxzz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn zxzw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn zxwx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn zxwy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn zxwz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn zxww(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn zyxx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn zyxy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn zyxz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn zyxw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn zyyx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn zyyy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn zyyz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn zyyw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn zyzx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn zyzy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn zyzz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zyzw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn zywx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn zywy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn zywz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn zyww(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn zzxx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zzxy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zzxz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zzxw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn zzyx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zzyy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zzyz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzyw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn zzzx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzzy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzzz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zzzw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn zzwx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn zzwy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn zzwz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn zzww(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn zwxx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn zwxy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn zwxz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn zwxw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn zwyx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn zwyy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn zwyz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn zwyw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn zwzx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn zwzy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn zwzz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn zwzw(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn zwwx(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn zwwy(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn zwwz(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn zwww(v: V4f) V4f {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn wxxx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn wxxy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn wxxz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn wxxw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn wxyx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn wxyy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn wxyz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn wxyw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn wxzx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn wxzy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn wxzz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn wxzw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn wxwx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn wxwy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn wxwz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn wxww(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn wyxx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn wyxy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn wyxz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn wyxw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn wyyx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn wyyy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn wyyz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn wyyw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn wyzx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn wyzy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn wyzz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn wyzw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn wywx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn wywy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn wywz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn wyww(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn wzxx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn wzxy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn wzxz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn wzxw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn wzyx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn wzyy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn wzyz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn wzyw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn wzzx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn wzzy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn wzzz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn wzzw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn wzwx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn wzwy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn wzwz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn wzww(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn wwxx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn wwxy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn wwxz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn wwxw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn wwyx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn wwyy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn wwyz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn wwyw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn wwzx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn wwzy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn wwzz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn wwzw(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn wwwx(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn wwwy(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn wwwz(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn wwww(v: V4f) V4f {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[3] } };
    }
};

pub const M4f = struct {
    data: [4]@Vector(4, f32),

    pub const zero: M4f = .{ .data = .{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    } };
    pub const eye: M4f = .{ .data = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };

    /// right handed, infinite far plane
    pub fn perspective(fovy: f32, aspect: f32, near: f32) M4f {
        const h = 1 / @tan(0.5 * fovy);
        const w = h / aspect;
        return .{ .data = .{
            .{ w, 0, 0, 0 },
            .{ 0, h, 0, 0 },
            .{ 0, 0, 0, -1 },
            .{ 0, 0, near, 0 },
        } };
    }
    /// right handed, camera at origin
    pub fn look(focus: V3f) M4f {
        const r = focus.cross(.up).normalized();
        const u = r.cross(focus).normalized();
        const d = focus.mul(.splat(-1)).normalized();
        return .{ .data = .{
            .{ r.data[0], r.data[1], r.data[2], 0 },
            .{ u.data[0], u.data[1], u.data[2], 0 },
            .{ d.data[0], d.data[1], d.data[2], 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn transpose(m: M4f) M4f {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0], m.data[2][0], m.data[3][0] },
            .{ m.data[0][1], m.data[1][1], m.data[2][1], m.data[3][1] },
            .{ m.data[0][2], m.data[1][2], m.data[2][2], m.data[3][2] },
            .{ m.data[0][3], m.data[1][3], m.data[2][3], m.data[3][3] },
        } };
    }

    pub fn mulmat(a: M4f, b: M4f) M4f {
        const t = b.transpose();
        var c: M4f = undefined;
        for (0..4) |i| {
            for (0..4) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M4f, v: V4f) V4f {
        var w: V4f = undefined;
        for (0..4) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub const Qf = struct {
    data: @Vector(4, f32)

    pub const eye: Qf = .{ .data = .{ 0, 0, 0, 1 } };

    pub fn between(a: V3f32, b: V3f32) Qf {
        const d = from.dot(to);
        if (d > -0.99999) { // FIXME make precision depend on type
            const c = from.cross(to);
            return .{ .data = .{ c.data[0], c.data[1], c.data[2], 1 + d } }.normalized() 
        } else {
            @panic("TODO");
            
            
            
        }
    }

    pub fn normalized(q: Qf) Qf {
        const inorm: @Vector(4, type) = @splat(1.0 / @sqrt(@reduce(.Add, q.data * q.data)));
        return .{ .data = v.data * inorm };
    }
    pub fn conj(q: Qf) Qf {
        return .{ .data = .{ -q.data[0], -q.data[1], -q.data[2], q.data[3] } };
    }
    pub fn rotate(q: Qf, v: V3f32) Qf {
        const q012 = v3f32(q.data[0], q.data[1], q.data[2]);
        const a: V3f32 = .mul(.cross(q012, v), .splat(2));
        const b: V3f32 = .cross(q012, a);
        const q3: @Vector(3, f32) = @splat(q.data[3]);
        return .{ .data = v + q3 * a + b };
    }
};

pub fn v2d(x: f64, y: f64) V2d {
    return .{ .data = .{ x, y } };
}

pub const V2d = struct {
    data: @Vector(2, f64),

    pub const zero: V2d = .{ .data = @splat(0) };

    pub fn splat(s: f64) V2d {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [2]f64) V2d {
        return .{ .data = a };
    }
    pub fn store(v: V2d, a: *[2]f64) V2d {
        a.* = v.data;
    }

    pub fn v3d(v: V2d, _z: f64) V3d {
        return .{ .data = .{ v.data[0], v.data[1], _z } };
    }
    pub fn v4d(v: V2d, _z: f64, _w: f64) V4d {
        return .{ .data = .{ v.data[0], v.data[1], _z, _w } };
    }
    pub fn v2f(v: V2d) V2f {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V2d) V2d {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V2d) V2d {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V2d) f64 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V2d) f64 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V2d) f64 {
        const inorm: @Vector(2, f64) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V2d, b: V2d) V2d {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V2d, b: V2d) V2d {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V2d, b: V2d) V2d {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V2d, b: V2d) V2d {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V2d, b: V2d) V2d {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }

    pub fn lerp(a: V2d, b: V2d, t: V2d) V2d {
        return .{ .data = (@as(@Vector(2, f64), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V2d) f64 {
        return v.data[0];
    }
    pub fn y(v: V2d) f64 {
        return v.data[1];
    }

    pub fn xx(v: V2d) V2d {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V2d) V2d {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn yx(v: V2d) V2d {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V2d) V2d {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }

    pub fn xxx(v: V2d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V2d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xyx(v: V2d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V2d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxx(v: V2d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V2d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyx(v: V2d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V2d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }

    pub fn xxxx(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxyx(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyxx(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyyx(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V2d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yxxx(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxyx(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yyxx(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyyx(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V2d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
};

pub const M2d = struct {
    data: [2]@Vector(2, f64),

    pub const zero: M2d = .{ .data = .{
        .{ 0, 0 },
        .{ 0, 0 },
    } };
    pub const eye: M2d = .{ .data = .{
        .{ 1, 0 },
        .{ 0, 1 },
    } };


    pub fn transpose(m: M2d) M2d {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0] },
            .{ m.data[0][1], m.data[1][1] },
        } };
    }

    pub fn mulmat(a: M2d, b: M2d) M2d {
        const t = b.transpose();
        var c: M2d = undefined;
        for (0..2) |i| {
            for (0..2) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M2d, v: V2d) V2d {
        var w: V2d = undefined;
        for (0..2) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub fn v3d(x: f64, y: f64, z: f64) V3d {
    return .{ .data = .{ x, y, z } };
}

pub const V3d = struct {
    data: @Vector(3, f64),

    pub const zero: V3d = .{ .data = @splat(0) };
    pub const up: V3d = .{ .data = .{ 0, 1, 0 } };

    pub fn splat(s: f64) V3d {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [3]f64) V3d {
        return .{ .data = a };
    }
    pub fn store(v: V3d, a: *[3]f64) V3d {
        a.* = v.data;
    }

    pub fn v4d(v: V3d, _w: f64) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], _w } };
    }
    pub fn v3f(v: V3d) V3f {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V3d) V3d {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V3d) V3d {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V3d) f64 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V3d) f64 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V3d) f64 {
        const inorm: @Vector(3, f64) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V3d, b: V3d) V3d {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V3d, b: V3d) V3d {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V3d, b: V3d) V3d {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V3d, b: V3d) V3d {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V3d, b: V3d) V3d {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }
    pub fn cross(a: V3d, b: V3d) V3d {
        return .{ .data = .{
            a.data[1] * b.data[2] - a.data[2] * b.data[1],
            a.data[2] * b.data[0] - a.data[0] * b.data[2],
            a.data[0] * b.data[1] - a.data[1] * b.data[0],
        } };
    }

    pub fn lerp(a: V3d, b: V3d, t: V3d) V3d {
        return .{ .data = (@as(@Vector(3, f64), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V3d) f64 {
        return v.data[0];
    }
    pub fn y(v: V3d) f64 {
        return v.data[1];
    }
    pub fn z(v: V3d) f64 {
        return v.data[2];
    }

    pub fn xx(v: V3d) V2d {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V3d) V2d {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn xz(v: V3d) V2d {
        return .{ .data = .{ v.data[0], v.data[2] } };
    }
    pub fn yx(v: V3d) V2d {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V3d) V2d {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }
    pub fn yz(v: V3d) V2d {
        return .{ .data = .{ v.data[1], v.data[2] } };
    }
    pub fn zx(v: V3d) V2d {
        return .{ .data = .{ v.data[2], v.data[0] } };
    }
    pub fn zy(v: V3d) V2d {
        return .{ .data = .{ v.data[2], v.data[1] } };
    }
    pub fn zz(v: V3d) V2d {
        return .{ .data = .{ v.data[2], v.data[2] } };
    }

    pub fn xxx(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxz(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xyx(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyz(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xzx(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xzy(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xzz(v: V3d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yxx(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yxz(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyx(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyz(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yzx(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yzy(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yzz(v: V3d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zxx(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zxy(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zxz(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zyx(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zyy(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zyz(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzx(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzy(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzz(v: V3d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2] } };
    }

    pub fn xxxx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxxz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxyx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xxyz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xxzx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xxzy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xxzz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xyxx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyxz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn xyyx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn xyyz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn xyzx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn xyzy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn xyzz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn xzxx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn xzxy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn xzxz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn xzyx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn xzyy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn xzyz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn xzzx(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn xzzy(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn xzzz(v: V3d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn yxxx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxxz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn yxyx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxyz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn yxzx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn yxzy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn yxzz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yyxx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyxz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyyx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyyz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyzx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yyzy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yyzz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yzxx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn yzxy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn yzxz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn yzyx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn yzyy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn yzyz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn yzzx(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn yzzy(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn yzzz(v: V3d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zxxx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn zxxy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn zxxz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn zxyx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn zxyy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn zxyz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn zxzx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn zxzy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn zxzz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn zyxx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn zyxy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn zyxz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn zyyx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn zyyy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn zyyz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn zyzx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn zyzy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn zyzz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zzxx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zzxy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zzxz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zzyx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zzyy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zzyz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzzx(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzzy(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzzz(v: V3d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[2] } };
    }
};

pub const M3d = struct {
    data: [3]@Vector(3, f64),

    pub const zero: M3d = .{ .data = .{
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    } };
    pub const eye: M3d = .{ .data = .{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    } };


    pub fn transpose(m: M3d) M3d {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0], m.data[2][0] },
            .{ m.data[0][1], m.data[1][1], m.data[2][1] },
            .{ m.data[0][2], m.data[1][2], m.data[2][2] },
        } };
    }

    pub fn mulmat(a: M3d, b: M3d) M3d {
        const t = b.transpose();
        var c: M3d = undefined;
        for (0..3) |i| {
            for (0..3) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M3d, v: V3d) V3d {
        var w: V3d = undefined;
        for (0..3) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub fn v4d(x: f64, y: f64, z: f64, w: f64) V4d {
    return .{ .data = .{ x, y, z, w } };
}

pub const V4d = struct {
    data: @Vector(4, f64),

    pub const zero: V4d = .{ .data = @splat(0) };

    pub fn splat(s: f64) V4d {
        return .{ .data = @splat(s) };
    }
    pub fn load(a: *const [4]f64) V4d {
        return .{ .data = a };
    }
    pub fn store(v: V4d, a: *[4]f64) V4d {
        a.* = v.data;
    }

    pub fn v4f(v: V4d) V4f {
        return .{ .data = @floatCast(v) };
    }

    pub fn floor(v: V4d) V4d {
        return .{ .data = @floor(v.data) };
    }
    pub fn ceil(v: V4d) V4d {
        return .{ .data = @floor(v.data) };
    }
    pub fn len(v: V4d) f64 {
        return @sqrt(@reduce(.Add, v.data * v.data));
    }
    pub fn len2(v: V4d) f64 {
        return @reduce(.Add, v.data * v.data);
    }
    pub fn normalized(v: V4d) f64 {
        const inorm: @Vector(4, f64) = @splat(1.0 / v.len());
        return .{ .data = v.data * inorm };
    }

    pub fn add(a: V4d, b: V4d) V4d {
        return .{ .data = a.data + b.data };
    }
    pub fn sub(a: V4d, b: V4d) V4d {
        return .{ .data = a.data - b.data };
    }
    pub fn mul(a: V4d, b: V4d) V4d {
        return .{ .data = a.data * b.data };
    }
    pub fn div(a: V4d, b: V4d) V4d {
        return .{ .data = a.data / b.data };
    }
    pub fn dot(a: V4d, b: V4d) V4d {
        return .{ .data = @reduce(.Add, a.data * b.data) };
    }

    pub fn lerp(a: V4d, b: V4d, t: V4d) V4d {
        return .{ .data = (@as(@Vector(4, f64), @splat(1)) - t.data) * a.data + t * b.data };
    }

    pub fn x(v: V4d) f64 {
        return v.data[0];
    }
    pub fn y(v: V4d) f64 {
        return v.data[1];
    }
    pub fn z(v: V4d) f64 {
        return v.data[2];
    }
    pub fn w(v: V4d) f64 {
        return v.data[3];
    }

    pub fn xx(v: V4d) V2d {
        return .{ .data = .{ v.data[0], v.data[0] } };
    }
    pub fn xy(v: V4d) V2d {
        return .{ .data = .{ v.data[0], v.data[1] } };
    }
    pub fn xz(v: V4d) V2d {
        return .{ .data = .{ v.data[0], v.data[2] } };
    }
    pub fn xw(v: V4d) V2d {
        return .{ .data = .{ v.data[0], v.data[3] } };
    }
    pub fn yx(v: V4d) V2d {
        return .{ .data = .{ v.data[1], v.data[0] } };
    }
    pub fn yy(v: V4d) V2d {
        return .{ .data = .{ v.data[1], v.data[1] } };
    }
    pub fn yz(v: V4d) V2d {
        return .{ .data = .{ v.data[1], v.data[2] } };
    }
    pub fn yw(v: V4d) V2d {
        return .{ .data = .{ v.data[1], v.data[3] } };
    }
    pub fn zx(v: V4d) V2d {
        return .{ .data = .{ v.data[2], v.data[0] } };
    }
    pub fn zy(v: V4d) V2d {
        return .{ .data = .{ v.data[2], v.data[1] } };
    }
    pub fn zz(v: V4d) V2d {
        return .{ .data = .{ v.data[2], v.data[2] } };
    }
    pub fn zw(v: V4d) V2d {
        return .{ .data = .{ v.data[2], v.data[3] } };
    }
    pub fn wx(v: V4d) V2d {
        return .{ .data = .{ v.data[3], v.data[0] } };
    }
    pub fn wy(v: V4d) V2d {
        return .{ .data = .{ v.data[3], v.data[1] } };
    }
    pub fn wz(v: V4d) V2d {
        return .{ .data = .{ v.data[3], v.data[2] } };
    }
    pub fn ww(v: V4d) V2d {
        return .{ .data = .{ v.data[3], v.data[3] } };
    }

    pub fn xxx(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxy(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxz(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxw(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3] } };
    }
    pub fn xyx(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xyy(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xyz(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xyw(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3] } };
    }
    pub fn xzx(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xzy(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xzz(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xzw(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3] } };
    }
    pub fn xwx(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0] } };
    }
    pub fn xwy(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1] } };
    }
    pub fn xwz(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2] } };
    }
    pub fn xww(v: V4d) V3d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3] } };
    }
    pub fn yxx(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yxy(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yxz(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yxw(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3] } };
    }
    pub fn yyx(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyy(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyz(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyw(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3] } };
    }
    pub fn yzx(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yzy(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yzz(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yzw(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3] } };
    }
    pub fn ywx(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0] } };
    }
    pub fn ywy(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1] } };
    }
    pub fn ywz(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2] } };
    }
    pub fn yww(v: V4d) V3d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3] } };
    }
    pub fn zxx(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zxy(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zxz(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zxw(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3] } };
    }
    pub fn zyx(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zyy(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zyz(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zyw(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3] } };
    }
    pub fn zzx(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzy(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzz(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zzw(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3] } };
    }
    pub fn zwx(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0] } };
    }
    pub fn zwy(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1] } };
    }
    pub fn zwz(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2] } };
    }
    pub fn zww(v: V4d) V3d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3] } };
    }
    pub fn wxx(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0] } };
    }
    pub fn wxy(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1] } };
    }
    pub fn wxz(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2] } };
    }
    pub fn wxw(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3] } };
    }
    pub fn wyx(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0] } };
    }
    pub fn wyy(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1] } };
    }
    pub fn wyz(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2] } };
    }
    pub fn wyw(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3] } };
    }
    pub fn wzx(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0] } };
    }
    pub fn wzy(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1] } };
    }
    pub fn wzz(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2] } };
    }
    pub fn wzw(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3] } };
    }
    pub fn wwx(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0] } };
    }
    pub fn wwy(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1] } };
    }
    pub fn wwz(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2] } };
    }
    pub fn www(v: V4d) V3d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3] } };
    }

    pub fn xxxx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn xxxy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn xxxz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn xxxw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn xxyx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn xxyy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn xxyz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn xxyw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn xxzx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn xxzy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn xxzz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn xxzw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn xxwx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn xxwy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn xxwz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn xxww(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn xyxx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn xyxy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn xyxz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn xyxw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn xyyx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn xyyy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn xyyz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn xyyw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn xyzx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn xyzy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn xyzz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn xyzw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn xywx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn xywy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn xywz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn xyww(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn xzxx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn xzxy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn xzxz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn xzxw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn xzyx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn xzyy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn xzyz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn xzyw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn xzzx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn xzzy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn xzzz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn xzzw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn xzwx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn xzwy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn xzwz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn xzww(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn xwxx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn xwxy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn xwxz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn xwxw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn xwyx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn xwyy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn xwyz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn xwyw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn xwzx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn xwzy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn xwzz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn xwzw(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn xwwx(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn xwwy(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn xwwz(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn xwww(v: V4d) V4d {
        return .{ .data = .{ v.data[0], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn yxxx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn yxxy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn yxxz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn yxxw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn yxyx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn yxyy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn yxyz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn yxyw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn yxzx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn yxzy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn yxzz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn yxzw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn yxwx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn yxwy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn yxwz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn yxww(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn yyxx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn yyxy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn yyxz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn yyxw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn yyyx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn yyyy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn yyyz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn yyyw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn yyzx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn yyzy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn yyzz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn yyzw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn yywx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn yywy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn yywz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn yyww(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn yzxx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn yzxy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn yzxz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn yzxw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn yzyx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn yzyy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn yzyz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn yzyw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn yzzx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn yzzy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn yzzz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn yzzw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn yzwx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn yzwy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn yzwz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn yzww(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn ywxx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn ywxy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn ywxz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn ywxw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn ywyx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn ywyy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn ywyz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn ywyw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn ywzx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn ywzy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn ywzz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn ywzw(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn ywwx(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn ywwy(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn ywwz(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn ywww(v: V4d) V4d {
        return .{ .data = .{ v.data[1], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn zxxx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn zxxy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn zxxz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn zxxw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn zxyx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn zxyy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn zxyz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn zxyw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn zxzx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn zxzy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn zxzz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn zxzw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn zxwx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn zxwy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn zxwz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn zxww(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn zyxx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn zyxy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn zyxz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn zyxw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn zyyx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn zyyy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn zyyz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn zyyw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn zyzx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn zyzy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn zyzz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn zyzw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn zywx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn zywy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn zywz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn zyww(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn zzxx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn zzxy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn zzxz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn zzxw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn zzyx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn zzyy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn zzyz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn zzyw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn zzzx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn zzzy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn zzzz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn zzzw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn zzwx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn zzwy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn zzwz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn zzww(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn zwxx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn zwxy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn zwxz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn zwxw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn zwyx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn zwyy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn zwyz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn zwyw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn zwzx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn zwzy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn zwzz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn zwzw(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn zwwx(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn zwwy(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn zwwz(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn zwww(v: V4d) V4d {
        return .{ .data = .{ v.data[2], v.data[3], v.data[3], v.data[3] } };
    }
    pub fn wxxx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[0] } };
    }
    pub fn wxxy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[1] } };
    }
    pub fn wxxz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[2] } };
    }
    pub fn wxxw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[0], v.data[3] } };
    }
    pub fn wxyx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[0] } };
    }
    pub fn wxyy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[1] } };
    }
    pub fn wxyz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[2] } };
    }
    pub fn wxyw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[1], v.data[3] } };
    }
    pub fn wxzx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[0] } };
    }
    pub fn wxzy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[1] } };
    }
    pub fn wxzz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[2] } };
    }
    pub fn wxzw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[2], v.data[3] } };
    }
    pub fn wxwx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[0] } };
    }
    pub fn wxwy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[1] } };
    }
    pub fn wxwz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[2] } };
    }
    pub fn wxww(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[0], v.data[3], v.data[3] } };
    }
    pub fn wyxx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[0] } };
    }
    pub fn wyxy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[1] } };
    }
    pub fn wyxz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[2] } };
    }
    pub fn wyxw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[0], v.data[3] } };
    }
    pub fn wyyx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[0] } };
    }
    pub fn wyyy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[1] } };
    }
    pub fn wyyz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[2] } };
    }
    pub fn wyyw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[1], v.data[3] } };
    }
    pub fn wyzx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[0] } };
    }
    pub fn wyzy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[1] } };
    }
    pub fn wyzz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[2] } };
    }
    pub fn wyzw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[2], v.data[3] } };
    }
    pub fn wywx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[0] } };
    }
    pub fn wywy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[1] } };
    }
    pub fn wywz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[2] } };
    }
    pub fn wyww(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[1], v.data[3], v.data[3] } };
    }
    pub fn wzxx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[0] } };
    }
    pub fn wzxy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[1] } };
    }
    pub fn wzxz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[2] } };
    }
    pub fn wzxw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[0], v.data[3] } };
    }
    pub fn wzyx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[0] } };
    }
    pub fn wzyy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[1] } };
    }
    pub fn wzyz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[2] } };
    }
    pub fn wzyw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[1], v.data[3] } };
    }
    pub fn wzzx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[0] } };
    }
    pub fn wzzy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[1] } };
    }
    pub fn wzzz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[2] } };
    }
    pub fn wzzw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[2], v.data[3] } };
    }
    pub fn wzwx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[0] } };
    }
    pub fn wzwy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[1] } };
    }
    pub fn wzwz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[2] } };
    }
    pub fn wzww(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[2], v.data[3], v.data[3] } };
    }
    pub fn wwxx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[0] } };
    }
    pub fn wwxy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[1] } };
    }
    pub fn wwxz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[2] } };
    }
    pub fn wwxw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[0], v.data[3] } };
    }
    pub fn wwyx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[0] } };
    }
    pub fn wwyy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[1] } };
    }
    pub fn wwyz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[2] } };
    }
    pub fn wwyw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[1], v.data[3] } };
    }
    pub fn wwzx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[0] } };
    }
    pub fn wwzy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[1] } };
    }
    pub fn wwzz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[2] } };
    }
    pub fn wwzw(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[2], v.data[3] } };
    }
    pub fn wwwx(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[0] } };
    }
    pub fn wwwy(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[1] } };
    }
    pub fn wwwz(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[2] } };
    }
    pub fn wwww(v: V4d) V4d {
        return .{ .data = .{ v.data[3], v.data[3], v.data[3], v.data[3] } };
    }
};

pub const M4d = struct {
    data: [4]@Vector(4, f64),

    pub const zero: M4d = .{ .data = .{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    } };
    pub const eye: M4d = .{ .data = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };

    /// right handed, infinite far plane
    pub fn perspective(fovy: f64, aspect: f64, near: f64) M4d {
        const h = 1 / @tan(0.5 * fovy);
        const w = h / aspect;
        return .{ .data = .{
            .{ w, 0, 0, 0 },
            .{ 0, h, 0, 0 },
            .{ 0, 0, 0, -1 },
            .{ 0, 0, near, 0 },
        } };
    }
    /// right handed, camera at origin
    pub fn look(focus: V3d) M4d {
        const r = focus.cross(.up).normalized();
        const u = r.cross(focus).normalized();
        const d = focus.mul(.splat(-1)).normalized();
        return .{ .data = .{
            .{ r.data[0], r.data[1], r.data[2], 0 },
            .{ u.data[0], u.data[1], u.data[2], 0 },
            .{ d.data[0], d.data[1], d.data[2], 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn transpose(m: M4d) M4d {
        return .{ .data = .{
            .{ m.data[0][0], m.data[1][0], m.data[2][0], m.data[3][0] },
            .{ m.data[0][1], m.data[1][1], m.data[2][1], m.data[3][1] },
            .{ m.data[0][2], m.data[1][2], m.data[2][2], m.data[3][2] },
            .{ m.data[0][3], m.data[1][3], m.data[2][3], m.data[3][3] },
        } };
    }

    pub fn mulmat(a: M4d, b: M4d) M4d {
        const t = b.transpose();
        var c: M4d = undefined;
        for (0..4) |i| {
            for (0..4) |j| {
                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);
            }
        }
        return c;
    }
    pub fn mulvec(m: M4d, v: V4d) V4d {
        var w: V4d = undefined;
        for (0..4) |i| {
            w.data[i] = @reduce(.Add, m.data[i] * v.data);
        }
        return w;
    }
};

pub const Qd = struct {
    data: @Vector(4, f64)

    pub const eye: Qd = .{ .data = .{ 0, 0, 0, 1 } };

    pub fn between(a: V3f64, b: V3f64) Qd {
        const d = from.dot(to);
        if (d > -0.99999) { // FIXME make precision depend on type
            const c = from.cross(to);
            return .{ .data = .{ c.data[0], c.data[1], c.data[2], 1 + d } }.normalized() 
        } else {
            @panic("TODO");
            
            
            
        }
    }

    pub fn normalized(q: Qd) Qd {
        const inorm: @Vector(4, type) = @splat(1.0 / @sqrt(@reduce(.Add, q.data * q.data)));
        return .{ .data = v.data * inorm };
    }
    pub fn conj(q: Qd) Qd {
        return .{ .data = .{ -q.data[0], -q.data[1], -q.data[2], q.data[3] } };
    }
    pub fn rotate(q: Qd, v: V3f64) Qd {
        const q012 = v3f64(q.data[0], q.data[1], q.data[2]);
        const a: V3f64 = .mul(.cross(q012, v), .splat(2));
        const b: V3f64 = .cross(q012, a);
        const q3: @Vector(3, f64) = @splat(q.data[3]);
        return .{ .data = v + q3 * a + b };
    }
};

