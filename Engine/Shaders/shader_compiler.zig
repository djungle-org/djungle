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
        if (shader_source.kind != .file) continue;

        if (!(std.mem.endsWith(u8, shader_source.name, ".vert.slang") or std.mem.endsWith(u8, shader_source.name, ".frag.slang"))) {
            continue;
        }

        // compile shader to spirv

        const shader_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ shader_source_path, shader_source.name });

        const output_path = try std.mem.join(init.arena.allocator(), "", &.{ shader_source.name, ".spv" });
        const output_full_path = try std.Io.Dir.path.join(init.arena.allocator(), &.{ compiled_shaders_path, output_path });

        const slangc_args = [_][]const u8{ "slangc", shader_path, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name", "-entry", "main", "-o", output_full_path };

        const result = try std.process.run(init.arena.allocator(), init.io, .{
            .argv = &slangc_args,
        });

        defer {
            init.arena.allocator().free(result.stdout);
            init.arena.allocator().free(result.stderr);
        }

        if (result.term != .exited or result.term.exited != 0) {
            std.log.err("slangc stderr: {s}\n", .{result.stderr});
            return ShaderCompilerError.ShaderCompileFailed;
        }
    }
}
