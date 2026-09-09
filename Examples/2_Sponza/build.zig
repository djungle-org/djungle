const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // contains engine modules
    const engine_dep = b.dependency("Engine", .{
        .target = target,
        .optimize = optimize,
        .assets_dir = b.path("Assets"), // REQUIRED: the engine needs to know where assets are located
        .shader_src_dir = b.path("Assets/Shaders"), // REQUIRED: the engine needs to know where shaders are located
    });

    // grab whatever engine modules you need for your project
    const renderer = engine_dep.module("Renderer");
    const lalg = engine_dep.module("Lalg");
    const window = engine_dep.module("Window");
    const logging = engine_dep.module("Logging");
    const input = engine_dep.module("Input");
    const core = engine_dep.module("Core");
    const time = engine_dep.module("Time");
    const c = engine_dep.module("C");

    const exe = b.addExecutable(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    b.installArtifact(exe);

    exe.root_module.addImport("Renderer", renderer);
    exe.root_module.addImport("Lalg", lalg);
    exe.root_module.addImport("Window", window);
    exe.root_module.addImport("Logging", logging);
    exe.root_module.addImport("Input", input);
    exe.root_module.addImport("Core", core);
    exe.root_module.addImport("Time", time);
    exe.root_module.addImport("C", c);

    // REQUIRED: in order to automatically compile shaders at build time
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
