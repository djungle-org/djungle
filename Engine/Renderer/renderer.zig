const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL_gpu.h");
});

const vk = @import("Vulkan");
const delque = @import("DeletionQueue");
const win = @import("Window");
const log = @import("Logging");

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

    pub fn init(self: *@This(), gpa: std.mem.Allocator, window: *win.Window, comptime app_name: [:0]const u8) !void {
        self._gpu_device = c.SDL_CreateGPUDevice(0, debug, app_name) orelse {
            log.err()
            return RendererError.FailedToCreateGpuDevice;
        };
    }

    pub fn deinit(self: *@This()) void {
        self._deletion_queue.deinit(self.allocator); // deinits all the items in the queue
    }
};
