const std = @import("std");

const c = @import("C").c;
const core = @import("Core");
const win = @import("Window");
const log = @import("Logging");
const vk = @import("Vulkan");
const la = @import("Lalg");
const sh = @import("Shaders");
const dq = @import("DeletionQueue");

pub const buf = @import("buffer.zig");
pub const img = @import("image.zig");
pub const tex = @import("textures.zig");
pub const gpu = @import("gpu_device.zig");
pub const cmd = @import("command_buffer.zig");
pub const msh = @import("mesh.zig");
pub const mdl = @import("model.zig");

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const Shader = sh.Shader;
const ShaderKind = sh.ShaderKind;
const ShaderRegistry = sh.ShaderRegistry;

pub const ViewProj = struct {
    view: la.Mat4,
    proj: la.Mat4,
};

const ModelMatrix = struct {
    model: la.Mat4,
};

pub const Renderer = struct {
    /// readonly
    gpu_device: gpu.GpuDevice,

    /// internal
    delque: dq.DeletionQueue,
    /// internal
    allocator: std.mem.Allocator,
    /// internal
    window: *win.Window,
    /// internal
    swapchain_format: tex.TextureFormat,
    /// internal
    multisamples: tex.SampleCount,
    /// internal
    col_tex: tex.Texture,
    /// internal
    depth_tex: tex.Texture,
    /// internal
    graphics_pipeline: *c.SDL_GPUGraphicsPipeline,
    /// internal
    shaders: ShaderRegistry,
    /// internal
    draw_queue: std.Deque(msh.DrawCall),
    /// internal
    material_cache: mdl.MaterialCache,

    pub const Error = error{
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

    pub fn init(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        path_resolver: *const core.PathResolver,
        window: *win.Window,
        gpu_driver: gpu.GpuDevice.Driver,
        debug: bool,
        multisamples: tex.SampleCount,
    ) !void {
        self.allocator = gpa;

        self.delque = try .initCapacity(self.allocator, 5);

        self.window = window;

        self.gpu_device = try .init(gpu_driver, debug, self.window);
        try self.delque.push(self.allocator, gpu.GpuDevice.deinit, .{&self.gpu_device});

        self.draw_queue = .empty;
        try self.delque.push(self.allocator, std.Deque(msh.DrawCall).deinit, .{ &self.draw_queue, self.allocator });

        self.material_cache = try .init(gpa);
        try self.delque.push(self.allocator, mdl.MaterialCache.deinit, .{ &self.material_cache, self.allocator, self });

        self.shaders = try ShaderRegistry.init(gpa);
        try self.delque.push(self.allocator, ShaderRegistry.deinit, .{ &self.shaders, &self.gpu_device });

        try sh.loadShaders(io, gpa, &self.shaders, &self.gpu_device, path_resolver.shader_bins_path);

        self.swapchain_format = try self.gpu_device.getSwapchainFormat(self.window);

        self.multisamples = multisamples;

        self.col_tex = try tex.Texture.init(
            &self.gpu_device,
            ._2d,
            self.swapchain_format,
            .{ .color_target = true },
            null,
            window.width,
            window.height,
            self.multisamples,
        );
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.col_tex, &self.gpu_device });

        self.depth_tex = try tex.Texture.init(
            &self.gpu_device,
            ._2d,
            .D32_Float,
            .{ .depth_stencil_target = true },
            null,
            window.width,
            window.height,
            self.multisamples,
        );
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.depth_tex, &self.gpu_device });

        const color_target_description = c.SDL_GPUColorTargetDescription{
            .format = self.swapchain_format.toSdl(),
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

        const vert_shader = try self.shaders.get("simple_vert");
        const frag_shader = try self.shaders.get("simple_frag");

        const gfx_pipeline_info = c.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = vert_shader.sdl_gpu_shader,
            .fragment_shader = frag_shader.sdl_gpu_shader,
            .vertex_input_state = .{
                .num_vertex_buffers = 1,
                .vertex_buffer_descriptions = &msh.vertex_buf_description,
                .num_vertex_attributes = msh.vertex_attribs.len,
                .vertex_attributes = &msh.vertex_attribs,
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
                .sample_count = tex.SampleCount.toSdl(self.multisamples),
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
                .depth_stencil_format = self.depth_tex.format.toSdl(),
            },
        };

        self.graphics_pipeline = try sdlCheck(
            @src(),
            *c.SDL_GPUGraphicsPipeline,
            c.SDL_CreateGPUGraphicsPipeline(self.gpu_device.sdl_gpu_device, &gfx_pipeline_info),
            Error.FailedToCreateGpuGraphicsPipeline,
        );

        try self.delque.push(gpa, c.SDL_ReleaseGPUGraphicsPipeline, .{ self.gpu_device.sdl_gpu_device, self.graphics_pipeline });
    }

    pub fn deinit(self: *@This()) void {
        self.delque.deinit(self.allocator);
    }

    /// queues up a draw call to be submitted during the render function
    /// acquire a DrawCall from Mesh.drawCall
    pub fn queueDrawCall(self: *@This(), draw_call: msh.DrawCall) !void {
        try self.draw_queue.pushBack(self.allocator, draw_call);
    }

    pub fn render(self: *@This(), view_proj: *const ViewProj) !void {
        var command_buffer = try cmd.CommandBuffer.acquire(&self.gpu_device);

        const swapchain_tex = try command_buffer.waitAndAcquireSwapchainTexture(&self.gpu_device, self.window);

        const color_target_info: c.SDL_GPUColorTargetInfo = if (self.multisamples == ._1)
            c.SDL_GPUColorTargetInfo{
                .texture = swapchain_tex.sdl_texture,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .clear_color = .{ .r = 0.2, .g = 0.3, .b = 0.8, .a = 1.0 },
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_STORE,
                .resolve_texture = null,
                .cycle = true,
            }
        else
            c.SDL_GPUColorTargetInfo{
                .texture = self.col_tex.sdl_texture,
                .mip_level = 0,
                .layer_or_depth_plane = 0,
                .clear_color = .{ .r = 0.2, .g = 0.3, .b = 0.8, .a = 1.0 },
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_RESOLVE, // resolve is for msaa
                .resolve_texture = swapchain_tex.sdl_texture, // ISSUE HERE, THIS MODIFIES THE READ ONLY SDL_TEXTURE, downsampling into swapchain texture
                .resolve_layer = 0,
                .resolve_mip_level = 0,
                .cycle_resolve_texture = true,
                .cycle = true,
            };

        const depth_stencil_target_info = c.SDL_GPUDepthStencilTargetInfo{
            .texture = self.depth_tex.sdl_texture,
            .clear_depth = 1, // can be ignored if loadop isnt clear
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_DONT_CARE,
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
                command_buffer.sdl_command_buffer,
                &color_target_info,
                1,
                &depth_stencil_target_info,
            ),
            Error.FailedToBeginRenderPass,
        );

        const viewport = c.SDL_GPUViewport{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(swapchain_tex.width),
            .h = @floatFromInt(swapchain_tex.height),
            .min_depth = 0,
            .max_depth = 1,
        };
        c.SDL_SetGPUViewport(render_pass, &viewport);

        c.SDL_BindGPUGraphicsPipeline(render_pass, self.graphics_pipeline);

        // --- drawing

        command_buffer.pushVertexUniformData(0, ViewProj, view_proj);

        while (self.draw_queue.popFront()) |draw_call| {
            const model_mat = ModelMatrix{
                .model = draw_call.model,
            };

            command_buffer.pushVertexUniformData(1, ModelMatrix, &model_mat);

            const sampler_binding = c.SDL_GPUTextureSamplerBinding{
                .texture = draw_call.material.texture.sdl_texture,
                .sampler = draw_call.material.texture.sampler.?.sdl_sampler,
            };

            c.SDL_BindGPUFragmentSamplers(render_pass, 0, &sampler_binding, 1);

            draw_call.draw(render_pass);
        }

        c.SDL_EndGPURenderPass(render_pass);

        try command_buffer.submit();
    }
};
