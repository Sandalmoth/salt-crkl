// A (partial) port of Sebastian Aaltonen's OffsetAllocator
// Origincal C++ code (C) Sebastian Aaltonen 2023, MIT License
// Zig port (C) Jonathan Lindström 2026, zlib license

// This is almost a verbatim translation of the core functionality
// So there are many places where the code could be restructured to use more zig features

const std = @import("std");

const num_top_bins: u32 = 32;
const bins_per_leaf: u32 = 8;
const top_bins_index_shift: u32 = 3;
const leaf_bins_index_mask: u32 = 0x7;
const num_leaf_bins: u32 = num_top_bins * bins_per_leaf;

pub const Allocation = struct {
    const no_space: u32 = std.math.maxInt(u32);

    offset: u32,
    metadata: u32,
};

pub const Allocator = struct {
    const Node = struct {
        const unused = std.math.maxInt(u32);

        data_offset: u32 = 0,
        data_size: u32 = 0,
        bin_list_prev: u32 = unused,
        bin_list_next: u32 = unused,
        neighbour_prev: u32 = unused,
        neighbour_next: u32 = unused,
        used: bool = false,
    };

    size: u32,
    free_storage: u32,

    used_bins_top: u32,
    used_bins: [num_top_bins]u8,
    bin_indices: [num_leaf_bins]u32,

    nodes: []Node,
    free_nodes: []u32,
    free_offset: u32,

    pub fn init(gpa: std.mem.Allocator, size: u32, max_allocs: u32) !Allocator {
        var alloc: Allocator = .{
            .size = size,
            .free_storage = 0,
            .used_bins_top = 0,
            .used_bins = .{0} ** num_top_bins,
            .bin_indices = .{Node.unused} ** num_leaf_bins,
            .nodes = undefined,
            .free_nodes = undefined,
            .free_offset = max_allocs - 1,
        };
        alloc.nodes = try gpa.alloc(Node, max_allocs);
        errdefer gpa.free(alloc.nodes);
        alloc.free_nodes = try gpa.alloc(u32, max_allocs);
        errdefer gpa.free(alloc.free_nodes);
        for (0..max_allocs) |i| alloc.free_nodes[i] = max_allocs - @as(u32, @intCast(i)) - 1;
        _ = alloc.insertNodeIntoBin(alloc.size, 0);
        return alloc;
    }

    pub fn deinit(alloc: *Allocator, gpa: std.mem.Allocator) void {
        gpa.free(alloc.nodes);
        gpa.free(alloc.free_nodes);
        alloc.* = undefined;
    }

    pub fn allocate(alloc: *Allocator, size: u32) !Allocation {
        std.debug.assert(size > 0);
        if (alloc.free_offset == 0) return error.MaxAllocs;

        const min_bin_index: u32 = SmallFloat.uintToFloatRoundUp(size).bits;
        const min_top_bin_index: u32 = min_bin_index >> top_bins_index_shift;
        const min_leaf_bin_index: u32 = min_bin_index & leaf_bins_index_mask;

        var top_bin_index: u32 = min_top_bin_index;
        var leaf_bin_index: u32 = Allocation.no_space;

        if (alloc.used_bins_top & (@as(u32, 1) << @intCast(top_bin_index)) != 0) {
            leaf_bin_index = findLowestSetBitAfter(
                alloc.used_bins[top_bin_index],
                min_leaf_bin_index,
            );
        }

        if (leaf_bin_index == Allocation.no_space) {
            // no space in the bin, search next one
            top_bin_index = findLowestSetBitAfter(
                alloc.used_bins_top,
                min_top_bin_index + 1,
            );
            if (top_bin_index == Allocation.no_space) return error.OutOfMemory;
            leaf_bin_index = @ctz(alloc.used_bins[top_bin_index]);
        }

        const bin_index = (top_bin_index << top_bins_index_shift) | leaf_bin_index;

        const node_index: u32 = alloc.bin_indices[bin_index];
        const node: *Node = &alloc.nodes[node_index];
        const node_total_size: u32 = node.data_size;
        node.data_size = size;
        node.used = true;
        alloc.bin_indices[bin_index] = node.bin_list_next;
        if (node.bin_list_next != Node.unused) {
            alloc.nodes[node.bin_list_next].bin_list_prev = Node.unused;
        }
        alloc.free_storage -= node_total_size;

        if (alloc.bin_indices[bin_index] == Node.unused) {
            alloc.used_bins[top_bin_index] &= ~(@as(u8, 1) << @intCast(leaf_bin_index));

            if (alloc.used_bins[top_bin_index] == 0) {
                alloc.used_bins_top &= ~(@as(u32, 1) << @intCast(top_bin_index));
            }
        }

        const remainder_size = node_total_size - size;
        if (remainder_size > 0) {
            const new_node_index: u32 = alloc.insertNodeIntoBin(
                remainder_size,
                node.data_offset + size,
            );

            if (node.neighbour_next != Node.unused) {
                alloc.nodes[node.neighbour_next].neighbour_prev = new_node_index;
            }
            alloc.nodes[new_node_index].neighbour_prev = node_index;
            alloc.nodes[new_node_index].neighbour_next = node.neighbour_next;
            node.neighbour_next = new_node_index;
        }

        return .{ .offset = node.data_offset, .metadata = node_index };
    }

    pub fn free(alloc: *Allocator, allocation: Allocation) void {
        const node_index: u32 = allocation.metadata;
        const node: *Node = &alloc.nodes[node_index];

        std.debug.assert(node.used == true);

        var offset: u32 = node.data_offset;
        var size: u32 = node.data_size;

        if ((node.neighbour_prev != Node.unused) and !alloc.nodes[node.neighbour_prev].used) {
            const prev_node: *Node = &alloc.nodes[node.neighbour_prev];
            offset = prev_node.data_offset;
            size += prev_node.data_size;
            alloc.removeNodeFromBin(node.neighbour_prev);
            std.debug.assert(prev_node.neighbour_next == node_index);
            node.neighbour_prev = prev_node.neighbour_prev;
        }

        if ((node.neighbour_next != Node.unused) and !alloc.nodes[node.neighbour_next].used) {
            const next_node: *Node = &alloc.nodes[node.neighbour_next];
            size += next_node.data_size;
            alloc.removeNodeFromBin(node.neighbour_next);
            std.debug.assert(next_node.neighbour_prev == node_index);
            node.neighbour_next = next_node.neighbour_next;
        }

        const neighbour_next = node.neighbour_next;
        const neighbour_prev = node.neighbour_prev;

        alloc.free_offset += 1;
        alloc.free_nodes[alloc.free_offset] = node_index;
        const combined_node_index: u32 = alloc.insertNodeIntoBin(size, offset);
        if (neighbour_next != Node.unused) {
            alloc.nodes[combined_node_index].neighbour_next = neighbour_next;
            alloc.nodes[neighbour_next].neighbour_prev = combined_node_index;
        }
        if (neighbour_prev != Node.unused) {
            alloc.nodes[combined_node_index].neighbour_prev = neighbour_prev;
            alloc.nodes[neighbour_prev].neighbour_next = combined_node_index;
        }
    }

    fn insertNodeIntoBin(alloc: *Allocator, size: u32, data_offset: u32) u32 {
        const bin_index: u32 = SmallFloat.uintToFloatRoundDown(size).bits;
        const top_bin_index: u32 = bin_index >> top_bins_index_shift;
        const leaf_bin_index: u32 = bin_index & leaf_bins_index_mask;
        if (alloc.bin_indices[bin_index] == Node.unused) {
            alloc.used_bins[top_bin_index] |= @as(u8, 1) << @intCast(leaf_bin_index);
            alloc.used_bins_top |= @as(u32, 1) << @intCast(top_bin_index);
        }

        const top_node_index: u32 = alloc.bin_indices[bin_index];
        const node_index = alloc.free_nodes[alloc.free_offset];
        alloc.free_offset -= 1;

        alloc.nodes[node_index] = .{
            .data_offset = data_offset,
            .data_size = size,
            .bin_list_next = top_node_index,
        };
        if (top_node_index != Node.unused) alloc.nodes[top_node_index].bin_list_prev = node_index;
        alloc.bin_indices[bin_index] = node_index;

        alloc.free_storage += size;

        return node_index;
    }

    fn removeNodeFromBin(alloc: *Allocator, node_index: u32) void {
        const node: *Node = &alloc.nodes[node_index];
        if (node.bin_list_prev != Node.unused) {
            alloc.nodes[node.bin_list_prev].bin_list_next = node.bin_list_next;
            if (node.bin_list_next != Node.unused) {
                alloc.nodes[node.bin_list_next].bin_list_prev = node.bin_list_prev;
            }
        } else {
            const bin_index = SmallFloat.uintToFloatRoundDown(node.data_size).bits;
            const top_bin_index: u32 = bin_index >> top_bins_index_shift;
            const leaf_bin_index: u32 = bin_index & leaf_bins_index_mask;
            alloc.bin_indices[bin_index] = node.bin_list_next;
            if (node.bin_list_next != Node.unused) {
                alloc.nodes[node.bin_list_next].bin_list_prev = Node.unused;
            }

            if (alloc.bin_indices[bin_index] == Node.unused) {
                alloc.used_bins[top_bin_index] &= ~(@as(u8, 1) << @intCast(leaf_bin_index));
                if (alloc.used_bins[top_bin_index] == 0) {
                    alloc.used_bins_top &= ~(@as(u32, 1) << @intCast(top_bin_index));
                }
            }
        }

        alloc.free_offset += 1;
        alloc.free_nodes[alloc.free_offset] = node_index;
        alloc.free_storage -= node.data_size;
    }
};

