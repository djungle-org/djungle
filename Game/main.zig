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
    defer renderer.deinit(gpa);

    var cube: eng.renderer.msh.Mesh = undefined;
    try cube.init(&renderer, &eng.renderer.msh.cube_vertices, &eng.renderer.msh.cube_indices);
    defer cube.deinit(&renderer);

    var running = true;
    while (running) {
        running = window.pollEvents();

        const time = std.Io.Clock.awake.now(io);
        const now: f32 = @floatFromInt(time.toMilliseconds());

        const model = eng.lalg.mulMat(
            eng.lalg.Mat4,
            eng.lalg.translate(.{ @sin(now / 400), 0, @cos(now / 400) + 2 }),
            try eng.lalg.rotate(.{ 0, 1, 0 }, now / 400),
        );

        try renderer.queueDrawCall(gpa, cube.drawCall(model));

        try renderer.render();
    }
}
