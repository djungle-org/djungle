const std = @import("std");
const c = @import("C").c;
const win = @import("Window");
const GpuDevice = @import("gpu_device.zig").GpuDevice;

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const tex = @import("textures.zig");
const TextureFormat = tex.TextureFormat;

pub const CommandBufferError = error{
    FailedToAcquire,
    FailedToSubmit,
    FailedToBeginCopyPass,
    FailedToAcquireSwapchainTexture,
};

pub const CommandBuffer = struct {
    _sdl_command_buffer: *c.SDL_GPUCommandBuffer,

    pub fn acquire(gpu_device: *GpuDevice) !@This() {
        return .{
            ._sdl_command_buffer = try sdlCheck(
                @src(),
                *c.SDL_GPUCommandBuffer,
                c.SDL_AcquireGPUCommandBuffer(gpu_device.toSdl()),
                CommandBufferError.FailedToAcquire,
            ),
        };
    }

    pub fn submit(self: *@This()) !void {
        try sdlCheckBool(@src(), c.SDL_SubmitGPUCommandBuffer(self.toSdl()), CommandBufferError.FailedToSubmit);
    }

    pub fn toSdl(self: *@This()) *c.SDL_GPUCommandBuffer {
        return self._sdl_command_buffer;
    }

    pub fn beginCopyPass(self: *@This()) !*c.SDL_GPUCopyPass {
        return try sdlCheck(
            @src(),
            *c.SDL_GPUCopyPass,
            c.SDL_BeginGPUCopyPass(self.toSdl()),
            CommandBufferError.FailedToBeginCopyPass,
        );
    }

    pub fn waitAndAcquireSwapchainTexture(self: *@This(), gpu_device: *GpuDevice, window: *win.Window) !tex.SwapchainTexture {
        var swapchain_tex: ?*c.SDL_GPUTexture = null;
        var swapchain_tex_width: u32 = undefined;
        var swapchain_tex_height: u32 = undefined;

        try sdlCheckBool(
            @src(),
            c.SDL_WaitAndAcquireGPUSwapchainTexture(
                self.toSdl(),
                window.toSdl(),
                &swapchain_tex,
                &swapchain_tex_width,
                &swapchain_tex_height,
            ),
            CommandBufferError.FailedToAcquireSwapchainTexture,
        );

        const texture = swapchain_tex orelse return CommandBufferError.FailedToAcquireSwapchainTexture;

        const format = try gpu_device.getSwapchainFormat(window);
        return tex.SwapchainTexture.create(texture, format, swapchain_tex_width, swapchain_tex_height);
    }

    /// data must be in std140 layout conventions
    pub fn pushVertexUniformData(self: *@This(), slot_idx: u32, comptime T: type, push_data: T) void {
        c.SDL_PushGPUVertexUniformData(self.toSdl(), slot_idx, push_data, @sizeOf(T));
    }
};
