const std = @import("std");

const ShaderCompilerError = error{
    ShaderCompileFailed,
};

const ShaderKind = enum {
    Vertex,
    Fragment,
    Compute,
};

const ShaderFile = struct {
    name: [:0]const u8,
    path: [:0]const u8,
    entry: [:0]const u8,
    kind: ShaderKind,

    pub fn compile(self: @This(), allocator: std.mem.Allocator, io: std.Io, shader_source_path: []const u8, compiled_shaders_path: []const u8) !void {
        const shader_absolute_path = try std.Io.Dir.path.join(allocator, &.{ shader_source_path, self.path });

        const binary_name = try std.mem.join(allocator, "", &.{ self.name, ".spv" });
        const binary_output_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, binary_name });

        const slangc_args = [_][]const u8{ "slangc", shader_absolute_path, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name", "-entry", self.entry, "-o", binary_output_path };

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
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const shader_src_path = args[1];
    const compiled_shaders_path = args[2];

    var shader_src_dir = try std.Io.Dir.openDirAbsolute(io, shader_src_path, .{});
    defer shader_src_dir.close(io);

    const shaders_zon_buf = try shader_src_dir.readFileAlloc(io, "shaders.zon", arena, .unlimited);

    const shaders_zon_buf_0 = try std.mem.Allocator.dupeSentinel(arena, u8, shaders_zon_buf, 0);
    const shader_files = try std.zon.parse.fromSliceAlloc([]ShaderFile, arena, shaders_zon_buf_0, null, .{});

    for (shader_files) |*shader_file| {
        try shader_file.compile(arena, io, shader_src_path, compiled_shaders_path);
    }

    // const shader_source_path = args[1];
    // const shader_source_dir = try std.Io.Dir.openDirAbsolute(init.io, shader_source_path, .{ .iterate = true });
    // defer shader_source_dir.close(init.io);
    // var shader_source_iter = std.Io.Dir.iterate(shader_source_dir);
    //
    // const compiled_shaders_path = args[2];

    // var shader_data = std.ArrayList(ShaderData).empty;
    // defer shader_data.deinit(alloc);

    // while (try shader_source_iter.next(init.io)) |shader_source| {
    //     // handle sub directories in future
    //     if (shader_source.kind != .file) return error.NotAFile;
    //
    //     const shader_path = try std.Io.Dir.path.join(alloc, &.{ shader_source_path, shader_source.name });
    //
    //     const output_path = try std.mem.join(alloc, "", &.{ shader_source.name, ".spv" });
    //     const output_full_path = try std.Io.Dir.path.join(alloc, &.{ compiled_shaders_path, output_path });
    //
    //     if (std.mem.endsWith(u8, shader_source.name, ".vert.slang")) {
    //         try shader_data.append(alloc, .{
    //             .path = output_path,
    //             .kind = .Vertex,
    //         });
    //
    //         try slangcCompile(alloc, init.io, shader_path, output_full_path, "main");
    //     } else if (std.mem.endsWith(u8, shader_source.name, ".frag.slang")) {
    //         try shader_data.append(alloc, .{
    //             .path = output_path,
    //             .kind = .Fragment,
    //         });
    //
    //         try slangcCompile(alloc, init.io, shader_path, output_full_path, "main");
    //     } else {
    //         return error.IncorrectFileExtension;
    //     }
    // }

    // const compiled_shaders_dir = try std.Io.Dir.openDirAbsolute(init.io, compiled_shaders_path, .{ .iterate = true });
    // defer compiled_shaders_dir.close(init.io);
    //
    // const shader_zon = try compiled_shaders_dir.createFile(init.io, "shaders.zon", .{});
    // defer shader_zon.close(init.io);
    //
    // var writer = std.Io.Writer.Allocating.init(alloc);
    // defer writer.deinit();
    //
    // try std.zon.stringify.serialize(shader_data.items, .{}, &writer.writer);
    //
    // const zon_text = writer.writer.buffered();
    //
    // try shader_zon.writePositionalAll(init.io, zon_text, 0);
}
