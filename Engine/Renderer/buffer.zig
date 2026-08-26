const std = @import("std");
const c = @import("C").c;

const sdlCheck = @import("C").sdlCheck;
const GpuDevice = @import("gpu_device.zig").GpuDevice;

pub const BufferError = error{
    FailedToCreateGpuBuffer,
    FailedToCreateGpuTransferBuffer,
    FailedToMapTransferBuffer,
};

pub const BufferUsage = enum {
    Vertex,
    Index,
    Indirect,
    GraphicsStorageRead,
    ComputeStorageRead,
    ComputeStorageWrite,
};

pub const Region = struct {
    offset: usize,
    size: usize,
};

pub const Buffer = struct {
    /// read only
    sdl_buffer: *c.SDL_GPUBuffer,
    /// read only
    size: usize,

    pub fn init(gpu_device: *GpuDevice, usage: BufferUsage, size: usize) !@This() {
        const sdl_buf_usage: u32 = switch (usage) {
            .Vertex => c.SDL_GPU_BUFFERUSAGE_VERTEX,
            .Index => c.SDL_GPU_BUFFERUSAGE_INDEX,
            .Indirect => c.SDL_GPU_BUFFERUSAGE_INDIRECT,
            .GraphicsStorageRead => c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            .ComputeStorageRead => c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
            .ComputeStorageWrite => c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
        };

        const gpu_buf_info = c.SDL_GPUBufferCreateInfo{
            .usage = sdl_buf_usage,
            .size = @intCast(size),
        };

        return .{
            .sdl_buffer = try sdlCheck(
                @src(),
                *c.SDL_GPUBuffer,
                c.SDL_CreateGPUBuffer(gpu_device.sdl_gpu_device, &gpu_buf_info),
                BufferError.FailedToCreateGpuBuffer,
            ),
            .size = size,
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
        c.SDL_ReleaseGPUBuffer(gpu_device.sdl_gpu_device, self.sdl_buffer);
    }

    pub fn upload(self: *@This(), copy_pass: *c.SDL_GPUCopyPass, transfer_buffer: *const transfer.Upload, transfer_buffer_offset: usize, buffer_region: Region) !void {
        const transfer_buffer_loc = c.SDL_GPUTransferBufferLocation{
            .transfer_buffer = transfer_buffer.sdl_transfer_buffer,
            .offset = @intCast(transfer_buffer_offset),
        };

        const sdl_buffer_region = c.SDL_GPUBufferRegion{
            .buffer = self.sdl_buffer,
            .offset = @intCast(buffer_region.offset),
            .size = @intCast(buffer_region.size),
        };

        c.SDL_UploadToGPUBuffer(copy_pass, &transfer_buffer_loc, &sdl_buffer_region, true);
    }
};

pub const transfer = struct {
    pub const Upload = struct {
        sdl_transfer_buffer: *c.SDL_GPUTransferBuffer,

        pub fn init(gpu_device: *GpuDevice, size: usize) !@This() {
            const transer_buf_info = c.SDL_GPUTransferBufferCreateInfo{
                .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                .size = @intCast(size),
            };

            return .{
                .sdl_transfer_buffer = try sdlCheck(
                    @src(),
                    *c.SDL_GPUTransferBuffer,
                    c.SDL_CreateGPUTransferBuffer(gpu_device.sdl_gpu_device, &transer_buf_info),
                    BufferError.FailedToCreateGpuTransferBuffer,
                ),
            };
        }

        pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
            c.SDL_ReleaseGPUTransferBuffer(gpu_device.sdl_gpu_device, self.sdl_transfer_buffer);
        }

        pub fn upload(self: *@This(), gpu_device: *GpuDevice, comptime T: type, buffer: []const T) !void {
            const mem = try sdlCheck(
                @src(),
                *anyopaque,
                c.SDL_MapGPUTransferBuffer(gpu_device.sdl_gpu_device, self.sdl_transfer_buffer, true),
                BufferError.FailedToMapTransferBuffer,
            );

            const dest: [*]T = @ptrCast(@alignCast(mem));
            @memcpy(dest[0..buffer.len], buffer);

            c.SDL_UnmapGPUTransferBuffer(gpu_device.sdl_gpu_device, self.sdl_transfer_buffer);
        }
    };

    /// NEEDS IMPLEMENTING
    pub const Download = struct {};
};
