const std = @import("std");
const c = @import("C").c;
const win = @import("Window");
const GpuDevice = @import("gpu_device.zig").GpuDevice;

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const tex = @import("textures.zig");
const TextureFormat = tex.TextureFormat;

pub const CommandBuffer = struct {
    /// read only
    sdl_command_buffer: *c.SDL_GPUCommandBuffer,

    pub const Error = error{
        FailedToAcquire,
        FailedToSubmit,
        FailedToBeginCopyPass,
        FailedToBeginRenderPass,
        FailedToAcquireSwapchainTexture,
    };

    pub fn acquire(gpu_device: *GpuDevice) !@This() {
        return .{
            .sdl_command_buffer = try sdlCheck(
                @src(),
                *c.SDL_GPUCommandBuffer,
                c.SDL_AcquireGPUCommandBuffer(gpu_device.sdl_gpu_device),
                Error.FailedToAcquire,
            ),
        };
    }

    pub fn submit(self: *@This()) !void {
        try sdlCheckBool(@src(), c.SDL_SubmitGPUCommandBuffer(self.sdl_command_buffer), Error.FailedToSubmit);
    }

    pub fn beginCopyPass(self: *@This()) !*c.SDL_GPUCopyPass {
        return try sdlCheck(
            @src(),
            *c.SDL_GPUCopyPass,
            c.SDL_BeginGPUCopyPass(self.sdl_command_buffer),
            Error.FailedToBeginCopyPass,
        );
    }

    pub fn beginRenderPass(self: *@This(), color_target_info: *const c.SDL_GPUColorTargetInfo, depth_stencil_target_info: *const c.SDL_GPUDepthStencilTargetInfo) !*c.SDL_GPURenderPass {
        return try sdlCheck(
            @src(),
            *c.SDL_GPURenderPass,
            c.SDL_BeginGPURenderPass(
                self.sdl_command_buffer,
                color_target_info,
                1,
                depth_stencil_target_info,
            ),
            Error.FailedToBeginRenderPass,
        );
    }

    /// if returns null, skip rendering for the frame, this means that the window has resized
    pub fn waitAndAcquireSwapchainTexture(self: *@This(), gpu_device: *GpuDevice, window: *win.Window) !?tex.SwapchainTexture {
        var swapchain_tex: ?*c.SDL_GPUTexture = null;
        var swapchain_tex_width: u32 = undefined;
        var swapchain_tex_height: u32 = undefined;

        try sdlCheckBool(
            @src(),
            c.SDL_WaitAndAcquireGPUSwapchainTexture(
                self.sdl_command_buffer,
                window.sdl_window,
                &swapchain_tex,
                &swapchain_tex_width,
                &swapchain_tex_height,
            ),
            Error.FailedToAcquireSwapchainTexture,
        );

        const texture = swapchain_tex orelse return null;

        const format = try gpu_device.getSwapchainFormat(window);
        return try tex.SwapchainTexture.init(texture, format, swapchain_tex_width, swapchain_tex_height);
    }

    /// data must be in std140 layout conventions
    pub fn pushVertexUniformData(self: *@This(), slot_idx: u32, comptime T: type, push_data: *const T) void {
        c.SDL_PushGPUVertexUniformData(self.sdl_command_buffer, slot_idx, @ptrCast(push_data), @sizeOf(T));
    }
};
