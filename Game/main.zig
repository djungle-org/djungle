const std = @import("std");

const eng = @import("Engine");

const app_name = "djungle";

pub fn main(init: std.process.Init) !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);

    const gpa = switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.c_allocator,
    };

    var array_list = std.ArrayList(u32).empty;
    defer array_list.deinit(gpa);

    try array_list.append(gpa, 5);
    try array_list.append(gpa, 1);

    var window = try eng.window.Window.init(800, 800, app_name);
    defer window.deinit();

    var exe_dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try std.process.executableDirPath(init.io, &exe_dir_buf);
    const exe_dir_path = exe_dir_buf[0..len];

    var renderer: eng.renderer.Renderer = undefined;
    try renderer.init(gpa, init.io, &window, .Auto, exe_dir_path);
    defer renderer.deinit();

    var running = true;
    while (running) {
        running = window.pollEvents();

        // TEMPORARY
        try window.clear();
    }
}
