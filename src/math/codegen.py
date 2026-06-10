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


f = open(os.path.join(__location__, f"lin.zig"), "w+")

f.write(f'const std = @import("std");\n\n')

write_vector(f, 2, "f32", ["f64"])
write_matrix(f, 2, "f32")
write_vector(f, 3, "f32", ["f64"])
write_matrix(f, 3, "f32")
write_vector(f, 4, "f32", ["f64"])
write_matrix(f, 4, "f32")

write_vector(f, 2, "f64", ["f32"])
write_matrix(f, 2, "f64")
write_vector(f, 3, "f64", ["f32"])
write_matrix(f, 3, "f64")
write_vector(f, 4, "f64", ["f32"])
write_matrix(f, 4, "f64")

f.close()
