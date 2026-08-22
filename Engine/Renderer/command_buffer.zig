const std = @import("std");
const c = @import("C").c;
const win = @import("Window");
const GpuDevice = @import("gpu_device.zig").GpuDevice;

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const TextureFormat = @import("textures.zig").TextureFormat;

pub const CommandBufferError = error{
    FailedToAcquire,
    FailedToSubmit,
    FailedToBeginCopyPass,
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

    pub fn beginCopyPass(self: *@This()) !*c.SDL_GPUCopyPass {
        return try sdlCheck(
            @src(),
            *c.SDL_GPUCopyPass,
            c.SDL_BeginGPUCopyPass(self.toSdl()),
            CommandBufferError.FailedToBeginCopyPass,
        );
    }

    pub fn toSdl(self: *@This()) *c.SDL_GPUCommandBuffer {
        return self._sdl_command_buffer;
    }
};
