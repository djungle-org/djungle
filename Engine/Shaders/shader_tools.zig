const std = @import("std");

pub const ShaderCompilerError = error{
    ShaderCompileFailed,
};

pub const ShaderBinary = struct {
    name: []const u8,
    json_path: []const u8,
    binary_path: []const u8,
};

pub const ShaderFile = struct {
    name: []const u8,
    path: []const u8,
    entry: []const u8,

    pub fn compile(self: @This(), allocator: std.mem.Allocator, io: std.Io, shader_source_path: []const u8, compiled_shaders_path: []const u8) !ShaderBinary {
        const shader_absolute_path = try std.Io.Dir.path.join(allocator, &.{ shader_source_path, self.path });

        const binary_name = try std.mem.join(allocator, "", &.{ self.name, ".spv" });
        const binary_output_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, binary_name });

        const reflection_name = try std.mem.join(allocator, "", &.{ self.name, ".json" });
        const reflection_json_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, reflection_name });

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
            "-reflection-json",
            reflection_json_path,
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

        return .{
            .name = self.name,
            .binary_path = try std.mem.join(allocator, "", &.{ self.name, ".spv" }),
            .json_path = try std.mem.join(allocator, "", &.{ self.name, ".json" }),
        };
    }
};
