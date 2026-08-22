const std = @import("std");
const c = @import("C").c;
const vk = @import("Vulkan");
const win = @import("Window");

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const TextureFormat = @import("textures.zig").TextureFormat;

pub const GpuDeviceError = error{
    FailedToCreate,
    FailedToClaimWindowForGpu,
};

/// Auto to auto choose driver, Vulkan for Linux, Direct3D12 for Windows, Metal for MacOS
pub const GpuDriver = enum {
    Auto,
    Vulkan,
    Direct3D12,
    Metal,
};

pub const GpuDevice = struct {
    _sdl_gpu_device: *c.SDL_GPUDevice,

    pub fn init(gpu_driver: GpuDriver, debug_mode: bool, window: *win.Window) !@This() {
        const gpu_driver_name: ?[]const u8 = switch (gpu_driver) {
            .Auto => null,
            .Vulkan => "vulkan",
            .Direct3D12 => "direct3d12",
            .Metal => "metal",
        };

        var draw_params_features = vk.PhysicalDeviceShaderDrawParametersFeatures{
            .shader_draw_parameters = vk.Bool32.true,
        };

        var vulkan_options = std.mem.zeroes(c.SDL_GPUVulkanOptions);
        vulkan_options.vulkan_api_version = vk.API_VERSION_1_3.toU32();
        vulkan_options.feature_list = &draw_params_features;

        const props = c.SDL_CreateProperties();
        defer c.SDL_DestroyProperties(props);

        try sdlCheckBool(
            @src(),
            c.SDL_SetPointerProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER, &vulkan_options),
            error.FailedToSetSdlPointerProperty,
        );
        try sdlCheckBool(
            @src(),
            c.SDL_SetBooleanProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true),
            error.FailedToSetSdlBoolProperty,
        );
        try sdlCheckBool(
            @src(),
            c.SDL_SetBooleanProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, debug_mode),
            error.FailedToSetSdlPointerProperty,
        );
        try sdlCheckBool(
            @src(),
            c.SDL_SetStringProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_NAME_STRING, @ptrCast(gpu_driver_name)),
            error.FailedToSetSdlPointerProperty,
        );

        // SPIRV for shaders so we can use slang
        const sdl_gpu_device = try sdlCheck(
            @src(),
            *c.SDL_GPUDevice,
            c.SDL_CreateGPUDeviceWithProperties(props),
            GpuDeviceError.FailedToCreate,
        );

        try sdlCheckBool(
            @src(),
            c.SDL_ClaimWindowForGPUDevice(sdl_gpu_device, window.toSdl()),
            GpuDeviceError.FailedToClaimWindowForGpu,
        );

        return .{
            ._sdl_gpu_device = sdl_gpu_device,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyGPUDevice(self._sdl_gpu_device);
    }

    pub fn getSwapchainFormat(self: *@This(), window: *win.Window) !TextureFormat {
        return try TextureFormat.fromSdl(c.SDL_GetGPUSwapchainTextureFormat(self.toSdl(), window.toSdl()));
    }

    pub fn toSdl(self: *@This()) *c.SDL_GPUDevice {
        return self._sdl_gpu_device;
    }
};
