const std = @import("std");

const c = @import("C").c;
const log = @import("Logging");

pub const ShaderError = enum {
    FailedToCreateGpuShader,
};

pub const ShaderKind = enum {
    Vertex,
    Fragment,
};

pub const Shader = struct {
    _sdl_gpu_shader: *c.SDL_GPUShader,

    pub fn create(gpu_device: *c.SDL_GPUDevice, code_size: usize, code: []const u8, entrypoint_name: []const u8, shader_kind: ShaderKind) !@This() {
        const shader_info = c.SDL_GPUShaderCreateInfo{
            .code_size = code_size,
            .code = code,
            .entrypoint = entrypoint_name,
            .stage = switch (shader_kind) {
                .Vertex => c.SDL_GPU_SHADERSTAGE_VERTEX,
                .Fragment => c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            },
            .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
            .num_samplers = 0,
            .num_storage_buffers = 0,
            .num_storage_textures = 0,
            .num_uniform_buffers = 0,
        };

        return .{
            ._sdl_gpu_shader = c.SDL_CreateGPUShader(gpu_device, &shader_info) orelse {
                log.err(@src(), "{s}", .{c.SDL_GetError()});
                return ShaderError.FailedToCreateGpuShader;
            },
        };
    }
};

pub const ShaderRegistry = struct {
    _shader_map: std.StringHashMap(Shader),

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{
            ._shader_map = std.StringHashMap(Shader).init(gpa),
        };
    }

    pub fn deinit(self: *@This()) void {
        self._shader_map.deinit();
    }

    pub fn clearRetainingCapacity(self: *@This()) void {
        self._shader_map.clearRetainingCapacity();
    }

    pub fn put(self: *@This(), name: [:0]const u8, shader: Shader) !void {
        try self._shader_map.put(name, shader);
    }
};
