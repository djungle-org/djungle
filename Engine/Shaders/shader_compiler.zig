const std = @import("std");

const ShaderCompilerError = error{
    ShaderCompileFailed,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const shader_source_path = args[1];
    const shader_source_dir = try std.Io.Dir.openDirAbsolute(init.io, shader_source_path, .{ .iterate = true });
    defer shader_source_dir.close(init.io);
    var shader_source_iter = std.Io.Dir.iterate(shader_source_dir);

    const compiled_shaders_path = args[2];

    while (try shader_source_iter.next(init.io)) |shader_source| {
        // handle sub directories in future
        if (shader_source.kind != .file) continue;

        const shader_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ shader_source_path, shader_source.name });

        const output_path = try std.mem.join(init.arena.allocator(), "", &.{ shader_source.name, ".spv" });
        const output_full_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ compiled_shaders_path, output_path });

        if (std.mem.endsWith(u8, shader_source.name, ".vert.slang")) {
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, false);
        } else if (std.mem.endsWith(u8, shader_source.name, ".frag.slang")) {
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, false);
        } else if (std.mem.endsWith(u8, shader_source.name, ".pair.slang")) {
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, true);
        } else {
            continue;
        }
    }
}

fn slangcCompile(allocator: std.mem.Allocator, io: std.Io, shader_path: []const u8, output_path: []const u8, pair: bool) !void {
    var slangc_args = try std.ArrayList([]const u8).initCapacity(allocator, 12);
    defer slangc_args.deinit(allocator);

    try slangc_args.appendSlice(allocator, &.{ "slangc", shader_path, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name" });

    if (pair) {
        try slangc_args.appendSlice(allocator, &.{ "-entry", "vertMain", "-entry", "fragMain" });
    } else {
        try slangc_args.appendSlice(allocator, &.{ "-entry", "main" });
    }

    try slangc_args.appendSlice(allocator, &.{ "-o", output_path });

    const result = try std.process.run(allocator, io, .{
        .argv = slangc_args.items,
    });

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term != .exited or result.term.exited != 0) {
        std.log.err("slangc stderr: {s}\n", .{result.stderr});
        return ShaderCompilerError.ShaderCompileFailed;
    }
}
