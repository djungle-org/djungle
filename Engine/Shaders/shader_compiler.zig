const std = @import("std");
const build_config = @import("build_config");

const sh = @import("Shaders");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const game_shader_src_path = args[1];
    const compiled_shaders_path = args[2];

    var binary_files = std.ArrayList(sh.ShaderBinary).empty;

    // engine shaders
    {
        const eng_shader_src_dir = try std.Io.Dir.openDirAbsolute(io, build_config.engine_shaders_src_dir, .{});
        defer eng_shader_src_dir.close(io);

        const eng_shaders_zon_buf = try eng_shader_src_dir.readFileAlloc(io, "shaders.zon", arena, .unlimited);
        const eng_shaders_zon_buf_0 = try arena.dupeSentinel(u8, eng_shaders_zon_buf, 0);

        const eng_shader_files = try std.zon.parse.fromSliceAlloc([]sh.ShaderFile, arena, eng_shaders_zon_buf_0, null, .{});

        for (eng_shader_files) |*shader_file| {
            const binary = try shader_file.compile(
                arena,
                io,
                build_config.engine_shaders_src_dir,
                compiled_shaders_path,
            );

            try binary_files.append(arena, binary);
        }
    }

    // game shaders
    {
        const shader_src_dir = try std.Io.Dir.openDirAbsolute(io, game_shader_src_path, .{});
        defer shader_src_dir.close(io);

        const shaders_zon_buf = try shader_src_dir.readFileAlloc(io, "shaders.zon", arena, .unlimited);
        const shaders_zon_buf_0 = try arena.dupeSentinel(u8, shaders_zon_buf, 0);

        const shader_files = try std.zon.parse.fromSliceAlloc([]sh.ShaderFile, arena, shaders_zon_buf_0, null, .{});

        for (shader_files) |*shader_file| {
            const binary = try shader_file.compile(
                arena,
                io,
                game_shader_src_path,
                compiled_shaders_path,
            );

            try binary_files.append(arena, binary);
        }
    }

    // writing to binaries zon
    const binaries_zon_path = try std.Io.Dir.path.join(arena, &.{ compiled_shaders_path, "shader_binaries.zon" });
    const binaries_zon = try std.Io.Dir.createFileAbsolute(io, binaries_zon_path, .{});
    defer binaries_zon.close(io);

    var writer = std.Io.Writer.Allocating.init(arena);
    defer writer.deinit();

    try std.zon.stringify.serialize(binary_files.items, .{}, &writer.writer);

    const zon_buf = writer.writer.buffered();

    try binaries_zon.writePositionalAll(io, zon_buf, 0);
}

test "parses shader zon with correct fields" {
    const zon_text: []const u8 =
        \\.{
        \\    .{ .name = "simple_frag", .path = "simple_frag.slang", .entry = "fragMain", },
        \\}
    ;

    const zon_text_0 = try std.testing.allocator.dupeSentinel(u8, zon_text, 0);
    defer std.testing.allocator.free(zon_text_0);

    const parsed = try std.zon.parse.fromSliceAlloc([]sh.ShaderFile, std.testing.allocator, zon_text_0, null, .{});
    defer std.zon.parse.free(std.testing.allocator, parsed);

    try std.testing.expectEqual(1, parsed.len);
    try std.testing.expectEqualStrings("simple_frag", parsed[0].name);
}
