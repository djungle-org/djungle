const std = @import("std");

const ShaderCompilerError = error{
    ShaderCompileFailed,
};

const ShaderKind = enum {
    Vertex,
    Fragment,
};

const ShaderData = struct {
    name: []const u8,
    kind: ShaderKind,
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    const args = try init.minimal.args.toSlice(alloc);

    const shader_source_path = args[1];
    const shader_source_dir = try std.Io.Dir.openDirAbsolute(init.io, shader_source_path, .{ .iterate = true });
    defer shader_source_dir.close(init.io);
    var shader_source_iter = std.Io.Dir.iterate(shader_source_dir);

    const compiled_shaders_path = args[2];

    var shader_data = std.ArrayList(ShaderData).empty;
    defer shader_data.deinit(alloc);

    while (try shader_source_iter.next(init.io)) |shader_source| {
        // handle sub directories in future
        if (shader_source.kind != .file) return error.NotAFile;

        const shader_path = try std.Io.Dir.path.join(alloc, &.{ shader_source_path, shader_source.name });

        const output_path = try std.mem.join(alloc, "", &.{ shader_source.name, ".spv" });
        const output_full_path = try std.Io.Dir.path.join(alloc, &.{ compiled_shaders_path, output_path });

        if (std.mem.endsWith(u8, shader_source.name, ".vert.slang")) {
            try shader_data.append(alloc, .{
                .name = std.mem.cutSuffix(u8, shader_source.name, ".vert.slang").?,
                .kind = .Vertex,
            });

            try slangcCompile(alloc, init.io, shader_path, output_full_path, "main");
        } else if (std.mem.endsWith(u8, shader_source.name, ".frag.slang")) {
            try shader_data.append(alloc, .{
                .name = std.mem.cutSuffix(u8, shader_source.name, ".frag.slang").?,
                .kind = .Fragment,
            });

            try slangcCompile(alloc, init.io, shader_path, output_full_path, "main");
        } else if (std.mem.endsWith(u8, shader_source.name, ".pair.slang")) {
            try shader_data.append(alloc, .{
                .name = std.mem.cutSuffix(u8, shader_source.name, ".pair.slang").?,
                .kind = .Vertex,
            });

            try shader_data.append(alloc, .{
                .name = std.mem.cutSuffix(u8, shader_source.name, ".pair.slang").?,
                .kind = .Fragment,
            });

            try slangcCompile(alloc, init.io, shader_path, output_full_path, "vertMain");
            try slangcCompile(alloc, init.io, shader_path, output_full_path, "fragMain");
        } else {
            return error.IncorrectFileExtension;
        }
    }

    const compiled_shaders_dir = try std.Io.Dir.openDirAbsolute(init.io, compiled_shaders_path, .{ .iterate = true });
    defer compiled_shaders_dir.close(init.io);

    const shader_zon = try compiled_shaders_dir.createFile(init.io, "shaders.zon", .{});
    defer shader_zon.close(init.io);

    var writer = std.Io.Writer.Allocating.init(alloc);
    defer writer.deinit();

    try std.zon.stringify.serialize(shader_data.items, .{}, &writer.writer);

    const zon_text = writer.writer.buffered();

    try shader_zon.writePositionalAll(init.io, zon_text, 0);
}

fn slangcCompile(allocator: std.mem.Allocator, io: std.Io, shader_path: []const u8, output_path: []const u8, entrypoint_name: []const u8) !void {
    const slangc_args = [_][]const u8{ "slangc", shader_path, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name", "-entry", entrypoint_name, "-o", output_path };

    const result = try std.process.run(allocator, io, .{
        .argv = &slangc_args,
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
