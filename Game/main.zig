const std = @import("std");

const eng = @import("Engine");

const width = 800;
const height = 800;
const app_name = "djungle";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var array_list = std.ArrayList(u32).empty;
    defer array_list.deinit(gpa);

    try array_list.append(gpa, 5);
    try array_list.append(gpa, 1);

    var window = try eng.window.Window.init(width, height, app_name);
    defer window.deinit();

    var exe_dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try std.process.executableDirPath(init.io, &exe_dir_buf);
    const exe_dir_path = exe_dir_buf[0..len];

    const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
    defer gpa.free(spirv_bin_dir_path);

    var renderer: eng.renderer.Renderer = undefined;
    try renderer.init(gpa, init.io, &window, .Auto, spirv_bin_dir_path);
    defer renderer.deinit();

    var running = true;
    while (running) {
        running = window.pollEvents();

        try renderer.render();
    }
}
