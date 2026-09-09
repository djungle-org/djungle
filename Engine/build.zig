const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // options
    const assets_dir = b.option(
        std.Build.LazyPath,
        "assets_dir",
        "Directory containing assets for the game",
    ) orelse b.path("."); // this dummy path should always be overrided by the game build.zig, only here to test build the engine standalone

    const build_config = b.addOptions();
    build_config.addOptionPath("assets_dir", assets_dir);

    const shader_src_dir = b.option(
        std.Build.LazyPath,
        "shader_src_dir",
        "Directory containing shaders.zon and shader files",
    ) orelse b.path("."); // same here, this dummy path should always be overrided by the game build.zig, only here to test build the engine standalone

    // engine module

    const vulkan = b.dependency("vulkan", .{
        .registry = std.Build.LazyPath{
            .cwd_relative = b.graph.environ_map.get("VULKAN_REGISTRY_XML") orelse {
                return error.FailedToFindVulkan;
                // std.debug.panic("VULKAN_REGISTRY_XML environment var not found", .{}); // for nixos
            },
        },
    }).module("vulkan-zig");

    const c = b.addModule("C", .{
        .root_source_file = b.path("c.zig"),
        .target = target,
        .optimize = optimize,
    });

    c.addIncludePath(b.path("Vendor"));
    c.addCSourceFile(.{
        .file = b.path("Vendor/stb_image_impl.c"),
    });
    c.addCSourceFile(.{
        .file = b.path("Vendor/cgltf_impl.c"),
    });

    c.linkSystemLibrary("SDL3", .{ .needed = true });

    const logging = b.addModule("Logging", .{
        .root_source_file = b.path("Logging/logging.zig"),
        .target = target,
        .optimize = optimize,
    });

    const deletion_queue = b.addModule("DeletionQueue", .{
        .root_source_file = b.path("DeletionQueue/deletion_queue.zig"),
        .target = target,
        .optimize = optimize,
    });

    const core = b.addModule("Core", .{
        .root_source_file = b.path("Core/core.zig"),
        .target = target,
        .optimize = optimize,
    });

    core.addOptions("build_config", build_config);

    const time = b.addModule("Time", .{
        .root_source_file = b.path("Time/time.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lalg = b.addModule("Lalg", .{
        .root_source_file = b.path("Lalg/lalg.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lalg_tests = b.addTest(.{ .root_module = lalg });
    const run_lalg_tests = b.addRunArtifact(lalg_tests);

    const window = b.addModule("Window", .{
        .root_source_file = b.path("Window/window.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    window.addImport("C", c);

    const shaders = b.addModule("Shaders", .{
        .root_source_file = b.path("Shaders/shaders.zig"),
        .target = target,
        .optimize = optimize,
    });

    shaders.addImport("C", c);

    const input = b.addModule("Input", .{
        .root_source_file = b.path("Input/input.zig"),
        .target = target,
        .optimize = optimize,
    });

    input.addImport("C", c);
    input.addImport("Window", window);

    const events = b.addModule("Events", .{
        .root_source_file = b.path("Events/events.zig"),
        .target = target,
        .optimize = optimize,
    });

    events.addImport("C", c);
    events.addImport("Window", window);
    events.addImport("Input", input);

    const renderer = b.addModule("Renderer", .{
        .root_source_file = b.path("Renderer/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    shaders.addImport("Renderer", renderer);

    renderer.addImport("C", c);
    renderer.addImport("Vulkan", vulkan);
    renderer.addImport("Lalg", lalg);
    renderer.addImport("DeletionQueue", deletion_queue);
    renderer.addImport("Window", window);
    renderer.addImport("Shaders", shaders);
    renderer.addImport("Core", core);
    renderer.addImport("Time", time);

    for ([_]*std.Build.Module{ window, renderer, deletion_queue, c, shaders }) |m| {
        m.addImport("Logging", logging);
    }

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

    shader_compiler.root_module.addImport("Shaders", shaders);

    b.installArtifact(shader_compiler);

    const run_shader_compiler = b.addRunArtifact(shader_compiler);
    run_shader_compiler.stdio = .inherit;
    run_shader_compiler.addDirectoryArg(shader_src_dir);
    const compiled_shaders_dir = run_shader_compiler.addOutputDirectoryArg("compiled_shaders_dir");

    // to be used by game build.zig to run shader_compiler executable and make zig-out shader directory
    b.addNamedLazyPath("compiled_shaders", compiled_shaders_dir);

    const shader_compiler_tests = b.addTest(.{ .root_module = shader_compiler.root_module });

    const run_shader_compiler_tests = b.addRunArtifact(shader_compiler_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_shader_compiler_tests.step);

    test_step.dependOn(&run_lalg_tests.step);

    // exe check step

    const exe_check = b.addExecutable(.{
        .name = "engine-check",
        .root_module = renderer,
    });
    const check_step = b.step("check", "Check if it compiles");
    check_step.dependOn(&exe_check.step);
}
