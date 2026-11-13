const std = @import("std");
pub const vk = @import("vulkan");

const rhi = @import("root.zig");
const allocators = @import("allocators.zig");

const Context = @import("VulkanContext.zig");
const SlotPool = @import("SlotPool.zig");
const OffsetAllocator = @import("OffsetAllocator.zig").Allocator;
const OffsetAllocation = @import("OffsetAllocator.zig").Allocation;

pub const BufferAllocator = struct {
    const Slab = struct {
        const slab_size = 256 * 1024 * 1024;
        const granularity = 64;

        allocator: OffsetAllocator,
        memory: vk.DeviceMemory,
        buffer: vk.Buffer,
        device_address: u64,
    };

    ctx: *Context,
    slabs: std.ArrayList(Slab),

    pub fn init(ctx: *Context) !BufferAllocator {
        return .{
            .ctx = ctx,
            .slabs = .empty,
        };
    }

    pub fn deinit(allocator: *BufferAllocator) void {
        for (allocator.slabs.items) |*slab| {
            allocator.ctx.device.destroyBuffer(slab.buffer, null);
            allocator.ctx.device.freeMemory(slab.memory, null);
            slab.allocator.deinit(allocator.ctx.gpa);
        }
        allocator.slabs.deinit(allocator.ctx.gpa);
        allocator.* = undefined;
    }

    fn addSlab(allocator: *BufferAllocator) !void {
        // todo ensure that the slab size is within minimum limits
        const buffer_info: vk.BufferCreateInfo = .{
            .size = Slab.slab_size,
            .flags = .{ .device_address_capture_replay = allocator.ctx.config.enable_debug },
            .usage = .{
                .transfer_src = true,
                .transfer_dst = true,
                .storage_buffer = true,
                .index_buffer = true,
                .indirect_buffer = true,
                .shader_device_address = true,
            },
            .sharing_mode = .exclusive, // we only use graphics queue anyway
            .p_queue_family_indices = @ptrCast(&allocator.ctx.graphics_queue.family),
            .queue_family_index_count = 1,
        };
        const device_buffer = try allocator.ctx.device.createBuffer(&buffer_info, null);
        errdefer allocator.ctx.device.destroyBuffer(device_buffer, null);

        var dedicated_memreq: vk.MemoryDedicatedRequirements = .{
            .prefers_dedicated_allocation = .false,
            .requires_dedicated_allocation = .false,
        };
        var buffer_memreq: vk.MemoryRequirements2 = .{
            .p_next = &dedicated_memreq,
            .memory_requirements = undefined,
        };
        allocator.ctx.device.getBufferMemoryRequirements2(&.{
            .buffer = device_buffer,
        }, &buffer_memreq);
        buffer_memreq.memory_requirements.alignment = @max(
            buffer_memreq.memory_requirements.alignment,
            Slab.granularity,
        );

        var memory_type_index: u32 = undefined;
        var best_score: i32 = -999;

        const memory_types = allocator.ctx.physical_device_memory_properties.memory_types;
        const memory_type_count = allocator.ctx.physical_device_memory_properties.memory_type_count;
        for (memory_types[0..memory_type_count], 0..) |memory_type, i| {
            // hard requirements
            if (buffer_memreq.memory_requirements.memory_type_bits &
                (@as(u32, 1) << @intCast(i)) == 0) continue;
            // soft requirements
            var score: i32 = 0;
            if (memory_type.property_flags.device_local) score += 1;
            if (score > best_score) {
                best_score = score;
                memory_type_index = @intCast(i);
            }
        }

        // dedicated allocation
        const dedicated_info: vk.MemoryDedicatedAllocateInfo = .{
            .buffer = device_buffer,
        };
        const alloc_flags: vk.MemoryAllocateFlagsInfo = .{
            .device_mask = 0,
            .p_next = &dedicated_info,
            .flags = .{
                .device_address = true,
                .device_address_capture_replay = allocator.ctx.config.enable_debug,
            },
        };
        const memory = try allocator.ctx.device.allocateMemory(&.{
            .allocation_size = buffer_memreq.memory_requirements.size,
            .memory_type_index = memory_type_index,
            .p_next = &alloc_flags,
        }, null);
        errdefer allocator.ctx.device.freeMemory(memory, null);
        try allocator.ctx.device.bindBufferMemory(device_buffer, memory, 0);

        const device_address = allocator.ctx.device.getBufferDeviceAddress(&.{
            .buffer = device_buffer,
        });

        const slab = try allocator.slabs.addOne(allocator.ctx.gpa);
        errdefer _ = allocator.slabs.pop();
        slab.* = .{
            .memory = memory,
            .allocator = try .init(
                allocator.ctx.gpa,
                Slab.slab_size / Slab.granularity,
                Slab.slab_size / Slab.granularity,
            ),
            .buffer = device_buffer,
            .device_address = device_address,
        };
    }

    pub fn alloc(
        allocator: *BufferAllocator,
        size: u64,
        alignment: u64,
    ) !u64 {
        const granule_size: u32 = @intCast((size + Slab.granularity - 1) / Slab.granularity);

        // ideally there should be some allocation policy where we
        // try to allocate into the most full slab first (i think?)
        // because emptying slabs as much as possible is defragmentation
        for (allocator.slabs.items) |*slab| {
            const allocation = slab.allocator.allocate(granule_size) catch continue;
            return slab.device_address + allocation.offset * Slab.granularity;
        }

        // no allocation possible with extant slabs, make a new one
        try allocator.addSlab();
        return allocator.alloc(size, alignment);
    }
};

pub const TextureAllocator = struct {};
pub const StagingAllocator = struct {};
