const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // shader compiler executable

    const shader_compiler = b.addExecutable(.{
        .name = "shader_compiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("Shaders/shader_compiler.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    shader_compiler.root_module.linkSystemLibrary("slang", .{ .needed = true });

    b.installArtifact(shader_compiler);

    const run_shader_compiler = b.addRunArtifact(shader_compiler);

    run_shader_compiler.addDirectoryArg(b.path("Shaders/Source"));
    const compiled_shaders_dir = run_shader_compiler.addOutputDirectoryArg("compiled_shaders_dir");

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = compiled_shaders_dir,
        .install_dir = .{ .custom = "Shaders" },
        .install_subdir = "",
    }).step);

    // engine module

    const c_module = b.addModule("C", .{
        .root_source_file = b.path("c.zig"),
        .target = target,
        .optimize = optimize,
    });

    const logging_module = b.addModule("Logging", .{
        .root_source_file = b.path("Logging/logging.zig"),
        .target = target,
        .optimize = optimize,
    });

    const deletion_queue_module = b.addModule("DeletionQueue", .{
        .root_source_file = b.path("DeletionQueue/deletion_queue.zig"),
        .target = target,
        .optimize = optimize,
    });

    const window_module = b.addModule("Window", .{
        .root_source_file = b.path("Window/window.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    window_module.addImport("C", c_module);

    const renderer_module = b.addModule("Renderer", .{
        .root_source_file = b.path("Renderer/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    renderer_module.addImport("C", c_module);
    renderer_module.addImport("DeletionQueue", deletion_queue_module);
    renderer_module.addImport("Window", window_module);

    const engine_module = b.addModule("Engine", .{
        .root_source_file = b.path("engine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    engine_module.addImport("DeletionQueue", deletion_queue_module);
    engine_module.addImport("Window", window_module);
    engine_module.addImport("Renderer", renderer_module);

    for ([_]*std.Build.Module{ window_module, renderer_module, engine_module, deletion_queue_module }) |m| {
        m.addImport("Logging", logging_module);
    }

    engine_module.linkSystemLibrary("SDL3", .{ .needed = true });
}
