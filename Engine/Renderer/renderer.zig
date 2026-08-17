const std = @import("std");

const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;

const delque = @import("DeletionQueue");
const win = @import("Window");
const log = @import("Logging");

const reg = @import("shader_registry.zig");
const Shader = reg.Shader;
const ShaderKind = reg.ShaderKind;
const ShaderRegistry = reg.ShaderRegistry;

/// Auto to auto choose driver, Vulkan for Linux, Direct3D12 for Windows, Metal for MacOS
pub const GpuDriver = enum {
    Auto,
    Vulkan,
    Direct3D12,
    Metal,
};

pub const RendererError = error{
    FailedToCreateGpuDevice,
    FailedToClaimWindowForGpu,
    FailedToCreateGpuShader,
};

const debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub const Renderer = struct {
    _window: *win.Window,

    _gpu_device: *c.SDL_GPUDevice,

    _shaders: ShaderRegistry,

    pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io, window: *win.Window, gpu_driver: GpuDriver, spirv_bin_dir_path: []const u8) !void {
        self._window = window;

        self._shaders = try ShaderRegistry.init(gpa);

        const gpu_driver_name: ?[]const u8 = switch (gpu_driver) {
            .Auto => null,
            .Vulkan => "vulkan",
            .Direct3D12 => "direct3d12",
            .Metal => "metal",
        };

        var vulkan_options = std.mem.zeroes(c.SDL_GPUVulkanOptions);
        const vulkan_api_version: u32 = (0 << 29) | (1 << 22) | (4 << 12) | 0; // vulkan 1.4.0
        vulkan_options.vulkan_api_version = vulkan_api_version;

        const props = c.SDL_CreateProperties();
        defer c.SDL_DestroyProperties(props);

        try sdlCheckBool(@src(), c.SDL_SetPointerProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER, &vulkan_options), error.FailedToSetSdlPointerProperty);
        try sdlCheckBool(@src(), c.SDL_SetBooleanProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true), error.FailedToSetSdlBoolProperty);
        try sdlCheckBool(@src(), c.SDL_SetBooleanProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, debug), error.FailedToSetSdlPointerProperty);
        try sdlCheckBool(@src(), c.SDL_SetStringProperty(props, c.SDL_PROP_GPU_DEVICE_CREATE_NAME_STRING, @ptrCast(gpu_driver_name)), error.FailedToSetSdlPointerProperty);

        // SPIRV for shaders so we can use slang
        self._gpu_device = c.SDL_CreateGPUDeviceWithProperties(props) orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.FailedToCreateGpuDevice;
        };

        if (!c.SDL_ClaimWindowForGPUDevice(self._gpu_device, self._window._sdl_window)) {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.FailedToClaimWindowForGpu;
        }

        try self.loadShaders(io, gpa, spirv_bin_dir_path);
    }

    pub fn deinit(self: *@This()) void {
        self._shaders.deinit(self._gpu_device);

        c.SDL_DestroyGPUDevice(self._gpu_device);
    }

    fn loadShaders(self: *@This(), io: std.Io, allocator: std.mem.Allocator, spirv_bin_dir_path: []const u8) !void {
        self._shaders.clearRetainingCapacity();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const spirv_bin_dir = try std.Io.Dir.openDirAbsolute(io, spirv_bin_dir_path, .{ .iterate = true });
        defer spirv_bin_dir.close(io);

        const binaries_zon_buf = try spirv_bin_dir.readFileAlloc(io, "shader_binaries.zon", arena, .unlimited);

        const ShaderBinary = struct {
            name: []const u8,
            path: []const u8,
            entry: []const u8,
            kind: ShaderKind,
        };

        const binaries_zon_buf_0 = try std.mem.Allocator.dupeSentinel(arena, u8, binaries_zon_buf, 0);
        const binary_files = try std.zon.parse.fromSliceAlloc([]ShaderBinary, arena, binaries_zon_buf_0, null, .{});

        for (binary_files) |binary_file| {
            const binary_buf = try spirv_bin_dir.readFileAlloc(io, binary_file.path, arena, .unlimited);

            const shader = try Shader.create(self._gpu_device, binary_buf.len * @sizeOf(u8), binary_buf, binary_file.entry, binary_file.kind);

            try self._shaders.put(binary_file.name, shader);
        }
    }
};
