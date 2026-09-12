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

    var bunny = try rdr.Model.init(bunny_path, gpa, &renderer, &path_resolver);
    defer bunny.deinit(gpa, &renderer);

    const light_ico_path = try path_resolver.resolvePath(gpa, .Assets, "light_icosphere/light_icosphere.gltf");
    defer gpa.free(light_ico_path);

    var light_ico = try rdr.Model.init(light_ico_path, gpa, &renderer, &path_resolver);
    defer light_ico.deinit(gpa, &renderer);

    const clock = std.Io.Clock.awake;
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

        var model = lalg.mulMat(.{
            lalg.translate(.{ 0, 0, 0 }),
            lalg.scale(.{ 10, 10, 10 }),
            try lalg.rotate(.{ 1, 0, 0 }, std.math.degreesToRadians(-90)),
        });

        var draw_call: rdr.msh.DrawCall = undefined;

        for (bunny.meshes) |mesh| {
            draw_call = mesh.drawCall(model);

            try renderer.queueDrawCall(draw_call);
        }

        const timestamp = clock.now(io);
        const now: f32 = @floatFromInt(timestamp.toMilliseconds());

        const light_pos = lalg.Vec3{ 4 * @sin(now / 400), 0, 4 * @cos(now / 400) };

        model = lalg.mulMat(.{
            lalg.translate(light_pos),
        });

        for (light_ico.meshes) |mesh| {
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

        var command_buffer = try rdr.cmd.CommandBuffer.acquire(&renderer.gpu_device);

        command_buffer.pushFragmentUniformData(
            1,
            struct { pos: lalg.Vec3 },
            &.{ .pos = light_pos },
        );

        command_buffer.pushFragmentUniformData(
            0,
            struct { pos: lalg.Vec3 },
            &.{ .pos = camera.pos },
        );

        try renderer.render(&command_buffer, &view_proj);

        try command_buffer.submit();
    }
}
