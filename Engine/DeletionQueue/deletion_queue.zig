const std = @import("std");

const DeletionEntry = struct {
    closure: *anyopaque,
    deinitFn: *const fn (closure: *anyopaque, allocator: std.mem.Allocator) void,
};

pub const DeletionQueue = struct {
    /// internal
    queue: std.Deque(DeletionEntry),

    pub const empty = std.Deque(DeletionEntry).empty;

    pub fn initCapacity(gpa: std.mem.Allocator, capacity: usize) !@This() {
        return .{
            .queue = try std.Deque(DeletionEntry).initCapacity(gpa, capacity),
        };
    }

    /// will deinit all the elements in the queue
    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        var it = self.queue.iterator();
        while (it.next()) |entry| {
            entry.deinitFn(entry.closure, gpa);
        }

        self.queue.deinit(gpa);
    }

    pub fn push(self: *@This(), gpa: std.mem.Allocator, comptime func: anytype, args: anytype) !void {
        const Args = @TypeOf(args);
        const args_fields = @typeInfo(Args).@"struct".fields;
        const func_params = @typeInfo(@TypeOf(func)).@"fn".params;

        if (func_params.len != args_fields.len)
            @compileError("Number of function params doesn't match the number of args sent in");

        inline for (0..func_params.len) |i| {
            comptime var func_param_type = func_params[i].type.?;
            comptime var arg_field_type = args_fields[i].type;

            if (@typeInfo(func_param_type) == .optional)
                func_param_type = @typeInfo(func_param_type).optional.child;

            if (@typeInfo(arg_field_type) == .optional)
                arg_field_type = @typeInfo(arg_field_type).optional.child;

            if (func_param_type != arg_field_type)
                @compileError(std.fmt.comptimePrint(
                    "Func paramater {} doesn't match argument type sent in: {s} vs {s}",
                    .{ i, @typeName(func_param_type), @typeName(arg_field_type) },
                ));
        }

        const Closure = struct {
            args: Args,

            fn deinit(closure: *anyopaque, allocator: std.mem.Allocator) void {
                const closure_ptr: *@This() = @ptrCast(@alignCast(closure));
                @call(.auto, func, closure_ptr.args);
                allocator.destroy(closure_ptr);
            }
        };

        const closure = try gpa.create(Closure);
        closure.* = .{ .args = args };

        try self.queue.pushFront(gpa, .{
            .closure = closure,
            .deinitFn = Closure.deinit,
        });
    }
};
