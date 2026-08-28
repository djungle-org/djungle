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

    const view_proj = eng.renderer.ViewProj{
        .view = try eng.lalg.lookAt(.{ 0, 5, -10 }, .{ 0, 0, 2 }, .{ 0, 1, 0 }),
        .proj = eng.lalg.perspective(width / height, std.math.degreesToRadians(60), 0.1, 100),
    };

    var running = true;
    while (running) {
        running = window.pollEvents();

        const time = std.Io.Clock.awake.now(io);
        const now: f32 = @floatFromInt(time.toMilliseconds());

        const model = eng.lalg.mulMat(.{
            eng.lalg.translate(.{ 3 * @sin(now / 400), 0, 3 * @cos(now / 400) }),
            try eng.lalg.rotate(.{ 0, 1, 0 }, now / 400),
        });

        var draw_call = cube.drawCall(model);

        try renderer.queueDrawCall(gpa, draw_call);

        draw_call.model = eng.lalg.mulMat(.{
            eng.lalg.translate(.{ @sin(now / 200), 0, @cos(now / 200) }),
            try eng.lalg.rotate(.{ 0, 1, 0 }, now / 200),
        });

        try renderer.queueDrawCall(gpa, draw_call);

        try renderer.render(&view_proj);
    }
}
