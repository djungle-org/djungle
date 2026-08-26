const std = @import("std");
const eng = @import("Engine");

const width = 800;
const height = 800;
const app_name = "djungle";

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var window = try eng.window.Window.init(width, height, app_name);
    defer window.deinit();

    const exe_dir_path = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(exe_dir_path);

    const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
    defer gpa.free(spirv_bin_dir_path);

    var renderer: eng.renderer.Renderer = undefined;
    try renderer.init(gpa, io, &window, .Auto, debug, spirv_bin_dir_path);
    defer renderer.deinit();

    var running = true;
    while (running) {
        running = window.pollEvents();

        try renderer.render(io);
    }
}
