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
    name: []const u8,
    path: []const u8,
    entry: []const u8,
    kind: ShaderKind,

    pub fn compile(self: @This(), allocator: std.mem.Allocator, io: std.Io, shader_source_path: []const u8, compiled_shaders_path: []const u8) ![]u8 {
        const shader_absolute_path = try std.Io.Dir.path.join(allocator, &.{ shader_source_path, self.path });

        const binary_name = try std.mem.join(allocator, "", &.{ self.name, ".spv" });
        const binary_output_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, binary_name });

        const slangc_args = [_][]const u8{
            "slangc",
            shader_absolute_path,
            "-target",
            "spirv",
            "-profile",
            "spirv_1_6",
            "-emit-spirv-directly",
            "-fvk-use-entrypoint-name",
            "-entry",
            self.entry,
            "-o",
            binary_output_path,
        };

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

        return binary_name;
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const shader_src_path = args[1];
    const compiled_shaders_path = args[2];

    const shader_src_dir = try std.Io.Dir.openDirAbsolute(io, shader_src_path, .{});
    defer shader_src_dir.close(io);

    const shaders_zon_buf = try shader_src_dir.readFileAlloc(io, "shaders.zon", arena, .unlimited);

    const shaders_zon_buf_0 = try std.mem.Allocator.dupeSentinel(arena, u8, shaders_zon_buf, 0);
    const shader_files = try std.zon.parse.fromSliceAlloc([]ShaderFile, arena, shaders_zon_buf_0, null, .{});

    for (shader_files) |*shader_file| {
        const binary_name = try shader_file.compile(arena, io, shader_src_path, compiled_shaders_path);
        shader_file.path = binary_name;
    }

    const binaries_zon_path = try std.Io.Dir.path.join(arena, &.{ compiled_shaders_path, "shader_binaries.zon" });
    const binaries_zon = try std.Io.Dir.createFileAbsolute(io, binaries_zon_path, .{});
    defer binaries_zon.close(io);

    var writer = std.Io.Writer.Allocating.init(arena);
    defer writer.deinit();

    try std.zon.stringify.serialize(shader_files, .{}, &writer.writer);

    const zon_buf = writer.writer.buffered();

    try binaries_zon.writePositionalAll(io, zon_buf, 0);
}

test "parses shader zon with correct fields" {
    const zon_text: []const u8 =
        \\.{
        \\    .{ .name = "simple_frag", .path = "simple_frag.slang", .entry = "fragMain", .kind = .Fragment },
        \\}
    ;

    const zon_text_0 = try std.mem.Allocator.dupeSentinel(std.testing.allocator, u8, zon_text, 0);
    defer std.testing.allocator.free(zon_text_0);

    const parsed = try std.zon.parse.fromSliceAlloc([]ShaderFile, std.testing.allocator, zon_text_0, null, .{});
    defer std.zon.parse.free(std.testing.allocator, parsed);

    try std.testing.expectEqual(1, parsed.len);
    try std.testing.expectEqualStrings("simple_frag", parsed[0].name);
    try std.testing.expectEqual(ShaderKind.Fragment, parsed[0].kind);
}
