const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // contains engine modules
    const engine_dep = b.dependency("Engine", .{
        .target = target,
        .optimize = optimize,
    });

    // grab whatever engine modules you need for your project
    const renderer_module = engine_dep.module("Renderer");
    const lalg_module = engine_dep.module("Lalg");
    const window_module = engine_dep.module("Window");

    const exe = b.addExecutable(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addImport("Renderer", renderer_module);
    exe.root_module.addImport("Lalg", lalg_module);
    exe.root_module.addImport("Window", window_module);

    b.installArtifact(exe);

    // this section is needed in order to automatically compile shaders at build time
    const compiled_shaders = engine_dep.namedLazyPath("compiled_shaders");

    const compile_shaders_step = &b.addInstallDirectory(.{
        .source_dir = compiled_shaders,
        .install_dir = .{ .custom = "Shaders" },
        .install_subdir = "",
    }).step;

    const run_cmd = b.addSystemCommand(&.{b.getInstallPath(.bin, "game")});
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run executable");
    run_step.dependOn(compile_shaders_step);
    run_step.dependOn(&run_cmd.step);
}
