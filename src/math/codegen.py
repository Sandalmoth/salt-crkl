import os

# Source - https://stackoverflow.com/a/4060259
# Posted by André Caron, modified by community. See post 'Timeline' for change history
# Retrieved 2026-06-08, License - CC BY-SA 4.0
__location__ = os.path.realpath(os.path.join(os.getcwd(), os.path.dirname(__file__)))


def write_vector(f, dim, type, casts):
    abbrev = {
        "f32": "f",
        "f64": "d",
    }[type]
    typename = f"V{dim}{abbrev}"
    vector = f"@Vector({dim}, {type})"

    f.write(f"pub fn v{dim}{abbrev}({', '.join([f"{d}: {type}" for d in ['x', 'y', 'z', 'w'][:dim]])}) {typename} {{\n")
    f.write(f"    return .{{ .data = .{{ {', '.join([d for d in ['x', 'y', 'z', 'w'][:dim]])} }} }};\n")
    f.write(f"}}\n")

    f.write("\n")

    f.write(f"pub const {typename} = struct {{\n")
    f.write(f"    data: {vector},\n")

    f.write("\n")

    f.write(f"    pub const zero: {typename} = .{{ .data = @splat(0) }};\n")

    if dim == 3:
        f.write(f"    pub const up: {typename} = .{{ .data = .{{ 0, 1, 0 }} }};\n")

    f.write("\n")

    f.write(f"    pub fn splat(s: {type}) {typename} {{\n")
    f.write(f"        return .{{ .data = @splat(s) }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn load(a: *const [{dim}]{type}) {typename} {{\n")
    f.write(f"        return .{{ .data = a }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn store(v: {typename}, a: *[{dim}]{type}) {typename} {{\n")
    f.write(f"        a.* = v.data;\n")
    f.write(f"    }}\n")

    f.write("\n")

    for i in range(dim + 1, 5):
        f.write(f"    pub fn v{i}{abbrev}(v: {typename}, {', '.join([f"{['_x', '_y', '_z', '_w'][dim + d]}: {type}" for d in range(i - dim)])}) V{i}{abbrev} {{\n")
        f.write(f"        return .{{ .data = .{{ {', '.join([f"v.data[{d}]" for d in range(dim)])}, {', '.join([['_x', '_y', '_z', '_w'][dim + d] for d in range(i - dim)])} }} }};\n")
        f.write(f"    }}\n")

    for other in casts:
        oa = {
            "f32": "f",
            "f64": "d",
        }[other]
        f.write(f"    pub fn v{dim}{oa}(v: {typename}) V{dim}{oa} {{\n")
        f.write(f"        return .{{ .data = @floatCast(v) }};\n")
        f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn floor(v: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = @floor(v.data) }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn ceil(v: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = @floor(v.data) }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn len(v: {typename}) {type} {{\n")
    f.write(f"        return @sqrt(@reduce(.Add, v.data * v.data));\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn len2(v: {typename}) {type} {{\n")
    f.write(f"        return @reduce(.Add, v.data * v.data);\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn normalized(v: {typename}) {type} {{\n")
    f.write(f"        const inorm: {vector} = @splat(1.0 / v.len());\n")
    f.write(f"        return .{{ .data = v.data * inorm }};\n")
    f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn add(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = a.data + b.data }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn sub(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = a.data - b.data }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn mul(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = a.data * b.data }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn div(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = a.data / b.data }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn dot(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = @reduce(.Add, a.data * b.data) }};\n")
    f.write(f"    }}\n")

    if dim == 3:
        f.write(f"    pub fn cross(a: {typename}, b: {typename}) {typename} {{\n")
        f.write(f"        return .{{ .data = .{{\n")
        f.write(f"            a.data[1] * b.data[2] - a.data[2] * b.data[1],\n")
        f.write(f"            a.data[2] * b.data[0] - a.data[0] * b.data[2],\n")
        f.write(f"            a.data[0] * b.data[1] - a.data[1] * b.data[0],\n")
        f.write(f"        }} }};\n")
        f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn lerp(a: {typename}, b: {typename}, t: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = (@as({vector}, @splat(1)) - t.data) * a.data + t * b.data }};\n")
    f.write(f"    }}\n")

    f.write("\n")

    for i, d0 in enumerate(["x", "y", "z", "w"][:dim]):
        f.write(f"    pub fn {d0}(v: {typename}) {type} {{\n")
        f.write(f"        return v.data[{i}];\n")
        f.write(f"    }}\n")

    f.write("\n")

    for i, d0 in enumerate(["x", "y", "z", "w"][:dim]):
        for j, d1 in enumerate(["x", "y", "z", "w"][:dim]):
            f.write(f"    pub fn {d0}{d1}(v: {typename}) V2{abbrev} {{\n")
            f.write(f"        return .{{ .data = .{{ v.data[{i}], v.data[{j}] }} }};\n")
            f.write(f"    }}\n")

    f.write("\n")

    for i, d0 in enumerate(["x", "y", "z", "w"][:dim]):
        for j, d1 in enumerate(["x", "y", "z", "w"][:dim]):
            for k, d2 in enumerate(["x", "y", "z", "w"][:dim]):
                f.write(f"    pub fn {d0}{d1}{d2}(v: {typename}) V3{abbrev} {{\n")
                f.write(f"        return .{{ .data = .{{ v.data[{i}], v.data[{j}], v.data[{k}] }} }};\n")
                f.write(f"    }}\n")

    f.write("\n")

    for i, d0 in enumerate(["x", "y", "z", "w"][:dim]):
        for j, d1 in enumerate(["x", "y", "z", "w"][:dim]):
            for k, d2 in enumerate(["x", "y", "z", "w"][:dim]):
                for l, d3 in enumerate(["x", "y", "z", "w"][:dim]):
                    f.write(f"    pub fn {d0}{d1}{d2}{d3}(v: {typename}) V4{abbrev} {{\n")
                    f.write(f"        return .{{ .data = .{{ v.data[{i}], v.data[{j}], v.data[{k}], v.data[{l}] }} }};\n")
                    f.write(f"    }}\n")

    f.write(f"}};\n\n")


