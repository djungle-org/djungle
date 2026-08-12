const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL_gpu.h");
});

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
};

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,

    _deletion_queue: delque.DeletionQueue,

    _window: *win.Window,

    _gpu_device: *c.SDL_GPUDevice,

    pub fn init(self: *@This(), gpa: std.mem.Allocator, window: *win.Window, gpu_driver: GpuDriver, comptime app_name: [:0]const u8) !void {
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

        _ = gpa;
        _ = window;
        _ = app_name;
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
