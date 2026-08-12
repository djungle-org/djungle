const std = @import("std");

const DeletionEntry = struct {
    ctx: *anyopaque,
    deinitFn: *const fn (*anyopaque) void,
};

/// thin wrapper around std.deque
/// the type of the queue is a fn () void
/// push the deinit function of the object you want to queue deletion for
/// on deinit, the deletion queue will run that deinit function on all the items in the queue
pub const DeletionQueue = struct {
    _queue: std.Deque(DeletionEntry),

    pub const empty = std.Deque(DeletionEntry).empty;

    pub fn initCapacity(gpa: std.mem.Allocator, capacity: usize) !@This() {
        const queue = try std.Deque(DeletionEntry).initCapacity(gpa, capacity);

        return .{
            ._queue = queue,
        };
    }

    /// will deinit all the elements in the queue
    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        var it = self._queue.iterator();
        while (it.next()) |entry| {
            entry.deinitFn(entry.ctx);
        }

        self._queue.deinit(gpa);
    }

    /// object is the thing you want to deinit
    pub fn push(self: *@This(), gpa: std.mem.Allocator, comptime T: type, object: *T, comptime deinitFn: *const fn (*T) void) !void {
        try self._queue.pushFront(gpa, .{
            .ctx = object,
            .deinitFn = @ptrCast(deinitFn),
        });
    }
};
