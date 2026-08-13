const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const shader_source_path = args[1];
    const shader_source_dir = try std.Io.Dir.openDirAbsolute(init.io, shader_source_path, .{ .iterate = true });
    var shader_source_iter = std.Io.Dir.iterate(shader_source_dir);

    const compiled_shaders_path = args[2];
    const compiled_shaders_dir = try std.Io.Dir.openDirAbsolute(init.io, compiled_shaders_path, .{ .iterate = true });
    _ = compiled_shaders_dir;

    while (try shader_source_iter.next(init.io)) |shader_source| {
        if (shader_source.kind != .file) continue;

        const shader_buf = try shader_source_dir.readFileAlloc(init.io, shader_source.name, init.arena.allocator(), .unlimited);
        _ = shader_buf;

        // compile shader to spirv

        // write compiled binary to compiled_shaders_dir
    }
}
