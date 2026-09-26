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

    // test vulkan
    var vulkantest: rdr.vktest.Vulkan = undefined;
    try vulkantest.init(gpa, io, &path_resolver, debug, &window, "test");
    defer vulkantest.deinit();

    // var renderer: rdr.Renderer = undefined;
    // try renderer.init(
    //     gpa,
    //     io,
    //     &path_resolver,
    //     &window,
    //     target_aspect,
    //     .Auto,
    //     debug,
    //     ._4,
    // );
    // defer renderer.deinit();
    //
    // const sponza_path = try path_resolver.resolvePath(gpa, .Assets, "sponza/Sponza.gltf");
    // defer gpa.free(sponza_path);
    //
    // var sponza = try rdr.mdl.Model.init(sponza_path, gpa, &renderer, &path_resolver);
    // defer sponza.deinit(gpa, &renderer);
    //
    // var input = ipt.Input.init();
    //
    // var camera: cam.Camera = .{};
    //
    // try window.setCursorLockAndHide(true);
    //
    // var view_proj = rdr.ViewProj{
    //     .view = lalg.identityMat(lalg.Mat4),
    //     .proj = lalg.identityMat(lalg.Mat4),
    // };
    //
    // var running = true;
    // while (running) {
    //     input.resetMouseState();
    //     running = try events.handleEvents(&window, &input);
    //
    //     const model = lalg.mulMat(.{
    //         lalg.translate(.{ 0, 0, 100 }),
    //         lalg.scale(.{ 0.1, 0.1, 0.1 }),
    //     });
    //
    //     var draw_call: rdr.msh.DrawCall = undefined;
    //
    //     for (sponza.meshes) |mesh| {
    //         draw_call = mesh.drawCall(model);
    //
    //         try renderer.queueDrawCall(draw_call);
    //     }
    //
    //     if (window.focused) {
    //         view_proj = try camera.moveAndLook(
    //             input,
    //             target_aspect,
    //             60,
    //             0.01,
    //             1000,
    //             0.01,
    //         );
    //     }
    //
    //     var command_buffer = try rdr.cmd.CommandBuffer.acquire(&renderer.gpu_device);
    //
    //     try renderer.render(&command_buffer, &view_proj);
    //
    //     try command_buffer.submit();
    // }
}
