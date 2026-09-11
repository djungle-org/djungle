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
const target_aspect: f32 = @as(f32, width) / @as(f32, height);
const app_name = "3_Simple_Lighting";

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
    try renderer.init(
        gpa,
        io,
        &path_resolver,
        &window,
        target_aspect,
        .Auto,
        debug,
        ._4,
    );
    defer renderer.deinit();

    const bunny_path = try path_resolver.resolvePath(gpa, .Assets, "stanford_bunny/scene.gltf");
    defer gpa.free(bunny_path);

    const clock = std.Io.Clock.awake;
    const t0 = clock.now(io);

    var bunny = try rdr.mdl.Model.init(bunny_path, gpa, &renderer, &path_resolver);
    defer bunny.deinit(gpa, &renderer);

    const t1 = clock.now(io);

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
            lalg.translate(.{ 0, 0, 0 }),
            lalg.scale(.{ 10, 10, 10 }),
            try lalg.rotate(.{ 1, 0, 0 }, std.math.degreesToRadians(-90)),
        });

        var draw_call: rdr.msh.DrawCall = undefined;

        for (bunny.meshes) |mesh| {
            draw_call = mesh.drawCall(model);

            try renderer.queueDrawCall(draw_call);
        }

        if (window.focused) {
            view_proj = try camera.moveAndLook(
                input,
                target_aspect,
                60,
                0.01,
                1000,
                0.01,
                0.02,
            );
        }

        try renderer.render(&view_proj);
    }
}
