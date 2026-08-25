const std = @import("std");
const c = @import("C").c;
const win = @import("Window");
const log = @import("Logging");
const vk = @import("Vulkan");
const t = @import("types.zig");
const reg = @import("shader_registry.zig");
const buf = @import("buffer.zig");
const tex = @import("textures.zig");
const dev = @import("gpu_device.zig");
const cmd = @import("command_buffer.zig");
const lalg = @import("Lalg");
const st = @import("ShaderTools");

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const Shader = reg.Shader;
const ShaderKind = reg.ShaderKind;
const ShaderRegistry = reg.ShaderRegistry;

pub const RendererError = error{
    FailedToCreateGpuDevice,
    FailedToClaimWindowForGpu,
    FailedToCreateGpuShader,
    FailedToAcquireGpuCommandBuffer,
    FailedToBeginGpuCopyPass,
    FailedToSubmitGpuCommandBuffer,
    FailedToCreateGpuGraphicsPipeline,
    FailedToBeginRenderPass,
    FailedToAcquireSwapchainTexture,
};

const Vertex = struct {
    pos: lalg.Vec2,
    col: lalg.Vec3,
};

const Matrices = struct {
    model: lalg.Mat4,
    view: lalg.Mat4,
    proj: lalg.Mat4,
};

pub const Renderer = struct {
    _window: *win.Window,
    _swapchain_format: tex.TextureFormat,
    _gpu_device: dev.GpuDevice,
    _depth_tex: tex.Texture,
    _vertex_buffer: buf.Buffer,
    _vertex_buf_binding: c.SDL_GPUBufferBinding,
    _graphics_pipeline: *c.SDL_GPUGraphicsPipeline,
    _shaders: ShaderRegistry,

    pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io, window: *win.Window, gpu_driver: dev.GpuDriver, debug: bool, spirv_bin_dir_path: []const u8) !void {
        self._window = window;

        self._gpu_device = try dev.GpuDevice.init(gpu_driver, debug, self._window);

        self._swapchain_format = try self._gpu_device.getSwapchainFormat(self._window);

        self._shaders = try ShaderRegistry.init(gpa);
        try self.loadShaders(io, gpa, spirv_bin_dir_path);

        try self.uploadToVertexBuffer();

        self._vertex_buf_binding = c.SDL_GPUBufferBinding{
            .buffer = self._vertex_buffer.toSdl(),
            .offset = 0,
        };

        const vertex_buf_description = c.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(Vertex),
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
        };

        const vertex_attribs = [_]c.SDL_GPUVertexAttribute{
            .{ // pos
                .location = 0,
                .buffer_slot = 0,
                .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
                .offset = 0,
            },
            .{ // col
                .location = 1,
                .buffer_slot = 0,
                .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                .offset = @sizeOf(lalg.Vec2),
            },
        };

        self._depth_tex = try tex.Texture.create(
            &self._gpu_device,
            ._2d,
            .D32_Float,
            .{ .depth_stencil_target = true },
            window._width,
            window._height,
            ._1,
        );

        const color_target_description = c.SDL_GPUColorTargetDescription{
            .format = self._swapchain_format.toSdl(),
            .blend_state = .{
                .enable_blend = true,
                .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
                .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
                .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
                .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
                .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
                .enable_color_write_mask = false,
            },
        };

        var vert_shader = try self._shaders.get("simple_vert");
        var frag_shader = try self._shaders.get("simple_frag");

        const gfx_pipeline_info = c.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = vert_shader.toSdl(),
            .fragment_shader = frag_shader.toSdl(),
            .vertex_input_state = .{
                .num_vertex_buffers = 1,
                .vertex_buffer_descriptions = &vertex_buf_description,
                .num_vertex_attributes = vertex_attribs.len,
                .vertex_attributes = &vertex_attribs,
            },
            .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = .{
                .fill_mode = c.SDL_GPU_FILLMODE_FILL,
                .cull_mode = c.SDL_GPU_CULLMODE_NONE, // CHANGE LATER
                .front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
                .enable_depth_bias = false,
                .depth_bias_constant_factor = 0, // these dont need to be added since depth bias is off
                .depth_bias_clamp = 0, // <--
                .depth_bias_slope_factor = 0, // <--
                .enable_depth_clip = true,
            },
            .multisample_state = .{
                .sample_count = t.SampleCount.toSdl(._1),
                .enable_alpha_to_coverage = false,
            },
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = false,
                .compare_op = c.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
                .enable_stencil_test = false,
                .back_stencil_state = .{ // all this can be ignored if enable stencil test is false
                    .compare_op = c.SDL_GPU_COMPAREOP_ALWAYS,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_KEEP,
                    .fail_op = c.SDL_GPU_STENCILOP_KEEP,
                    .pass_op = c.SDL_GPU_STENCILOP_KEEP,
                },
                .front_stencil_state = .{
                    .compare_op = c.SDL_GPU_COMPAREOP_ALWAYS,
                    .depth_fail_op = c.SDL_GPU_STENCILOP_KEEP,
                    .fail_op = c.SDL_GPU_STENCILOP_KEEP,
                    .pass_op = c.SDL_GPU_STENCILOP_KEEP,
                },
                .compare_mask = 0,
                .write_mask = 0,
            },
            .target_info = .{
                .num_color_targets = 1,
                .color_target_descriptions = &color_target_description,
                .has_depth_stencil_target = true,
                .depth_stencil_format = self._depth_tex.format.toSdl(),
            },
        };

        self._graphics_pipeline = try sdlCheck(
            @src(),
            *c.SDL_GPUGraphicsPipeline,
            c.SDL_CreateGPUGraphicsPipeline(self._gpu_device.toSdl(), &gfx_pipeline_info),
            RendererError.FailedToCreateGpuGraphicsPipeline,
        );
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_ReleaseGPUGraphicsPipeline(self._gpu_device.toSdl(), self._graphics_pipeline);

        self._depth_tex.deinit(&self._gpu_device);

        self._vertex_buffer.deinit(&self._gpu_device);

        self._shaders.deinit(&self._gpu_device);

        self._gpu_device.deinit();
    }

    pub fn render(self: *@This(), io: std.Io) !void {
        var command_buffer = try cmd.CommandBuffer.acquire(&self._gpu_device);

        var swapchain_tex = try command_buffer.waitAndAcquireSwapchainTexture(&self._gpu_device, self._window);

        const color_target_info = c.SDL_GPUColorTargetInfo{
            .texture = swapchain_tex.toSdl(),
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = .{ .r = 0.5, .g = 0.2, .b = 0.7, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .resolve_texture = null, // resolve fields can be ignored since a resolve store_op is not being used
            .cycle = true,
        };

        const depth_stencil_target_info = c.SDL_GPUDepthStencilTargetInfo{
            .texture = self._depth_tex.toSdl(),
            .clear_depth = 1, // can be ignored if loadop isnt clear
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
            .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
            .clear_stencil = 0, // can be ignored if stnecil load op isnt clear
            .mip_level = 0,
            .layer = 0,
            .cycle = true,
        };

        const render_pass = try sdlCheck(
            @src(),
            *c.SDL_GPURenderPass,
            c.SDL_BeginGPURenderPass(
                command_buffer.toSdl(),
                &color_target_info,
                1,
                &depth_stencil_target_info,
            ),
            RendererError.FailedToBeginRenderPass,
        );

        c.SDL_BindGPUVertexBuffers(render_pass, 0, &self._vertex_buf_binding, 1);

        const viewport = c.SDL_GPUViewport{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(swapchain_tex.width),
            .h = @floatFromInt(swapchain_tex.height),
            .min_depth = 0,
            .max_depth = 1,
        };
        c.SDL_SetGPUViewport(render_pass, &viewport);

        c.SDL_BindGPUGraphicsPipeline(render_pass, self._graphics_pipeline);

        const f_width: f32 = @floatFromInt(self._window.getWidth());
        const f_height: f32 = @floatFromInt(self._window.getHeight());

        const time = std.Io.Clock.awake.now(io);
        const seconds: f32 = @floatFromInt(time.toMilliseconds());

        const matrices = Matrices{
            .model = lalg.translate(.{ @sin(seconds / 400), 0, @cos(seconds / 400) + 2 }),
            .view = try lalg.lookAt(.{ 0, 0.5, 1.5 }, .{ 0, 0, 5 }, .{ 0, 1, 0 }),
            .proj = lalg.perspective(f_width / f_height, std.math.degreesToRadians(60), 0.1, 100),
        };

        command_buffer.pushVertexUniformData(0, Matrices, &matrices);

        c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);

        c.SDL_EndGPURenderPass(render_pass);

        try command_buffer.submit();
    }

    fn loadShaders(self: *@This(), io: std.Io, allocator: std.mem.Allocator, spirv_bin_dir_path: []const u8) !void {
        self._shaders.clearRetainingCapacity();

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const spirv_bin_dir = try std.Io.Dir.openDirAbsolute(io, spirv_bin_dir_path, .{ .iterate = true });
        defer spirv_bin_dir.close(io);

        const binaries_zon_buf = try spirv_bin_dir.readFileAlloc(io, "shader_binaries.zon", arena, .unlimited);

        const binaries_zon_buf_0 = try arena.dupeSentinel(u8, binaries_zon_buf, 0);
        const binary_files = try std.zon.parse.fromSliceAlloc([]st.ShaderBinary, arena, binaries_zon_buf_0, null, .{});

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

            var descriptor_counts = reg.DescriptorCounts{
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

            const shader = try Shader.create(
                &self._gpu_device,
                binary_buf.len * @sizeOf(u8),
                binary_buf,
                try arena.dupeSentinel(u8, entrypoint_name, 0),
                stage,
                descriptor_counts,
            );

            try self._shaders.put(binary_file.name, shader);
        }
    }

    fn uploadToVertexBuffer(self: *@This()) !void {
        var command_buffer = try cmd.CommandBuffer.acquire(&self._gpu_device);

        const vertices = [_]Vertex{
            .{ .pos = .{ -0.5, -0.5 }, .col = .{ 1.0, 0.0, 0.0 } },
            .{ .pos = .{ 0.5, -0.5 }, .col = .{ 0.0, 1.0, 0.0 } },
            .{ .pos = .{ 0, 0.5 }, .col = .{ 0.0, 0.0, 1.0 } },
        };

        const buf_size = @sizeOf(@TypeOf(vertices));

        self._vertex_buffer = try buf.Buffer.create(&self._gpu_device, .Vertex, buf_size);

        var transfer_buffer = try buf.transfer.Upload.create(&self._gpu_device, buf_size);
        defer transfer_buffer.deinit(&self._gpu_device);

        try transfer_buffer.upload(&self._gpu_device, Vertex, &vertices);

        const copy_pass = try command_buffer.beginCopyPass();

        try self._vertex_buffer.upload(copy_pass, transfer_buffer, 0, .{
            .offset = 0,
            .size = buf_size,
        });

        c.SDL_EndGPUCopyPass(copy_pass);

        try command_buffer.submit();
    }
};
