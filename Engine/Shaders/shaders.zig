const std = @import("std");
const c = @import("C").c;
const log = @import("Logging");

const GpuDevice = @import("Renderer").dev.GpuDevice;

pub const ShaderError = error{
    FailedToCreateGpuShader,
    ShaderCompileFailed,
    FailedToGetShaderFromRegistry,
};

/// stage 1 of shader creation
/// filled by parsing the shader .zon file
/// outputs ShaderBinary
pub const ShaderFile = struct {
    name: []const u8,
    path: []const u8,
    entry: []const u8,

    pub fn compile(self: *const @This(), allocator: std.mem.Allocator, io: std.Io, shader_source_path: []const u8, compiled_shaders_path: []const u8) !ShaderBinary {
        const shader_absolute_path = try std.Io.Dir.path.join(allocator, &.{ shader_source_path, self.path });

        const binary_name = try std.mem.join(allocator, "", &.{ self.name, ".spv" });
        const binary_output_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, binary_name });

        const reflection_name = try std.mem.join(allocator, "", &.{ self.name, ".json" });
        const reflection_json_path = try std.Io.Dir.path.join(allocator, &.{ compiled_shaders_path, reflection_name });

        const slangc_args = [_][]const u8{
            "slangc",
            shader_absolute_path,
            "-target",
            "spirv",
            "-profile",
            "spirv_1_6",
            "-emit-spirv-directly",
            "-fvk-use-entrypoint-name",
            "-entry",
            self.entry,
            "-o",
            binary_output_path,
            "-reflection-json",
            reflection_json_path,
        };

        const result = try std.process.run(allocator, io, .{
            .argv = &slangc_args,
        });

        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        if (result.term != .exited or result.term.exited != 0) {
            std.log.err("slangc stderr: {s}\n", .{result.stderr});
            return ShaderError.ShaderCompileFailed;
        }

        return .{
            .name = self.name,
            .binary_path = try std.mem.join(allocator, "", &.{ self.name, ".spv" }),
            .json_path = try std.mem.join(allocator, "", &.{ self.name, ".json" }),
        };
    }
};

/// stage 2 of shader creation
/// contains info about spirv shader binaries
pub const ShaderBinary = struct {
    name: []const u8,
    json_path: []const u8,
    binary_path: []const u8,
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

/// result of shader creation
/// contains the actual shader module used in pipeline creation
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

/// data structure for storing shaders
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

    pub fn put(self: *@This(), name: []const u8, shader: *const Shader) !void {
        try self.shader_map.put(name, shader.*);
    }

    pub fn get(self: *@This(), shader_name: []const u8) !Shader {
        return self.shader_map.get(shader_name) orelse {
            return ShaderError.FailedToGetShaderFromRegistry;
        };
    }
};

/// will clear the shader registry
/// reads shader_binaries.zon file in zig-out to create shaders which will be added to the registry
/// shader_binaries.zon contains info about the spirv shader binaries
pub fn loadShaders(io: std.Io, allocator: std.mem.Allocator, registry: *ShaderRegistry, gpu_device: *GpuDevice, spirv_bin_dir_path: []const u8) !void {
    registry.clearRetainingCapacity();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const spirv_bin_dir = try std.Io.Dir.openDirAbsolute(io, spirv_bin_dir_path, .{ .iterate = true });
    defer spirv_bin_dir.close(io);

    const binaries_zon_buf = try spirv_bin_dir.readFileAlloc(io, "shader_binaries.zon", arena, .unlimited);

    const binaries_zon_buf_0 = try arena.dupeSentinel(u8, binaries_zon_buf, 0);
    const binary_files = try std.zon.parse.fromSliceAlloc([]ShaderBinary, arena, binaries_zon_buf_0, null, .{});

    for (binary_files) |binary_file| {
        const binary_json = try spirv_bin_dir.readFileAlloc(io, binary_file.json_path, arena, .unlimited);

        const parsed = try std.json.parseFromSlice(std.json.Value, arena, binary_json, .{});
        defer parsed.deinit();

        const entrypoint = parsed.value.object.get("entryPoints").?.array.items[0].object;
        const entrypoint_name = entrypoint.get("name").?.string;
        const stage_name = entrypoint.get("stage").?.string;

        const stage: ShaderKind = if (std.mem.eql(u8, stage_name, "vertex"))
            .Vertex
        else if (std.mem.eql(u8, stage_name, "fragment"))
            .Fragment
        else
            return error.InvalidShaderStage;

        const parameters = parsed.value.object.get("parameters").?.array.items;

        var descriptor_counts = DescriptorCounts{
            .samplers = 0,
            .storage_buffers = 0,
            .storage_textures = 0,
            .uniform_buffers = 0,
        };

        for (parameters) |parameter| {
            const kind = parameter.object.get("type").?.object.get("kind").?.string;

            if (std.mem.eql(u8, kind, "constantBuffer")) {
                descriptor_counts.uniform_buffers += 1;
            } else {
                return error.InvalidDescriptorKind;
            }
        }

        const binary_buf = try spirv_bin_dir.readFileAlloc(io, binary_file.binary_path, arena, .unlimited);

        const shader = try Shader.init(
            gpu_device,
            binary_buf.len * @sizeOf(u8),
            binary_buf,
            try arena.dupeSentinel(u8, entrypoint_name, 0),
            stage,
            descriptor_counts,
        );

        try registry.put(binary_file.name, &shader);
    }
}
