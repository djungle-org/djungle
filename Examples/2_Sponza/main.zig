const std = @import("std");

const rdr = @import("Renderer");
const lalg = @import("Lalg");
const win = @import("Window");
const log = @import("Logging");

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

    var window = try win.Window.init(width, height, app_name);
    defer window.deinit();

    const path_resolver = try rdr.PathResolver.init(gpa, io);
    defer path_resolver.deinit(gpa);

    var renderer: rdr.Renderer = undefined;
    try renderer.init(gpa, io, &window, .Auto, debug, &path_resolver);
    defer renderer.deinit(gpa);

    const sponza_path = try path_resolver.resolvePath(gpa, .Assets, "sponza/Sponza.gltf");
    defer gpa.free(sponza_path);

    const clock = std.Io.Clock.awake;
    const t0 = clock.now(io);

    var sponza = try rdr.mdl.Model.init(sponza_path, gpa, &renderer, &path_resolver);
    defer sponza.deinit(gpa, &renderer);

    const t1 = clock.now(io);

    log.info("model load took {d}ms", .{t1.toMilliseconds() - t0.toMilliseconds()});

    const view_proj = rdr.ViewProj{
        .view = try lalg.lookAt(.{ 0, 0, 0 }, .{ 0, 0, 2 }, .{ 0, 1, 0 }),
        .proj = lalg.perspective(width / height, std.math.degreesToRadians(60), 0.1, 100),
    };

    var running = true;
    while (running) {
        running = window.pollEvents();

        const model = lalg.mulMat(.{
            lalg.translate(.{ 0, 0, 100 }),
        });

        var draw_call: rdr.msh.DrawCall = undefined;

        for (sponza.meshes) |mesh| {
            draw_call = mesh.drawCall(model);

            try renderer.queueDrawCall(gpa, draw_call);
        }

        try renderer.render(&view_proj);
    }
}
