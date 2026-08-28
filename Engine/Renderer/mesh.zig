const std = @import("std");
const c = @import("C").c;
const la = @import("Lalg");

const rdr = @import("renderer.zig");
const buf = @import("buffer.zig");
const dev = @import("gpu_device.zig");
const cmd = @import("command_buffer.zig");

pub const Vertex = struct {
    pos: la.Vec3,
    col: la.Vec3,
};

/// initialized with the drawCall function in a Mesh
/// can be reused with new model matrices for multiple draw calls
pub const DrawCall = struct {
    model: la.Mat4,

    vertex_buf_binding: c.SDL_GPUBufferBinding,
    index_buf_binding: c.SDL_GPUBufferBinding,
    index_count: u32,

    pub fn draw(self: *const @This(), render_pass: *c.SDL_GPURenderPass) void {
        c.SDL_BindGPUVertexBuffers(render_pass, 0, &self.vertex_buf_binding, 1);
        c.SDL_BindGPUIndexBuffer(render_pass, &self.index_buf_binding, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);

        c.SDL_DrawGPUIndexedPrimitives(render_pass, self.index_count, 1, 0, 0, 0);
    }
};

pub const Mesh = struct {
    /// internal
    vertex_buffer: buf.Buffer,
    /// internal
    index_buffer: buf.Buffer,
    /// internal
    vertex_buf_binding: c.SDL_GPUBufferBinding,
    /// internal
    index_buf_binding: c.SDL_GPUBufferBinding,
    /// internal
    index_count: u32,

    pub fn init(self: *@This(), renderer: *rdr.Renderer, vertices: []const Vertex, indices: []const u32) !void {
        self.index_count = @intCast(indices.len);

        var cmd_buf = try cmd.CommandBuffer.acquire(&renderer.gpu_device);

        const vertex_buf_size = vertices.len * @sizeOf(Vertex);

        self.vertex_buffer = try buf.Buffer.init(&renderer.gpu_device, .Vertex, vertex_buf_size);

        var transfer_buffer = try buf.transfer.Upload.init(&renderer.gpu_device, vertex_buf_size);
        defer transfer_buffer.deinit(&renderer.gpu_device);

        try transfer_buffer.upload(&renderer.gpu_device, Vertex, vertices);

        self.vertex_buf_binding = c.SDL_GPUBufferBinding{
            .buffer = self.vertex_buffer.sdl_buffer,
            .offset = 0,
        };

        const index_buf_size = indices.len * @sizeOf(u32);

        self.index_buffer = try buf.Buffer.init(&renderer.gpu_device, .Index, index_buf_size);

        var index_transfer_buf = try buf.transfer.Upload.init(&renderer.gpu_device, index_buf_size);
        defer index_transfer_buf.deinit(&renderer.gpu_device);

        try index_transfer_buf.upload(&renderer.gpu_device, u32, indices);

        self.index_buf_binding = c.SDL_GPUBufferBinding{
            .buffer = self.index_buffer.sdl_buffer,
            .offset = 0,
        };

        const copy_pass = try cmd_buf.beginCopyPass();

        try self.vertex_buffer.upload(copy_pass, &transfer_buffer, 0, .{
            .offset = 0,
            .size = vertex_buf_size,
        });

        try self.index_buffer.upload(copy_pass, &index_transfer_buf, 0, .{
            .offset = 0,
            .size = index_buf_size,
        });

        c.SDL_EndGPUCopyPass(copy_pass);

        try cmd_buf.submit();
    }

    pub fn deinit(self: *@This(), renderer: *rdr.Renderer) void {
        self.index_buffer.deinit(&renderer.gpu_device);
        self.vertex_buffer.deinit(&renderer.gpu_device);
    }

    /// binds vertex and index buffer and draws them
    /// model matrix encodes position, rotation, and scale of the mesh to be drawn
    pub fn drawCall(self: *const @This(), model: la.Mat4) DrawCall {
        return .{
            .model = model,
            .vertex_buf_binding = self.vertex_buf_binding,
            .index_buf_binding = self.index_buf_binding,
            .index_count = self.index_count,
        };
    }
};

// cube
pub const cube_vertices = [_]Vertex{
    // top
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .col = .{ 1.0, 1.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .col = .{ 1.0, 1.0, 1.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .col = .{ 1.0, 1.0, 1.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .col = .{ 1.0, 1.0, 1.0 } },

    // bottom
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .col = .{ 1.0, 0.8, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .col = .{ 1.0, 0.8, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .col = .{ 1.0, 0.8, 0.0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .col = .{ 1.0, 0.8, 0.0 } },

    // left
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .col = .{ 1.0, 0.3, 0.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .col = .{ 1.0, 0.3, 0.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .col = .{ 1.0, 0.3, 0.0 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .col = .{ 1.0, 0.3, 0.0 } },

    // right
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .col = .{ 0.8, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .col = .{ 0.8, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .col = .{ 0.8, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .col = .{ 0.8, 0.0, 0.0 } },

    // front
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .col = .{ 0.0, 0.6, 0.3 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .col = .{ 0.0, 0.6, 0.3 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .col = .{ 0.0, 0.6, 0.3 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .col = .{ 0.0, 0.6, 0.3 } },

    // back
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .col = .{ 0.0, 0.3, 0.7 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .col = .{ 0.0, 0.3, 0.7 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .col = .{ 0.0, 0.3, 0.7 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .col = .{ 0.0, 0.3, 0.7 } },
};

pub const cube_indices = [_]u32{
    // top
    0,  1,  2,
    2,  3,  0,

    // bottom
    4,  5,  6,
    6,  7,  4,

    // left
    8,  9,  10,
    10, 11, 8,

    // right
    12, 13, 14,
    14, 15, 12,

    // front
    16, 17, 18,
    18, 19, 16,

    // back
    20, 21, 22,
    22, 23, 20,
};

// quad
pub const quad_vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5, 0.0 }, .col = .{ 1.0, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.0 }, .col = .{ 0.0, 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.0 }, .col = .{ 0.0, 0.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.0 }, .col = .{ 0.33, 0.33, 0.33 } },
};

pub const quad_indices = [_]u32{
    0, 1, 2,
    2, 3, 0,
};

// triangle
pub const triangle_vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5, 0.0 }, .col = .{ 1.0, 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.0 }, .col = .{ 0.0, 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.0 }, .col = .{ 0.0, 0.0, 1.0 } },
};

pub const triangle_indices = [_]u32{
    0, 1, 2,
};