def write_matrix(f, dim, type):
    abbrev = {
        "f32": "f",
        "f64": "d",
    }[type]
    typename = f"M{dim}{abbrev}"
    vector = f"@Vector({dim}, {type})"

    f.write(f"pub const {typename} = struct {{\n")
    f.write(f"    data: [{dim}]{vector},\n")

    f.write("\n")

    f.write(f"    pub const zero: {typename} = .{{ .data = .{{\n")
    for _ in range(dim):
        f.write(f"        .{{ {', '.join(['0' for _ in range(dim)])} }},\n")
    f.write(f"    }} }};\n")

    f.write(f"    pub const eye: {typename} = .{{ .data = .{{\n")
    for i in range(dim):
        f.write(f"        .{{ {', '.join(['1' if i == j else '0' for j in range(dim)])} }},\n")
    f.write(f"    }} }};\n")

    f.write("\n")

    if dim == 4:
        f.write(f"    /// right handed, infinite far plane\n")
        f.write(f"    pub fn perspective(fovy: {type}, aspect: {type}, near: {type}) {typename} {{\n")
        f.write(f"        const h = 1 / @tan(0.5 * fovy);\n")
        f.write(f"        const w = h / aspect;\n")
        f.write(f"        return .{{ .data = .{{\n")
        f.write(f"            .{{ w, 0, 0, 0 }},\n")
        f.write(f"            .{{ 0, h, 0, 0 }},\n")
        f.write(f"            .{{ 0, 0, 0, -1 }},\n")
        f.write(f"            .{{ 0, 0, near, 0 }},\n")
        f.write(f"        }} }};\n")
        f.write(f"    }}\n")

        f.write(f"    /// right handed, camera at origin\n")
        f.write(f"    pub fn look(focus: V3{abbrev}) {typename} {{\n")
        f.write(f"        const r = focus.cross(.up).normalized();\n")
        f.write(f"        const u = r.cross(focus).normalized();\n")
        f.write(f"        const d = focus.mul(.splat(-1)).normalized();\n")
        f.write(f"        return .{{ .data = .{{\n")
        f.write(f"            .{{ r.data[0], r.data[1], r.data[2], 0 }},\n")
        f.write(f"            .{{ u.data[0], u.data[1], u.data[2], 0 }},\n")
        f.write(f"            .{{ d.data[0], d.data[1], d.data[2], 0 }},\n")
        f.write(f"            .{{ 0, 0, 0, 1 }},\n")
        f.write(f"        }} }};\n")
        f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn transpose(m: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = .{{\n")
    for i in range(dim):
        f.write(f"            .{{ {', '.join([f"m.data[{j}][{i}]" for j in range(dim)])} }},\n")
    f.write(f"        }} }};\n")
    f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn mulmat(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        const t = b.transpose();\n")
    f.write(f"        var c: {typename} = undefined;\n")
    f.write(f"        for (0..{dim}) |i| {{\n")
    f.write(f"            for (0..{dim}) |j| {{\n")
    f.write(f"                c.data[i][j] = @reduce(.Add, a.data[i] * t.data[i]);\n")
    f.write(f"            }}\n")
    f.write(f"        }}\n")
    f.write(f"        return c;\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn mulvec(m: {typename}, v: V{dim}{abbrev}) V{dim}{abbrev} {{\n")
    f.write(f"        var w: V{dim}{abbrev} = undefined;\n")
    f.write(f"        for (0..{dim}) |i| {{\n")
    f.write(f"            w.data[i] = @reduce(.Add, m.data[i] * v.data);\n")
    f.write(f"        }}\n")
    f.write(f"        return w;\n")
    f.write(f"    }}\n")

    f.write(f"}};\n\n")

def write_quat(f, type):
    abbrev = {
        "f32": "f",
        "f64": "d",
    }[type]
    typename = f"Q{abbrev}"
    vector = f"@Vector(4, type)"

    f.write(f"pub const {typename} = struct {{\n")
    f.write(f"    data: @Vector(4, {type}),\n")

    f.write("\n")

    f.write(f"    pub const eye: {typename} = .{{ .data = .{{ 0, 0, 0, 1 }} }};\n")

    f.write("\n")

    f.write(f"    pub fn between(a: V3{abbrev}, b: V3{abbrev}) {typename} {{\n")
    f.write(f"        const d = a.dot(b);\n")
    f.write(f"        if (d > -0.999) {{ // FIXME make precision depend on type\n")
    f.write(f"            const c = a.cross(b);\n")
    f.write(f"            return .{{ .data = .{{ c.data[0], c.data[1], c.data[2], 1 + d }} }}.normalized();\n")
    f.write(f"        }} else {{\n")
    f.write(f"            if (@abs(a.data[0]) < 0.1) {{\n")
    f.write(f"                return .{{ .data = .{{ 0, -a.data[2], a.data[1], 0 }} }}.normalized();\n")
    f.write(f"            }} else {{\n")
    f.write(f"                return .{{ .data = .{{ -a.data[2], 0, a.data[0], 0 }} }}.normalized();\n")
    f.write(f"            }}\n")
    f.write(f"        }}\n")
    f.write(f"        unreachable;\n")
    f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn normalized(q: {typename}) {typename} {{\n")
    f.write(f"        const inorm: {vector} = @splat(1.0 / @sqrt(@reduce(.Add, q.data * q.data)));\n")
    f.write(f"        return .{{ .data = q.data * inorm }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn conj(q: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = .{{ -q.data[0], -q.data[1], -q.data[2], q.data[3] }} }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn neg(q: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = .{{ -q.data[0], -q.data[1], -q.data[2], -q.data[3] }} }};\n")
    f.write(f"    }}\n")

    f.write("\n")

    f.write(f"    pub fn mul(a: {typename}, b: {typename}) {typename} {{\n")
    f.write(f"        // TODO SIMD\n")
    f.write(f"        const x0, const y0, const z0, const w0 = a.data;\n")
    f.write(f"        const x1, const y1, const z1, const w1 = b.data;\n")
    f.write(f"        return .{{ .data = .{{\n")
    f.write(f"            w0 * x1 + x0 * w1 + y0 * z1 - z0 * y1,\n")
    f.write(f"            w0 * y1 - x0 * z1 + y0 * w1 + z0 * x1,\n")
    f.write(f"            w0 * z1 + x0 * y1 - y0 * x1 + z0 * w1,\n")
    f.write(f"            w0 * w1 - x0 * x1 - y0 * y1 - z0 * z1,\n")
    f.write(f"        }} }};\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn nlerp(a: {typename}, b: {typename}, t: {type}) {typename} {{\n")
    f.write(f"        const ts: @Vector(4, {type}) = @splat(t);\n")
    f.write(f"        const its: @Vector(4, {type}) = @splat(1 - t);\n")
    f.write(f"        return .{{ .data = (its - t.data) * a.data + ts * b.data }}.normalized();\n")
    f.write(f"    }}\n")

    f.write(f"    pub fn slerp(a: {typename}, b: {typename}, t: {type}) {typename} {{\n")
    f.write(f"        var d = a.dot(b);\n")
    f.write(f"        var b2 = b;\n")
    f.write(f"        if (d < 0) {{\n")
    f.write(f"            d = -d;\n")
    f.write(f"            b2 = b2.neg();\n")
    f.write(f"        }}\n")
    f.write(f"        if (d > 0.999) return .nlerp(a, b, t);\n")
    f.write(f"        const theta = @acos(d);\n")
    f.write(f"        const sin_theta = @sqrt(1 - d * d);\n")
    f.write(f"        const xa = @sin(1 - t) * theta) / sin_theta;\n")
    f.write(f"        const xb = @sin(t * theta) / sin_theta;\n")
    f.write(f"        return .{{ .data = .{{ xa * a.data + xb + b.data }} }};\n")
    f.write(f"    }}\n")
    
    f.write("\n")

    f.write(f"    pub fn rotate(q: {typename}, v: V3{abbrev}) {typename} {{\n")
    f.write(f"        const q012 = v3{abbrev}(q.data[0], q.data[1], q.data[2]);\n")
    f.write(f"        const a: V3{abbrev} = .mul(.cross(q012, v), .splat(2));\n")
    f.write(f"        const b: V3{abbrev} = .cross(q012, a);\n")
    f.write(f"        const q3: @Vector(3, {type}) = @splat(q.data[3]);\n")
    f.write(f"        return .{{ .data = v + q3 * a + b }};\n")
    f.write(f"    }}\n")

    f.write(f"}};\n\n")


f = open(os.path.join(__location__, f"lin.zig"), "w+")

f.write(f'const std = @import("std");\n\n')

write_vector(f, 2, "f32", ["f64"])
write_matrix(f, 2, "f32")
write_vector(f, 3, "f32", ["f64"])
write_matrix(f, 3, "f32")
write_vector(f, 4, "f32", ["f64"])
write_matrix(f, 4, "f32")
write_quat(f, "f32")

write_vector(f, 2, "f64", ["f32"])
write_matrix(f, 2, "f64")
write_vector(f, 3, "f64", ["f32"])
write_matrix(f, 3, "f64")
write_vector(f, 4, "f64", ["f32"])
write_matrix(f, 4, "f64")
write_quat(f, "f64")

f.close()
