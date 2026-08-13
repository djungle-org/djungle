const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_module = b.dependency("Engine", .{
        .target = target,
        .optimize = optimize,
    }).module("Engine");

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

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run executable");
    run_step.dependOn(&run_exe.step);
}
