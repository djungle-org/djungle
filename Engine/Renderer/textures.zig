const std = @import("std");

const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;

const types = @import("types.zig");

pub const TextureError = error{
    FailedToCreateGpuTexture,
    InvalidTextureUsageCombination,
};

pub const TextureType = enum {
    _2d,
    _2dArray,
    _3d,
    Cube,
    CubeArray,

    pub fn toSdl(self: @This()) c_uint {
        return switch (self) {
            ._2d => c.SDL_GPU_TEXTURETYPE_2D,
            ._2dArray => c.SDL_GPU_TEXTURETYPE_2D_ARRAY,
            ._3d => c.SDL_GPU_TEXTURETYPE_3D,
            .Cube => c.SDL_GPU_TEXTURETYPE_CUBE,
            .CubeArray => c.SDL_GPU_TEXTURETYPE_CUBE_ARRAY,
        };
    }
};

pub const TextureFormat = enum {
    R8G8B8A8_Srgb,
    D24_Unorm,
    D32_Float,

    pub fn toSdl(self: @This()) c_uint {
        return switch (self) {
            .R8G8B8A8_Srgb => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
            .D24_Unorm => c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
            .D32_Float => c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        };
    }
};

/// sampler + graphics_storage_read or compute_storage_read is invalid
pub const TextureUsage = packed struct {
    /// Texture supports sampling
    sampler: bool = false,
    /// Texture is a color render target
    color_target: bool = false,
    /// Texture is a depth stencil target
    depth_stencil_target: bool = false,
    /// Texture supports storage reads in graphics stages
    graphics_storage_read: bool = false,
    /// Texture supports storage reads in the compute stage
    compute_storage_read: bool = false,
    /// Texture supports storage writes in the compute stage
    compute_storage_write: bool = false,
    /// Texture supports reads and writes in the same compute shader. This is NOT equivalent to READ | WRITE
    compute_storage_simultaneous_read_write: bool = false,

    _padding: u25 = 0,

    pub fn toU32(self: @This()) u32 {
        return @bitCast(self);
    }
};

pub const Texture = struct {
    _sdl_texture: *c.SDL_GPUTexture,

    tex_type: TextureType,
    format: TextureFormat,
    usage: TextureUsage,

    /// sampler + graphics_storage_read or compute_storage_read is invalid and will return an error
    pub fn create(
        gpu_device: *c.SDL_GPUDevice,
        tex_type: TextureType,
        format: TextureFormat,
        usage: TextureUsage,
        width: u32,
        height: u32,
        sample_count: types.SampleCount,
    ) !@This() {
        if (usage.sampler and (usage.graphics_storage_read or usage.compute_storage_read)) {
            return TextureError.InvalidTextureUsageCombination;
        }

        const gpu_tex_info = c.SDL_GPUTextureCreateInfo{
            .type = tex_type.toSdl(),
            .format = format.toSdl(),
            .usage = usage.toU32(),
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = switch (sample_count) {
                ._1 => c.SDL_GPU_SAMPLECOUNT_1,
                ._2 => c.SDL_GPU_SAMPLECOUNT_2,
                ._4 => c.SDL_GPU_SAMPLECOUNT_4,
                ._8 => c.SDL_GPU_SAMPLECOUNT_8,
            },
        };

        return .{
            ._sdl_texture = try sdlCheck(
                @src(),
                *c.SDL_GPUTexture,
                c.SDL_CreateGPUTexture(gpu_device, &gpu_tex_info),
                TextureError.FailedToCreateGpuTexture,
            ),
            .tex_type = tex_type,
            .format = format,
            .usage = usage,
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *c.SDL_GPUDevice) void {
        c.SDL_ReleaseGPUTexture(gpu_device, self._sdl_texture);
    }

    /// needs to be implemented
    pub fn upload(self: *@This(), gpu_device: *c.SDL_GPUDevice) void {
        _ = self;
        _ = gpu_device;
    }

    pub fn toSdl(self: *@This()) *c.SDL_GPUTexture {
        return self._sdl_texture;
    }
};
