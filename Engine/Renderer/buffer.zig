const std = @import("std");

const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;

const BufferError = error{
    FailedToCreateGpuBuffer,
};

const BufferUsage = enum {
    Vertex,
    Index,
    Indirect,
    GraphicsStorageRead,
    ComputeStorageRead,
    ComputeStorageWrite,
};

const Buffer = struct {
    _sdl_buffer: *c.SDL_GPUBuffer,

    pub fn create(gpu_device: *c.SDL_GPUDevice, usage: BufferUsage, size: usize) !@This() {
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
            .size = size,
        };

        return .{
            ._sdl_buffer = try sdlCheck(@src(), c.SDL_CreateGPUBuffer(gpu_device, &gpu_buf_info), BufferError.FailedToCreateGpuBuffer),
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *c.SDL_GPUDevice) void {
        c.SDL_ReleaseGPUBuffer(gpu_device, self._sdl_buffer);
    }
};

const TransferBufferUsage = enum {
    Upload,
    Download,
};

const TransferBuffer = struct {
    _sdl_transfer_buffer: *c.SDL_GPUTransferBuffer,

    pub fn create(gpu_device: *c.SDL_GPUDevice, usage: TransferBufferUsage, size: usize) !@This() {
        const transer_buf_info = c.SDL_GPUTransferBufferCreateInfo{
            .usage = switch (usage) {
                .Upload => c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                .Download => c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
            },
            .size = size,
        };

        return .{
            ._sdl_transfer_buffer = try sdlCheck(@src(), c.SDL_CreateGPUTransferBuffer(gpu_device, &transer_buf_info), BufferError.FailedToCreateGpuTransferBuffer),
        };
    }
};
