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

    b.installArtifact(shader_compiler);

    const run_shader_compiler = b.addRunArtifact(shader_compiler);
    run_shader_compiler.stdio = .inherit;
    run_shader_compiler.addDirectoryArg(b.path("Shaders/Source"));
    const compiled_shaders_dir = run_shader_compiler.addOutputDirectoryArg("compiled_shaders_dir");

    // to be used by game build.zig to run shader_compiler executable and make zig-out shader directory
    b.addNamedLazyPath("compiled_shaders", compiled_shaders_dir);

    const shader_compiler_tests = b.addTest(.{ .root_module = shader_compiler.root_module });

    const run_shader_compiler_tests = b.addRunArtifact(shader_compiler_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_shader_compiler_tests.step);

    // engine module

    const vulkan_module = b.dependency("vulkan", .{
        .registry = std.Build.LazyPath{
            .cwd_relative = b.graph.environ_map.get("VULKAN_REGISTRY_XML") orelse {
                return error.FailedToFindVulkan;
                // std.debug.panic("VULKAN_REGISTRY_XML environment var not found", .{}); // for nixos
            },
        },
    }).module("vulkan-zig");

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

    const lalg_module = b.addModule("Lalg", .{
        .root_source_file = b.path("Lalg/lalg.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lalg_tests = b.addTest(.{ .root_module = lalg_module });
    const run_lalg_tests = b.addRunArtifact(lalg_tests);
    test_step.dependOn(&run_lalg_tests.step);

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
    renderer_module.addImport("Vulkan", vulkan_module);
    renderer_module.addImport("Lalg", lalg_module);
    renderer_module.addImport("DeletionQueue", deletion_queue_module);
    renderer_module.addImport("Window", window_module);

    const engine_module = b.addModule("Engine", .{
        .root_source_file = b.path("engine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    engine_module.addImport("Lalg", lalg_module);
    engine_module.addImport("DeletionQueue", deletion_queue_module);
    engine_module.addImport("Window", window_module);
    engine_module.addImport("Renderer", renderer_module);

    for ([_]*std.Build.Module{ window_module, renderer_module, engine_module, deletion_queue_module, c_module }) |m| {
        m.addImport("Logging", logging_module);
    }

    engine_module.linkSystemLibrary("SDL3", .{ .needed = true });

    const exe_check = b.addExecutable(.{
        .name = "engine-check",
        .root_module = renderer_module,
    });
    const check_step = b.step("check", "Check if it compiles");
    check_step.dependOn(&exe_check.step);
}
