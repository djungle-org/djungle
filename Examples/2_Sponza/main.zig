const std = @import("std");

const rdr = @import("Renderer");
const core = @import("Core");
const lalg = @import("Lalg");
const win = @import("Window");
const log = @import("Logging");
const ipt = @import("Input");
const c = @import("C").c;

const cam = @import("camera_controller.zig");

const width = 1600;
const height = 900;
const app_name = "2_Sponza";

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var window = try win.Window.init(width, height, app_name);
    defer window.deinit();

    const path_resolver = try core.PathResolver.init(gpa, io);
    defer path_resolver.deinit(gpa);

    var renderer: rdr.Renderer = undefined;
    try renderer.init(gpa, io, &path_resolver, &window, .Auto, debug, ._4);
    defer renderer.deinit();

    const sponza_path = try path_resolver.resolvePath(gpa, .Assets, "sponza/Sponza.gltf");
    defer gpa.free(sponza_path);

    const clock = std.Io.Clock.awake;
    const t0 = clock.now(io);

    var sponza = try rdr.mdl.Model.init(sponza_path, gpa, &renderer, &path_resolver);
    defer sponza.deinit(gpa, &renderer);

    const t1 = clock.now(io);

    log.info("model load took {d}ms", .{t1.toMilliseconds() - t0.toMilliseconds()});

    var input = ipt.Input.init();
    try input.setCursorLockAndHide(&window, true);

    var camera: cam.Camera = .{};

    var running = true;
    while (running) {
        input.resetMouseState();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (!window.handleEvent(&event)) running = false;
            input.handleEvent(&event);
        }

        const model = lalg.mulMat(.{
            lalg.translate(.{ 0, 0, 100 }),
            lalg.scale(.{ 0.1, 0.1, 0.1 }),
        });

        var draw_call: rdr.msh.DrawCall = undefined;

        for (sponza.meshes) |mesh| {
            draw_call = mesh.drawCall(model);

            try renderer.queueDrawCall(draw_call);
        }

        const vp_mat = try camera.moveAndLook(
            input,
            width,
            height,
            60,
            0.01,
            1000,
            0.01,
        );

        try renderer.render(&vp_mat);
    }
}
