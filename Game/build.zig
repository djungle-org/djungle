const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_dep = b.dependency("Engine", .{
        .target = target,
        .optimize = optimize,
    });
    const engine_module = engine_dep.module("Engine");

    const exe = b.addExecutable(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addImport("Engine", engine_module);

    b.installArtifact(exe);

    const compiled_shaders = engine_dep.namedLazyPath("compiled_shaders");
    // b.getInstallStep().dependOn(&b.addInstallDirectory(.{
    //     .source_dir = compiled_shaders,
    //     .install_dir = .{ .custom = "Shaders" },
    //     .install_subdir = "",
    // }).step);

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
