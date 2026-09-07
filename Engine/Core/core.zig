const std = @import("std");
const build_config = @import("build_config");

pub const PathKind = enum {
    Assets,
    ShaderBinaries,
};

pub const PathResolver = struct {
    /// readonly
    assets_path: [:0]const u8,
    /// readonly
    shader_bins_path: [:0]const u8,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) !@This() {
        const exe_dir_path = try std.process.executableDirPathAlloc(io, gpa);
        defer gpa.free(exe_dir_path);

        const shader_bins_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
        defer gpa.free(shader_bins_path);

        return .{
            .assets_path = try gpa.dupeSentinel(u8, build_config.assets_dir, 0),
            .shader_bins_path = try gpa.dupeSentinel(u8, shader_bins_path, 0),
        };
    }

    pub fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
        gpa.free(self.assets_path);
        gpa.free(self.shader_bins_path);
    }

    /// kind: Assets will find path relative to assets folder, ShaderBinaries will find path relative to zig-out shaders folder
    /// returned slice is owned by the caller
    pub fn resolvePath(self: *const @This(), gpa: std.mem.Allocator, kind: PathKind, relative: []const u8) ![:0]const u8 {
        const joined: []u8 = switch (kind) {
            .Assets => try std.Io.Dir.path.join(gpa, &.{ self.assets_path, relative }),
            .ShaderBinaries => try std.Io.Dir.path.join(gpa, &.{ self.shader_bins_path, relative }),
        };

        defer gpa.free(joined);

        return try gpa.dupeSentinel(u8, joined, 0);
    }

    /// returned slice is owned by the caller
    pub fn combine(_: *const @This(), gpa: std.mem.Allocator, absolute: []const u8, relative: []const u8) ![:0]const u8 {
        const joined = try std.Io.Dir.path.join(gpa, &.{ absolute, relative });
        defer gpa.free(joined);

        return try gpa.dupeSentinel(u8, joined, 0);
    }
};
