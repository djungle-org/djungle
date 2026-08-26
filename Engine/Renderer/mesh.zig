const std = @import("std");
const c = @import("C").c;

const buf = @import("buffer.zig");
const dev = @import("gpu_device.zig");
const cmd = @import("command_buffer.zig");
const la = @import("Lalg");

pub const Mesh = struct {
    _vertex_buffer: buf.Buffer,
    _index_buffer: buf.Buffer,

    _vertex_buf_binding: c.SDL_GPUBufferBinding,
    _index_buf_binding: c.SDL_GPUBufferBinding,

    pub fn init(self: *@This(), gpu_device: *dev.GpuDevice, comptime Vertex: type, vertices: []const Vertex, indices: []const u32) !void {
        var cmd_buf = try cmd.CommandBuffer.acquire(gpu_device);

        const vertex_buf_size = vertices.len * @sizeOf(Vertex);

        self._vertex_buffer = try buf.Buffer.init(gpu_device, .Vertex, vertex_buf_size);

        var transfer_buffer = try buf.transfer.Upload.init(gpu_device, vertex_buf_size);
        defer transfer_buffer.deinit(gpu_device);

        try transfer_buffer.upload(gpu_device, Vertex, vertices);

        self._vertex_buf_binding = c.SDL_GPUBufferBinding{
            .buffer = self._vertex_buffer.toSdl(),
            .offset = 0,
        };

        const index_buf_size = indices.len * @sizeOf(u32);

        self._index_buffer = try buf.Buffer.init(gpu_device, .Index, index_buf_size);

        var index_transfer_buf = try buf.transfer.Upload.init(gpu_device, index_buf_size);
        defer index_transfer_buf.deinit(gpu_device);

        try index_transfer_buf.upload(gpu_device, u32, indices);

        self._index_buf_binding = c.SDL_GPUBufferBinding{
            .buffer = self._index_buffer.toSdl(),
            .offset = 0,
        };

        const copy_pass = try cmd_buf.beginCopyPass();

        try self._vertex_buffer.upload(copy_pass, transfer_buffer, 0, .{
            .offset = 0,
            .size = vertex_buf_size,
        });

        try self._index_buffer.upload(copy_pass, index_transfer_buf, 0, .{
            .offset = 0,
            .size = index_buf_size,
        });

        c.SDL_EndGPUCopyPass(copy_pass);

        try cmd_buf.submit();
    }

    pub fn deinit(self: *@This(), gpu_device: *dev.GpuDevice) void {
        self._index_buffer.deinit(gpu_device);
        self._vertex_buffer.deinit(gpu_device);
    }

    /// binds the vertex and index buffer for the render pass
    pub fn bind(self: *@This(), render_pass: *c.SDL_GPURenderPass) void {
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &self._vertex_buf_binding, 1);
        c.SDL_BindGPUIndexBuffer(render_pass, &self._index_buf_binding, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
    }
};
