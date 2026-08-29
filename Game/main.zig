const std = @import("std");

const rdr = @import("Renderer");
const lalg = @import("Lalg");
const win = @import("Window");

const width = 800;
const height = 800;
const app_name = "djungle";

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

// pub fn main(init: std.process.Init) !void {
//     const gpa = init.gpa;
//     const io = init.io;
//
//     var window = try win.Window.init(width, height, app_name);
//     defer window.deinit();
//
//     const exe_dir_path = try std.process.executableDirPathAlloc(io, gpa);
//     defer gpa.free(exe_dir_path);
//
//     const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
//     defer gpa.free(spirv_bin_dir_path);
//
//     var renderer: rdr.Renderer = undefined;
//     try renderer.init(gpa, io, &window, .Auto, debug, spirv_bin_dir_path);
//     defer renderer.deinit(gpa);
//
//     var cube: rdr.msh.Mesh = undefined;
//     try cube.init(&renderer, &rdr.msh.cube_vertices, &rdr.msh.cube_indices);
//     defer cube.deinit(&renderer);
//
//     const view_proj = rdr.ViewProj{
//         .view = try lalg.lookAt(.{ 0, 8, 16 }, .{ 0, 0, 2 }, .{ 0, 1, 0 }),
//         .proj = lalg.perspective(width / height, std.math.degreesToRadians(60), 0.1, 100),
//     };
//
//     var running = true;
//     while (running) {
//         running = window.pollEvents();
//
//         const time = std.Io.Clock.awake.now(io);
//         const now: f32 = @floatFromInt(time.toMilliseconds());
//
//         const model = lalg.mulMat(.{
//             lalg.translate(.{ 6 * @sin(now / 600), 0, 6 * @cos(now / 600) }),
//             try lalg.rotate(.{ 0, 1, 0 }, now / 600),
//             lalg.scale(.{ 2, 2, 2 }),
//         });
//
//         var draw_call = cube.drawCall(model);
//
//         try renderer.queueDrawCall(gpa, draw_call);
//
//         draw_call.model = lalg.mulMat(.{
//             lalg.translate(.{ 4 * @sin(now / 400), 0, 4 * @cos(now / 400) }),
//             try lalg.rotate(.{ 0, 1, 0 }, now / 400),
//             lalg.scale(.{ 1, 1, 1 }),
//         });
//
//         try renderer.queueDrawCall(gpa, draw_call);
//
//         draw_call.model = lalg.mulMat(.{
//             lalg.translate(.{ 2 * @sin(now / 200), 0, 2 * @cos(now / 200) }),
//             try lalg.rotate(.{ 0, 1, 0 }, now / 200),
//             lalg.scale(.{ 0.5, 0.5, 0.5 }),
//         });
//
//         try renderer.queueDrawCall(gpa, draw_call);
//
//         draw_call.model = lalg.mulMat(.{
//             lalg.translate(.{ @sin(now / 100), 0, @cos(now / 100) }),
//             try lalg.rotate(.{ 0, 1, 0 }, now / 100),
//             lalg.scale(.{ 0.25, 0.25, 0.25 }),
//         });
//
//         try renderer.queueDrawCall(gpa, draw_call);
//
//         try renderer.render(&view_proj);
//     }
// }

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var window = try win.Window.init(width, height, app_name);
    defer window.deinit();

    const exe_dir_path = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(exe_dir_path);

    const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
    defer gpa.free(spirv_bin_dir_path);

    var renderer: rdr.Renderer = undefined;
    try renderer.init(gpa, io, &window, .Auto, debug, spirv_bin_dir_path);
    defer renderer.deinit(gpa);

    var quad: rdr.msh.Mesh = undefined;
    try quad.init(&renderer, &rdr.msh.quad_vertices, &rdr.msh.quad_indices);
    defer quad.deinit(&renderer);

    const view_proj = rdr.ViewProj{
        .view = try lalg.lookAt(.{ 0, 0, 2 }, .{ 0, 0, 0 }, .{ 0, 1, 0 }),
        .proj = lalg.perspective(width / height, std.math.degreesToRadians(60), 0.1, 100),
    };

    var running = true;
    while (running) {
        running = window.pollEvents();

        const model = lalg.mulMat(.{
            lalg.translate(.{ 0, 0, 0 }),
            try lalg.rotate(.{ 0, 1, 0 }, 0),
            lalg.scale(.{ 1, 1, 1 }),
        });

        const draw_call = quad.drawCall(model);

        try renderer.queueDrawCall(gpa, draw_call);

        try renderer.render(&view_proj);
    }
}
