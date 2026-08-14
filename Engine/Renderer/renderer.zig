const std = @import("std");

const c = @import("C").c;

const delque = @import("DeletionQueue");
const win = @import("Window");
const log = @import("Logging");

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

    _shaders: std.StringHashMap(*c.SDL_GPUShader),

    pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io, window: *win.Window, gpu_driver: GpuDriver, comptime app_name: [:0]const u8) !void {
        self._window = window;

        const gpu_driver_name: ?[]const u8 = switch (gpu_driver) {
            .Auto => null,
            .Vulkan => "vulkan",
            .Direct3D12 => "direct3d12",
            .Metal => "metal",
        };

        // SPIRV for shaders so we can use slang
        self._gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, debug, @ptrCast(gpu_driver_name)) orelse {
            return RendererError.FailedToCreateGpuDevice;
        };

        if (!c.SDL_ClaimWindowForGPUDevice(self._gpu_device, self._window._sdl_window)) {
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

        const exe_dir_path: []u8 = undefined;
        _ = try std.process.executableDirPath(io, exe_dir_path);
        const spirv_bin_dir_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "..", "Shaders" });

        const spirv_bin_dir = try std.Io.Dir.openDirAbsolute(io, spirv_bin_dir_path, .{ .iterate = true });
        var spirv_bin_iter = spirv_bin_dir.iterate();

        while (try spirv_bin_iter.next(io)) |spirv_bin| {
            if (std.mem.endsWith(u8, spirv_bin.name, ".vert.slang.spv")) {
                const vert_shader_info = c.SDL_GPUShaderCreateInfo{};

                self._vertex_shader = c.SDL_CreateGPUShader(self._gpu_device, &vert_shader_info) orelse {
                    return RendererError.FailedToCreateGpuShader;
                };
            } else if (std.mem.endsWith(u8, spirv_bin.name, ".frag.slang.spv")) {
                const frag_shader_info = c.SDL_GPUShaderCreateInfo{};

                self._fragment_shader = c.SDL_CreateGPUShader(self._gpu_device, &frag_shader_info) orelse {
                    return RendererError.FailedToCreateGpuShader;
                };
            }
        }
    }
};
