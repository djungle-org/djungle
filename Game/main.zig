const std = @import("std");

const eng = @import("Engine");

const app_name = "djungle";

pub fn main() !void {
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

    var renderer: eng.renderer.Renderer = undefined;
    try renderer.init(gpa, &window, .Auto, app_name);
    defer renderer.deinit();

    var running = true;
    while (running) {
        running = window.pollEvents();

        // TEMPORARY
        try window.clear();
    }
}
