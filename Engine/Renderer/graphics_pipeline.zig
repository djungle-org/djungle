const c_util = @import("C");
const c = c_util.c;

const sh = @import("Shaders");

const dev = @import("gpu_device.zig");
const tex = @import("textures.zig");

pub const GraphicsPipeline = struct {
    /// readonly
    sdl_gfx_pipeline: *c.SDL_GPUGraphicsPipeline,

    pub const Error = error{
        FailedToCreateGpuGraphicsPipeline,
    };

    /// color target fmt usually swapchain format
    /// depth target fmt usually depth tex format
    pub fn init(
        gpu_device: *dev.GpuDevice,
        vert_shader: *const sh.Shader,
        frag_shader: *const sh.Shader,
        color_target_fmt: tex.TextureFormat,
        depth_target_fmt: tex.TextureFormat,
        multisamples: tex.SampleCount,
        vertex_buf_description: *const c.SDL_GPUVertexBufferDescription,
        vertex_attributes: []const c.SDL_GPUVertexAttribute,
    ) !@This() {
        const color_target_description = c.SDL_GPUColorTargetDescription{
            .format = color_target_fmt.toSdl(),
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

        const gfx_pipeline_info = c.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = vert_shader.sdl_gpu_shader,
            .fragment_shader = frag_shader.sdl_gpu_shader,
            .vertex_input_state = .{
                .num_vertex_buffers = 1,
                .vertex_buffer_descriptions = vertex_buf_description,
                .num_vertex_attributes = @intCast(vertex_attributes.len),
                .vertex_attributes = @ptrCast(vertex_attributes),
            },
            .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = .{
                .fill_mode = c.SDL_GPU_FILLMODE_FILL,
                .cull_mode = c.SDL_GPU_CULLMODE_BACK,
                .front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
                .enable_depth_bias = false,
                .depth_bias_constant_factor = 0, // these dont need to be added since depth bias is off
                .depth_bias_clamp = 0, // <--
                .depth_bias_slope_factor = 0, // <--
                .enable_depth_clip = true,
            },
            .multisample_state = .{
                .sample_count = tex.SampleCount.toSdl(multisamples),
                .enable_alpha_to_coverage = false,
            },
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = true,
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
                .depth_stencil_format = depth_target_fmt.toSdl(),
            },
        };

        return .{
            .sdl_gfx_pipeline = try c_util.sdlCheck(
                @src(),
                *c.SDL_GPUGraphicsPipeline,
                c.SDL_CreateGPUGraphicsPipeline(gpu_device.sdl_gpu_device, &gfx_pipeline_info),
                Error.FailedToCreateGpuGraphicsPipeline,
            ),
        };
    }

    pub fn deinit(self: *@This(), gpu_device: *dev.GpuDevice) void {
        c.SDL_ReleaseGPUGraphicsPipeline(gpu_device.sdl_gpu_device, self.sdl_gfx_pipeline);
    }

    pub fn bind(self: *@This(), render_pass: *c.SDL_GPURenderPass) void {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.sdl_gfx_pipeline);
    }
};
