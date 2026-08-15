const std = @import("std");

const sdlCheck = @import("C").sdlCheck;
const c = @import("C").c;

const delque = @import("DeletionQueue");
const win = @import("Window");
const log = @import("Logging");

const reg = @import("shader_registry.zig");
const Shader = reg.Shader;
const ShaderRegistry = reg.ShaderRegistry;

/// Auto to auto choose driver, Vulkan for Linux, Direct3D12 for Windows, Metal for MacOS
pub const GpuDriver = enum {
    Auto,
    Vulkan,
    Direct3D12,
    Metal,
};

pub const RendererError = error{
    FailedToCreateGpuDevice,
    FailedToClaimWindowForGpu,
    FailedToCreateGpuShader,
};

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub const Renderer = struct {
    _window: *win.Window,

    _gpu_device: *c.SDL_GPUDevice,

    _shaders: ShaderRegistry,

    pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io, window: *win.Window, gpu_driver: GpuDriver, comptime app_name: [:0]const u8) !void {
        self._window = window;

        self._shaders = try ShaderRegistry.init(gpa);

        const gpu_driver_name: ?[]const u8 = switch (gpu_driver) {
            .Auto => null,
            .Vulkan => "vulkan",
            .Direct3D12 => "direct3d12",
            .Metal => "metal",
        };

        // SPIRV for shaders so we can use slang
        self._gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, debug, @ptrCast(gpu_driver_name)) orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.FailedToCreateGpuDevice;
        };

        if (!c.SDL_ClaimWindowForGPUDevice(self._gpu_device, self._window._sdl_window)) {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.FailedToClaimWindowForGpu;
        }

        try self.loadShaders(io, gpa);

        _ = app_name;
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyGPUDevice(self._gpu_device);

        self._shaders.deinit();
    }

    fn loadShaders(self: *@This(), io: std.Io, gpa: std.mem.Allocator) !void {
        self._shaders.clearRetainingCapacity();

        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = try std.process.executableDirPath(io, &exe_dir_buf);
        const exe_dir_path = exe_dir_buf[0..len];

        const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "..", "Shaders" });
        defer gpa.free(spirv_bin_dir_path);

        const spirv_bin_dir = try std.Io.Dir.openDirAbsolute(io, spirv_bin_dir_path, .{ .iterate = true });
        defer spirv_bin_dir.close(io);
        var spirv_bin_iter = spirv_bin_dir.iterate();

        while (try spirv_bin_iter.next(io)) |spirv_bin| {
            _ = spirv_bin;
            // if (spirv_bin.kind != .file) return error.NotAFile;
            //
            // if (std.mem.endsWith(u8, spirv_bin.name, ".vert.slang.spv")) {
            //     const file_buf = try spirv_bin_dir.readFileAlloc(io, spirv_bin.name, gpa, .unlimited);
            //     defer gpa.destroy(file_buf);
            //
            //     const vert_shader =
            //         try Shader.create(self._gpu_device, file_buf.len * @sizeOf(u8), file_buf, "main", .Vertex);
            //
            //     const shader_name = std.mem.cutSuffix(u8, spirv_bin.name, ".spv") orelse {
            //         return error.ShaderNameIsNull;
            //     };
            //
            //     try self._shaders.put(shader_name, vert_shader);
            // } else if (std.mem.endsWith(u8, spirv_bin.name, ".frag.slang.spv")) {
            //     const file_buf = try spirv_bin_dir.readFileAlloc(io, spirv_bin.name, gpa, .unlimited);
            //     defer gpa.destroy(file_buf);
            //
            //     const frag_shader =
            //         try Shader.create(self._gpu_device, file_buf.len * @sizeOf(u8), file_buf, "main", .Fragment);
            //
            //     const shader_name = std.mem.cutSuffix(u8, spirv_bin.name, ".spv") orelse {
            //         return error.ShaderNameIsNull;
            //     };
            //
            //     try self._shaders.put(shader_name, frag_shader);
            // } else if (std.mem.endsWith(u8, spirv_bin.name, ".pair.slang.spv")) {
            //     continue;
            // } else {
            //     return error.IncorrectFileExtension;
            // }
        }
    }
};
