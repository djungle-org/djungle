const std = @import("std");

const c = @import("C").c;
const core = @import("Core");
const win = @import("Window");
const log = @import("Logging");
const la = @import("Lalg");
const sh = @import("Shaders");
const dq = @import("DeletionQueue");

pub const buf = @import("buffer.zig");
pub const img = @import("image.zig");
pub const tex = @import("textures.zig");
pub const dev = @import("gpu_device.zig");
pub const mat = @import("materials.zig");
pub const cmd = @import("command_buffer.zig");
pub const msh = @import("mesh.zig");
pub const mdl = @import("model.zig");
pub const mats = @import("materials.zig");

pub const vk = @import("Vulkan");
pub const vktest = @import("vulkan.zig");

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const Shader = sh.Shader;
const ShaderKind = sh.ShaderKind;
const ShaderRegistry = sh.ShaderRegistry;

pub const GraphicsPipelineKind = enum {
    Lit,
    Unlit,
};

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
            .sdl_gfx_pipeline = try sdlCheck(
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

pub const ViewProj = struct {
    view: la.Mat4,
    proj: la.Mat4,
};

pub const Renderer = struct {
    /// readonly
    gpu_device: dev.GpuDevice,

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
    col_tex_initialized: bool = false,
    /// internal
    col_tex: tex.Texture,
    /// internal
    depth_tex: tex.Texture,
    /// internal
    target_aspect: f32,
    /// internal
    shaders: ShaderRegistry,

    /// internal
    unlit_gfx_pipeline: GraphicsPipeline,
    /// internal
    lit_gfx_pipeline: GraphicsPipeline,

    /// internal
    unlit_draw_queue: std.Deque(msh.DrawCall),
    /// internal
    lit_draw_queue: std.Deque(msh.DrawCall),

    pub fn init(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        path_resolver: *const core.PathResolver,
        window: *win.Window,
        target_aspect: f32,
        gpu_driver: dev.GpuDevice.Driver,
        debug: bool,
        multisamples: tex.SampleCount,
    ) !void {
        // test vulkan
        var vulkantest: vktest.Vulkan = undefined;
        try vulkantest.init(gpa, debug, window, "test");
        defer vulkantest.deinit();

        self.allocator = gpa;

        self.delque = try .initCapacity(self.allocator, 5);

        self.window = window;
        self.target_aspect = target_aspect;

        self.gpu_device = try .init(gpu_driver, debug, self.window);
        try self.delque.push(self.allocator, dev.GpuDevice.deinit, .{&self.gpu_device});

        self.shaders = try ShaderRegistry.init(gpa);
        try self.delque.push(self.allocator, ShaderRegistry.deinit, .{ &self.shaders, &self.gpu_device });

        try sh.loadShaders(io, gpa, &self.shaders, &self.gpu_device, path_resolver.shader_bins_path);

        self.swapchain_format = try self.gpu_device.getSwapchainFormat(self.window);

        self.multisamples = multisamples;

        try self.createColorAndDepthTex(self.window.width, self.window.height);
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.col_tex, &self.gpu_device });
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.depth_tex, &self.gpu_device });

        var vert_shader = try self.shaders.get("unlit.vert");
        var frag_shader = try self.shaders.get("unlit.frag");

        self.unlit_gfx_pipeline = try GraphicsPipeline.init(
            &self.gpu_device,
            &vert_shader,
            &frag_shader,
            self.swapchain_format,
            self.depth_tex.format,
            multisamples,
            &msh.vertex_buf_description,
            &msh.vertex_attribs,
        );
        try self.delque.push(gpa, GraphicsPipeline.deinit, .{ &self.unlit_gfx_pipeline, &self.gpu_device });

        vert_shader = try self.shaders.get("lit.vert");
        frag_shader = try self.shaders.get("lit.frag");

        self.lit_gfx_pipeline = try GraphicsPipeline.init(
            &self.gpu_device,
            &vert_shader,
            &frag_shader,
            self.swapchain_format,
            self.depth_tex.format,
            multisamples,
            &msh.vertex_buf_description,
            &msh.vertex_attribs,
        );
        try self.delque.push(gpa, GraphicsPipeline.deinit, .{ &self.lit_gfx_pipeline, &self.gpu_device });

        self.unlit_draw_queue = .empty;
        try self.delque.push(self.allocator, std.Deque(msh.DrawCall).deinit, .{ &self.unlit_draw_queue, self.allocator });

        self.lit_draw_queue = .empty;
        try self.delque.push(self.allocator, std.Deque(msh.DrawCall).deinit, .{ &self.lit_draw_queue, self.allocator });
    }

    pub fn deinit(self: *@This()) void {
        self.delque.deinit(self.allocator);
    }

    /// queues up a draw call to be submitted during the render function
    /// acquire a DrawCall from Mesh.drawCall
    /// places draw calls into draw queues for their respective pipelines
    pub fn queueDrawCall(self: *@This(), draw_call: msh.DrawCall) !void {
        switch (draw_call.material.gfx_pipeline_kind) {
            .Unlit => {
                try self.unlit_draw_queue.pushBack(self.allocator, draw_call);
            },
            .Lit => {
                try self.lit_draw_queue.pushBack(self.allocator, draw_call);
            },
        }
    }

    pub fn createColorAndDepthTex(self: *@This(), width: u32, height: u32) !void {
        if (self.col_tex_initialized) {
            self.col_tex.deinit(&self.gpu_device);
            self.depth_tex.deinit(&self.gpu_device);
        }

        self.col_tex = try tex.Texture.init(
            &self.gpu_device,
            ._2d,
            self.swapchain_format,
            .{ .color_target = true },
            null,
            width,
            height,
            self.multisamples,
        );

        self.depth_tex = try tex.Texture.init(
            &self.gpu_device,
            ._2d,
            .D32_Float,
            .{ .depth_stencil_target = true },
            null,
            width,
            height,
            self.multisamples,
        );

        self.col_tex_initialized = true;
    }

    pub fn letterboxViewport(self: *@This(), swapchain_width: u32, swapchain_height: u32) c.SDL_GPUViewport {
        const win_width: f32 = @floatFromInt(swapchain_width);
        const win_height: f32 = @floatFromInt(swapchain_height);
        const win_aspect = win_width / win_height;

        var viewport_width = win_width;
        var viewport_height = win_height;

        if (win_aspect > self.target_aspect) {
            viewport_width = win_height * self.target_aspect;
        } else {
            viewport_height = win_width / self.target_aspect;
        }

        return .{
            .x = (win_width - viewport_width) / 2.0,
            .y = (win_height - viewport_height) / 2.0,
            .w = viewport_width,
            .h = viewport_height,
            .min_depth = 0,
            .max_depth = 1,
        };
    }

    pub fn render(self: *@This(), command_buffer: *cmd.CommandBuffer, view_proj: *const ViewProj) !void {
        const swapchain_tex = try command_buffer.waitAndAcquireSwapchainTexture(&self.gpu_device, self.window) orelse {
            // if texture is null, window has resized, skip rendering
            return;
        };

        // recreate color and depth textures
        if (swapchain_tex.width != self.col_tex.width or swapchain_tex.height != self.col_tex.height)
            try self.createColorAndDepthTex(swapchain_tex.width, swapchain_tex.height);

        const color_target_info: c.SDL_GPUColorTargetInfo =
            if (self.multisamples == ._1)
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

        const render_pass = try command_buffer.beginRenderPass(
            &color_target_info,
            &depth_stencil_target_info,
        );

        const viewport = self.letterboxViewport(swapchain_tex.width, swapchain_tex.height);
        c.SDL_SetGPUViewport(render_pass, &viewport);

        // --- drawing

        command_buffer.pushVertexUniformData(0, ViewProj, view_proj);

        self.unlit_gfx_pipeline.bind(render_pass);

        while (self.unlit_draw_queue.popFront()) |draw_call| {
            try draw_call.pushModelMatrix(command_buffer);
            draw_call.draw(render_pass);
        }

        self.lit_gfx_pipeline.bind(render_pass);

        while (self.lit_draw_queue.popFront()) |draw_call| {
            command_buffer.pushFragmentUniformData(
                2,
                struct {
                    base_color: la.Vec4,
                    metallic: f32,
                    roughness: f32,
                },
                &.{
                    .base_color = draw_call.material.base_color_factor,
                    .metallic = draw_call.material.metallic,
                    .roughness = draw_call.material.roughness,
                },
            );

            try draw_call.pushModelMatrix(command_buffer);
            draw_call.draw(render_pass);
        }

        c.SDL_EndGPURenderPass(render_pass);
    }
};
