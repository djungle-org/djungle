const std = @import("std");
const vk = @import("Vulkan");
const log = @import("Logging");

pub const Error = error{
    FailedToCreateGpuShader,
    ShaderCompileFailed,
    FailedToGetShaderFromRegistry,
    InvalidShaderStage,
    InvalidDescriptorKind,
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
            return Error.ShaderCompileFailed;
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

pub const ShaderStage = enum {
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
    module: vk.ShaderModule,
    /// read only
    stage_info: vk.PipelineShaderStageCreateInfo,

    /// entrypoint name will be owned by Shader and freed by Shader
    pub fn init(
        device: vk.DeviceProxy,
        code_size: usize,
        code: []const u32,
        entrypoint_name: [:0]const u8,
        stage: ShaderStage,
        descriptor_counts: DescriptorCounts,
    ) !@This() {
        _ = descriptor_counts;

        const create_info = vk.ShaderModuleCreateInfo{
            .code_size = code_size,
            .p_code = code.ptr,
        };

        const module = try device.createShaderModule(&create_info, null);

        return .{
            .module = module,
            .stage_info = .{
                .stage = .{
                    .vertex_bit = if (stage == .Vertex) true else false,
                    .fragment_bit = if (stage == .Fragment) true else false,
                },
                .module = module,
                .p_name = entrypoint_name,
                .p_specialization_info = null,
            },
        };
    }

    pub fn deinit(self: *const @This(), gpa: std.mem.Allocator, device: vk.DeviceProxy) void {
        device.destroyShaderModule(self.module, null);
        gpa.free(self.stage_info.p_name[0 .. std.mem.len(self.stage_info.p_name) + 1]);
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

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator, device: vk.DeviceProxy) void {
        var iter = self.shader_map.iterator();

        while (iter.next()) |entry| {
            entry.value_ptr.deinit(gpa, device);
        }

        self.shader_map.deinit();
    }

    pub fn clearRetainingCapacity(self: *@This()) void {
        self.shader_map.clearRetainingCapacity();
    }

    pub fn put(self: *@This(), name: []const u8, shader: *const Shader) !void {
        try self.shader_map.put(name, shader.*);
    }

    pub fn get(self: *const @This(), shader_name: []const u8) !Shader {
        return self.shader_map.get(shader_name) orelse {
            return Error.FailedToGetShaderFromRegistry;
        };
    }
};

/// will clear the shader registry
/// reads shader_binaries.zon file in zig-out to create shaders which will be added to the registry
/// shader_binaries.zon contains info about the spirv shader binaries
pub fn loadShaders(io: std.Io, allocator: std.mem.Allocator, registry: *ShaderRegistry, device: vk.DeviceProxy, spirv_bin_dir_path: [:0]const u8) !void {
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

        const stage: ShaderStage = if (std.mem.eql(u8, stage_name, "vertex"))
            .Vertex
        else if (std.mem.eql(u8, stage_name, "fragment"))
            .Fragment
        else
            return Error.InvalidShaderStage;

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
            } else if (std.mem.eql(u8, kind, "resource")) {
                descriptor_counts.samplers += 1;
            } else {
                return Error.InvalidDescriptorKind;
            }
        }

        const binary_buf_bytes = try spirv_bin_dir.readFileAllocOptions(
            io,
            binary_file.binary_path,
            arena,
            .unlimited,
            .of(u32),
            null,
        );

        const binary_buf: []u32 = std.mem.bytesAsSlice(u32, binary_buf_bytes);

        const shader = try Shader.init(
            device,
            binary_buf.len * @sizeOf(u32),
            binary_buf,
            try allocator.dupeSentinel(u8, entrypoint_name, 0),
            stage,
            descriptor_counts,
        );

        try registry.put(binary_file.name, &shader);
    }
}
