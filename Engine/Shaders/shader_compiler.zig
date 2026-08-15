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
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const shader_source_path = args[1];
    const shader_source_dir = try std.Io.Dir.openDirAbsolute(init.io, shader_source_path, .{ .iterate = true });
    defer shader_source_dir.close(init.io);
    var shader_source_iter = std.Io.Dir.iterate(shader_source_dir);

    const compiled_shaders_path = args[2];
    const compiled_shaders_dir = try std.Io.Dir.openDirAbsolute(init.io, compiled_shaders_path, .{ .iterate = true });
    defer compiled_shaders_dir.close(init.io);

    const shader_data = try compiled_shaders_dir.createFile(init.io, "shaders.zon", .{});
    defer shader_data.close(init.io);

    var writer = std.Io.Writer.Allocating.init(init.arena.allocator());
    defer writer.deinit();

    while (try shader_source_iter.next(init.io)) |shader_source| {
        // handle sub directories in future
        if (shader_source.kind != .file) return error.NotAFile;

        const shader_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ shader_source_path, shader_source.name });

        const output_path = try std.mem.join(init.arena.allocator(), "", &.{ shader_source.name, ".spv" });
        const output_full_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ compiled_shaders_path, output_path });

        if (std.mem.endsWith(u8, shader_source.name, ".vert.slang")) {
            const data = ShaderData{
                .name = std.mem.cutSuffix(u8, shader_source.name, ".vert.slang").?,
                .kind = .Vertex,
            };

            try std.zon.stringify.serialize(data, .{}, &writer.writer);

            const zon_text = writer.writer.buffered();

            try shader_data.writePositionalAll(init.io, zon_text, 0);

            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, "main");
        } else if (std.mem.endsWith(u8, shader_source.name, ".frag.slang")) {
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, "main");
        } else if (std.mem.endsWith(u8, shader_source.name, ".pair.slang")) {
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, "vertMain");
            try slangcCompile(init.arena.allocator(), init.io, shader_path, output_full_path, "fragMain");
        } else {
            return error.IncorrectFileExtension;
        }
    }
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