fn findLowestSetBitAfter(bit_mask: u32, start_bit_index: u32) u32 {
    const mask_before_start_index: u32 = (@as(u32, 1) << @intCast(start_bit_index)) - 1;
    const mask_after_start_index: u32 = ~mask_before_start_index;
    const bits_after: u32 = bit_mask & mask_after_start_index;
    if (bits_after == 0) return Allocation.no_space;
    return @ctz(bits_after);
}

const SmallFloat = struct {
    const mantissa_bits: u32 = 3;
    const mantissa_value: u32 = 1 << mantissa_bits;
    const mantissa_mask = mantissa_value - 1;

    bits: u32,

    fn uintToFloatRoundUp(size: u32) SmallFloat {
        var exponent: u32 = 0;
        var mantissa: u32 = 0;
        if (size < mantissa_value) {
            mantissa = size;
        } else {
            const leading_zeros: u32 = @clz(size);
            const highest_set_bit: u32 = 31 - leading_zeros;
            const mantissa_start_bit = highest_set_bit - mantissa_bits;
            exponent = mantissa_start_bit + 1;
            mantissa = (size >> @intCast(mantissa_start_bit)) & mantissa_mask;
            const low_bits_mask: u32 = (@as(u32, 1) << @intCast(mantissa_start_bit)) - 1;
            if ((size & low_bits_mask) != 0) mantissa += 1;
        }
        return .{ .bits = (exponent << mantissa_bits) + mantissa };
    }

    fn uintToFloatRoundDown(size: u32) SmallFloat {
        var exponent: u32 = 0;
        var mantissa: u32 = 0;
        if (size < mantissa_value) {
            mantissa = size;
        } else {
            const leading_zeros: u32 = @clz(size);
            const highest_set_bit: u32 = 31 - leading_zeros;
            const mantissa_start_bit = highest_set_bit - mantissa_bits;
            exponent = mantissa_start_bit + 1;
            mantissa = (size >> @intCast(mantissa_start_bit)) & mantissa_mask;
        }
        return .{ .bits = (exponent << mantissa_bits) | mantissa };
    }

    fn floatToUint(float: SmallFloat) u32 {
        const exponent: u32 = float.bits >> mantissa_bits;
        const mantissa = float.bits & mantissa_mask;
        return if (exponent == 0)
            mantissa
        else
            (mantissa | mantissa_value) << (exponent - 1);
    }
};

test "allocator" {
    var alloc: Allocator = try .init(std.testing.allocator, 1024 * 1024 * 1024, 256 * 1024);
    defer alloc.deinit(std.testing.allocator);

    const starting_free_offset = alloc.free_offset;
    const starting_free_storage = alloc.free_storage;

    const a0 = try alloc.allocate(1337);
    const a1 = try alloc.allocate(1337);
    const a2 = try alloc.allocate(1337);
    const a3 = try alloc.allocate(1337);
    const a4 = try alloc.allocate(1337);

    alloc.free(a3);
    alloc.free(a4);
    alloc.free(a1);
    alloc.free(a0);
    alloc.free(a2);

    try std.testing.expectEqual(starting_free_offset, alloc.free_offset);
    try std.testing.expectEqual(starting_free_storage, alloc.free_storage);
}
