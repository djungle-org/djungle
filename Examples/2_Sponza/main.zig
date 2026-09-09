const std = @import("std");

const rdr = @import("Renderer");
const core = @import("Core");
const lalg = @import("Lalg");
const win = @import("Window");
const log = @import("Logging");
const ipt = @import("Input");
const Time = @import("Time");
const events = @import("Events");
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

    const clock = std.Io.Clock.awake;
    var t0 = clock.now(io);

    var renderer: rdr.Renderer = undefined;
    try renderer.init(gpa, io, &path_resolver, &window, .Auto, debug, ._4);
    defer renderer.deinit();

    var t1 = clock.now(io);

    log.info("renderer init took {d}ms", .{t1.toMilliseconds() - t0.toMilliseconds()});

    const sponza_path = try path_resolver.resolvePath(gpa, .Assets, "sponza/Sponza.gltf");
    defer gpa.free(sponza_path);

    t0 = clock.now(io);

    var sponza = try rdr.mdl.Model.init(sponza_path, gpa, &renderer, &path_resolver);
    defer sponza.deinit(gpa, &renderer);

    t1 = clock.now(io);

    log.info("model load took {d}ms", .{t1.toMilliseconds() - t0.toMilliseconds()});

    var time: Time = .{};

    var input = ipt.Input.init();

    var camera: cam.Camera = .{};

    try window.setCursorLockAndHide(true);

    var view_proj = rdr.ViewProj{
        .view = lalg.identityMat(lalg.Mat4),
        .proj = lalg.identityMat(lalg.Mat4),
    };

    var running = true;
    while (running) {
        input.resetMouseState();
        running = try events.handleEvents(&window, &input);

        time.calculate(io, clock);

        // log.info("ms per frame: {}", .{time.ms_per_frame});

        const model = lalg.mulMat(.{
            lalg.translate(.{ 0, 0, 100 }),
            lalg.scale(.{ 0.1, 0.1, 0.1 }),
        });

        var draw_call: rdr.msh.DrawCall = undefined;

        for (sponza.meshes) |mesh| {
            draw_call = mesh.drawCall(model);

            try renderer.queueDrawCall(draw_call);
        }

        if (window.focused) {
            view_proj = try camera.moveAndLook(
                input,
                width,
                height,
                60,
                0.01,
                1000,
                0.01,
            );
        }

        t0 = clock.now(io);
        try renderer.render(&view_proj);

        t1 = clock.now(io);

        // log.info("render took {d}ms", .{t1.toMilliseconds() - t0.toMilliseconds()});
    }
}
