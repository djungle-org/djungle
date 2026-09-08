const std = @import("std");
const c = @import("C").c;
const log = @import("Logging");
const img = @import("image.zig");
const buf = @import("buffer.zig");

const sdlCheck = @import("C").sdlCheck;
const GpuDevice = @import("gpu_device.zig").GpuDevice;

pub const SampleCount = enum {
    _1,
    _2,
    _4,
    _8,

    pub fn toSdl(self: @This()) c_uint {
        return switch (self) {
            ._1 => c.SDL_GPU_SAMPLECOUNT_1,
            ._2 => c.SDL_GPU_SAMPLECOUNT_2,
            ._4 => c.SDL_GPU_SAMPLECOUNT_4,
            ._8 => c.SDL_GPU_SAMPLECOUNT_8,
        };
    }
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
    R8G8B8A8_Unorm,
    B8G8R8A8_Unorm,
    D24_Unorm,
    D32_Float,

    pub fn toSdl(self: @This()) c_uint {
        return switch (self) {
            .R8G8B8A8_Srgb => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
            .R8G8B8A8_Unorm => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .B8G8R8A8_Unorm => c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
            .D24_Unorm => c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
            .D32_Float => c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
        };
    }

    pub fn fromSdl(sdl_format: c_uint) !TextureFormat {
        return switch (sdl_format) {
            c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB => .R8G8B8A8_Srgb,
            c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM => .R8G8B8A8_Unorm,
            c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM => .B8G8R8A8_Unorm,
            c.SDL_GPU_TEXTUREFORMAT_D24_UNORM => .D24_Unorm,
            c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT => .D32_Float,
            else => {
                log.err(@src(), "format {}", .{sdl_format});
                return Texture.Error.UnknownTextureFormat;
            },
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

    padding: u25 = 0,

    pub fn toU32(self: *const @This()) u32 {
        return @bitCast(self.*);
    }
};

pub const SamplerCreateInfo = struct {};

const Sampler = struct {
    sdl_sampler: *c.SDL_GPUSampler,

    pub const Error = error{
        FailedToCreate,
        NoSamplerCreateInfoForSamplerTexture,
    };

    pub fn init(gpu_device: *GpuDevice, create_info: SamplerCreateInfo) !@This() {
        _ = create_info;

        const sampler_info = c.SDL_GPUSamplerCreateInfo{
            .min_filter = c.SDL_GPU_FILTER_LINEAR,
            .mag_filter = c.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .mip_lod_bias = 0,
            .enable_anisotropy = false,
            .max_anisotropy = 0,
            .enable_compare = false,
            .compare_op = c.SDL_GPU_COMPAREOP_ALWAYS,
            .min_lod = 0,
            .max_lod = 0,
        };

        return .{
            .sdl_sampler = try sdlCheck(
                @src(),
                *c.SDL_GPUSampler,
                c.SDL_CreateGPUSampler(gpu_device.sdl_gpu_device, &sampler_info),
                Error.FailedToCreate,
            ),
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
        c.SDL_ReleaseGPUSampler(gpu_device.sdl_gpu_device, self.sdl_sampler);
    }
};

pub const Texture = struct {
    /// read only
    sdl_texture: *c.SDL_GPUTexture,
    /// readonly
    width: u32,
    /// readonly
    height: u32,
    /// readonly
    tex_type: TextureType,
    /// readonly
    format: TextureFormat,
    /// readonly
    usage: TextureUsage,
    /// readonly, will only be created if usage is sampler
    sampler: ?Sampler,

    pub const Error = error{
        FailedToCreateGpuTexture,
        InvalidTextureUsageCombination,
        UnknownTextureFormat,
    };

    /// sampler + graphics_storage_read or compute_storage_read is invalid and will return an error
    /// ONLY SEND IN SAMPLER CREATE INFO IF SAMPLER USAGE IS ENABLED
    pub fn init(
        gpu_device: *GpuDevice,
        tex_type: TextureType,
        format: TextureFormat,
        usage: TextureUsage,
        sampler_create_info: ?SamplerCreateInfo,
        width: u32,
        height: u32,
        sample_count: SampleCount,
    ) !@This() {
        if (usage.sampler and (usage.graphics_storage_read or usage.compute_storage_read)) {
            return Error.InvalidTextureUsageCombination;
        }

        if (usage.sampler and sampler_create_info == null) return Sampler.Error.NoSamplerCreateInfoForSamplerTexture;

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
            .sdl_texture = try sdlCheck(
                @src(),
                *c.SDL_GPUTexture,
                c.SDL_CreateGPUTexture(gpu_device.sdl_gpu_device, &gpu_tex_info),
                Error.FailedToCreateGpuTexture,
            ),
            .tex_type = tex_type,
            .format = format,
            .usage = usage,
            .sampler = if (usage.sampler) try Sampler.init(gpu_device, sampler_create_info.?) else null,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
        if (self.sampler) |*sampler| sampler.deinit(gpu_device);

        c.SDL_ReleaseGPUTexture(gpu_device.sdl_gpu_device, self.sdl_texture);
    }

    pub fn upload(self: *@This(), gpu_device: *GpuDevice, copy_pass: *c.SDL_GPUCopyPass, image: *const img.Image) !void {
        var transfer = try buf.transfer.Upload.init(gpu_device, @sizeOf(u8) * image.pixels.len);
        defer transfer.deinit(gpu_device);

        try transfer.upload(gpu_device, u8, image.pixels);

        const transfer_info = c.SDL_GPUTextureTransferInfo{
            .transfer_buffer = transfer.sdl_transfer_buffer,
            .offset = 0,
            .pixels_per_row = image.width,
            .rows_per_layer = image.height,
        };

        const dest = c.SDL_GPUTextureRegion{
            .texture = self.sdl_texture,
            .mip_level = 0,
            .layer = 0,
            .x = 0,
            .y = 0,
            .z = 0,
            .w = image.width,
            .h = image.height,
            .d = 1,
        };

        c.SDL_UploadToGPUTexture(copy_pass, &transfer_info, &dest, true);
    }
};

pub const SwapchainTexture = struct {
    /// read only
    sdl_texture: *c.SDL_GPUTexture,

    format: TextureFormat,

    width: u32,
    height: u32,

    pub fn init(
        sdl_texture: *c.SDL_GPUTexture,
        format: TextureFormat,
        width: u32,
        height: u32,
    ) !@This() {
        return .{
            .sdl_texture = sdl_texture,
            .format = format,
            .width = width,
            .height = height,
        };
    }
};
