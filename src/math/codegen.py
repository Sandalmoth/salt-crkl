import os


# Source - https://stackoverflow.com/a/4060259
# Posted by André Caron, modified by community. See post 'Timeline' for change history
# Retrieved 2026-06-08, License - CC BY-SA 4.0
__location__ = os.path.realpath(
    os.path.join(os.getcwd(), os.path.dirname(__file__)))


def write_vector(f, dim, type):
    abbrev = {
        "f32": "f",
        "f64": "d",
    }[type]
    typename = f"V{dim}{abbrev}"
    vector = f"@Vector({dim}, {type})"

    f.write(f"pub const {typename} = struct {{\n")
    f.write(f"    data: {vector},\n")

    f.write("\n");

    f.write(f"    pub const zero: {typename} = .{{ .data = @splat(0) }};\n")

    f.write("\n");

    f.write(f"    pub fn splat(s: {type}) {typename} {{\n")
    f.write(f"         return .{{ .data = @splat(s) }};\n")
    f.write(f"    }}\n")

    f.write("\n");

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

    f.write("\n");

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

    f.write("\n");

    f.write(f"    pub fn lerp(a: {typename}, b: {typename}, t: {typename}) {typename} {{\n")
    f.write(f"        return .{{ .data = (@as({vector}, @splat(1)) - t.data) * a.data + t * b.data }};\n")
    f.write(f"    }}\n")

    f.write("\n");

    for i, d0 in enumerate(['x', 'y', 'z', 'w'][:dim]):
        f.write(f"    pub fn {d0}(v: {typename}) {type} {{\n")
        f.write(f"        return v.data[{i}];\n")
        f.write(f"    }}\n")

    f.write("\n");

    for i, d0 in enumerate(['x', 'y', 'z', 'w'][:dim]):
        for j, d1 in enumerate(['x', 'y', 'z', 'w'][:dim]):
            f.write(f"    pub fn {d0}{d1}(v: {typename}) V2{abbrev} {{\n")
            f.write(f"        return .{{ .data = .{{ v.data[{i}], v.data[{j}] }} }};\n")
            f.write(f"    }}\n")

    f.write("\n");
            
    for i, d0 in enumerate(['x', 'y', 'z', 'w'][:dim]):
        for j, d1 in enumerate(['x', 'y', 'z', 'w'][:dim]):
            for k, d2 in enumerate(['x', 'y', 'z', 'w'][:dim]):
                f.write(f"    pub fn {d0}{d1}{d2}(v: {typename}) V3{abbrev} {{\n")
                f.write(f"        return .{{ .data = .{{ v.data[{i}], v.data[{j}], v.data[{k}] }} }};\n")
                f.write(f"    }}\n")

    f.write("\n");

    for i, d0 in enumerate(['x', 'y', 'z', 'w'][:dim]):
        for j, d1 in enumerate(['x', 'y', 'z', 'w'][:dim]):
            for k, d2 in enumerate(['x', 'y', 'z', 'w'][:dim]):
                for l, d3 in enumerate(['x', 'y', 'z', 'w'][:dim]):
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

    f.write("\n");

    f.write(f"    pub const zero: {typename} = .{{ .data = .{{\n")
    for _ in range(dim):
        f.write(f"        .{{ {', '.join(['0' for _ in range(dim)])} }},\n");
    f.write(f"    }} }};\n")

    f.write(f"    pub const eye: {typename} = .{{ .data = .{{\n")
    for i in range(dim):
        f.write(f"        .{{ {', '.join(['1' if i == j else '0' for j in range(dim)])} }},\n");
    f.write(f"    }} }};\n")

    f.write("\n");

    f.write(f"    pub fn splat(s: {type}) {typename} {{\n")
    f.write(f"        return .{{ .data = .{{\n")
    for _ in range(dim):
        f.write(f"            @splat(s),\n")
    f.write(f"        }} }};\n")
    f.write(f"    }}\n")

    f.write(f"}};\n\n")


f = open(os.path.join(__location__, f"lin.zig"), "w+");

f.write(f"const std = @import(\"std\");\n\n")

write_vector(f, 2, "f32")
write_matrix(f, 2, "f32")
write_vector(f, 3, "f32")
write_matrix(f, 3, "f32")
write_vector(f, 4, "f32")
write_matrix(f, 4, "f32")

f.close();
