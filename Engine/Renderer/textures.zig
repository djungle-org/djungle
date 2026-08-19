const std = @import("std");

const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;

pub const TextureError = error{
    FailedToCreateGpuTexture,
    InvalidTextureUsageCombination,
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
};

pub const TextureSamples = enum {
    Count1,
    Count2,
    Count4,
    Count8,
};

pub const Texture = struct {
    _sdl_texture: *c.SDL_GPUTexture,

    /// sampler + graphics_storage_read or compute_storage_read is invalid and will return an error
    pub fn create(gpu_device: *c.SDL_GPUDevice, usage: TextureUsage, width: usize, height: usize, sample_count: TextureSamples) !@This() {
        if (usage.sampler and (usage.graphics_storage_read or usage.compute_storage_read)) {
            return TextureError.InvalidTextureUsageCombination;
        }

        const gpu_tex_info = c.SDL_GPUTextureCreateInfo{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
            .usage = @bitCast(usage),
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = switch (sample_count) {
                .Count1 => c.SDL_GPU_SAMPLECOUNT_1,
                .Count2 => c.SDL_GPU_SAMPLECOUNT_2,
                .Count4 => c.SDL_GPU_SAMPLECOUNT_4,
                .Count8 => c.SDL_GPU_SAMPLECOUNT_8,
            },
        };

        return .{
            ._sdl_buffer = try sdlCheck(
                @src(),
                *c.SDL_GPUBuffer,
                c.SDL_CreateGPUTexture(gpu_device, &gpu_tex_info),
                TextureError.FailedToCreateGpuTexture,
            ),
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *c.SDL_GPUDevice) void {
        c.SDL_ReleaseGPUTexture(gpu_device, self._sdl_texture);
    }
};
