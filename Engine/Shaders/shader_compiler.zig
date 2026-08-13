const std = @import("std");

const c = @cImport({
    @cInclude("slang.h");
});

pub fn main(init: std.process.Init.Minimal) !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);

    const gpa = switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.c_allocator,
    };

    var args = try init.args.iterateAllocator(gpa);

    while (args.next()) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
}

fn compileShaders(io: std.Io) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, "Shaders/Source", .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();

    while (try it.next(io)) |entry| {
        if (entry.kind == .file) {
            // entry.name
        }
    }
}
