const std = @import("std");
const c = @import("C").c;
const log = @import("Logging");

const GpuDevice = @import("gpu_device.zig").GpuDevice;

pub const ShaderError = error{
    FailedToCreateGpuShader,
};

pub const ShaderKind = enum {
    Vertex,
    Fragment,
};

pub const DescriptorCounts = struct {
    samplers: u32,
    storage_buffers: u32,
    storage_textures: u32,
    uniform_buffers: u32,
};

pub const Shader = struct {
    /// read only
    sdl_gpu_shader: *c.SDL_GPUShader,
    /// read only
    kind: ShaderKind,

    pub fn init(
        gpu_device: *GpuDevice,
        code_size: usize,
        code: []const u8,
        entrypoint_name: [:0]const u8,
        shader_kind: ShaderKind,
        descriptor_counts: DescriptorCounts,
    ) !@This() {
        const shader_info = c.SDL_GPUShaderCreateInfo{
            .code_size = code_size,
            .code = @ptrCast(code),
            .entrypoint = @ptrCast(entrypoint_name),
            .stage = switch (shader_kind) {
                .Vertex => c.SDL_GPU_SHADERSTAGE_VERTEX,
                .Fragment => c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            },
            .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
            .num_samplers = descriptor_counts.samplers,
            .num_storage_buffers = descriptor_counts.storage_buffers,
            .num_storage_textures = descriptor_counts.storage_textures,
            .num_uniform_buffers = descriptor_counts.uniform_buffers,
        };

        return .{
            .sdl_gpu_shader = c.SDL_CreateGPUShader(gpu_device.sdl_gpu_device, &shader_info) orelse {
                log.err(@src(), "{s}", .{c.SDL_GetError()});
                return ShaderError.FailedToCreateGpuShader;
            },
            .kind = shader_kind,
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
        c.SDL_ReleaseGPUShader(gpu_device.sdl_gpu_device, self.sdl_gpu_shader);
    }
};

pub const ShaderRegistryError = error{
    FailedToGetShaderFromRegistry,
};

pub const ShaderRegistry = struct {
    /// internal
    shader_map: std.StringHashMap(Shader),

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{
            .shader_map = std.StringHashMap(Shader).init(gpa),
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *GpuDevice) void {
        var iter = self.shader_map.iterator();

        while (iter.next()) |entry| {
            entry.value_ptr.deinit(gpu_device);
        }

        self.shader_map.deinit();
    }

    pub fn clearRetainingCapacity(self: *@This()) void {
        self.shader_map.clearRetainingCapacity();
    }

    pub fn put(self: *@This(), name: []const u8, shader: Shader) !void {
        try self.shader_map.put(name, shader);
    }

    pub fn get(self: *@This(), shader_name: []const u8) !Shader {
        return self.shader_map.get(shader_name) orelse {
            return ShaderRegistryError.FailedToGetShaderFromRegistry;
        };
    }
};
