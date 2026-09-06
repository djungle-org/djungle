const std = @import("std");
const c = @import("C").c;
const win = @import("Window");
const log = @import("Logging");
const vk = @import("Vulkan");
const la = @import("Lalg");
const sh = @import("Shaders");

pub const buf = @import("buffer.zig");
pub const img = @import("image.zig");
pub const tex = @import("textures.zig");
pub const dev = @import("gpu_device.zig");
pub const cmd = @import("command_buffer.zig");
pub const msh = @import("mesh.zig");
pub const mdl = @import("model.zig");

const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const Shader = sh.Shader;
const ShaderKind = sh.ShaderKind;
const ShaderRegistry = sh.ShaderRegistry;

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

pub const ViewProj = struct {
    view: la.Mat4,
    proj: la.Mat4,
};

const ModelMatrix = struct {
    model: la.Mat4,
};

const Seconds = f32;

pub const PathKind = enum {
    Assets,
    ShaderBinaries,
};

pub const PathResolver = struct {
    /// readonly
    assets_path: [:0]const u8,
    /// readonly
    shader_bins_path: [:0]const u8,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) !@This() {
        const exe_dir_path = try std.process.executableDirPathAlloc(io, gpa);
        defer gpa.free(exe_dir_path);

        const assets_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../../../Assets" });
        defer gpa.free(assets_path);

        const shader_bins_path = try std.Io.Dir.path.join(gpa, &.{ exe_dir_path, "../Shaders" });
        defer gpa.free(shader_bins_path);

        return .{
            .assets_path = try gpa.dupeSentinel(u8, assets_path, 0),
            .shader_bins_path = try gpa.dupeSentinel(u8, shader_bins_path, 0),
        };
    }

    pub fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
        gpa.free(self.assets_path);
        gpa.free(self.shader_bins_path);
    }

    /// kind: Assets will find path relative to assets folder, ShaderBinaries will find path relative to zig-out shaders folder
    /// returned slice is owned by the caller
    pub fn resolvePath(self: *const @This(), gpa: std.mem.Allocator, kind: PathKind, relative: []const u8) ![:0]const u8 {
        const joined: []u8 = switch (kind) {
            .Assets => try std.Io.Dir.path.join(gpa, &.{ self.assets_path, relative }),
            .ShaderBinaries => try std.Io.Dir.path.join(gpa, &.{ self.shader_bins_path, relative }),
        };

        defer gpa.free(joined);

        return try gpa.dupeSentinel(u8, joined, 0);
    }

    /// returned slice is owned by the caller
    pub fn combine(_: *const @This(), gpa: std.mem.Allocator, absolute: []const u8, relative: []const u8) ![:0]const u8 {
        const joined = try std.Io.Dir.path.join(gpa, &.{ absolute, relative });
        defer gpa.free(joined);

        return try gpa.dupeSentinel(u8, joined, 0);
    }
};

pub const Renderer = struct {
    /// readonly
    gpu_device: dev.GpuDevice,
    /// readonly
    delta_time: Seconds,

    /// internal
    window: *win.Window,
    /// internal
    swapchain_format: tex.TextureFormat,
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

    pub fn init(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        window: *win.Window,
        gpu_driver: dev.GpuDriver,
        debug: bool,
        path_resolver: *const PathResolver,
    ) !void {
        self.window = window;

        self.draw_queue = .empty;
        self.material_cache = try .init(gpa);

        self.gpu_device = try .init(gpu_driver, debug, self.window);

        self.swapchain_format = try self.gpu_device.getSwapchainFormat(self.window);

        self.shaders = try ShaderRegistry.init(gpa);

        try sh.loadShaders(io, gpa, &self.shaders, &self.gpu_device, path_resolver.shader_bins_path);

        self.depth_tex = try tex.Texture.init(
            &self.gpu_device,
            ._2d,
            .D32_Float,
            .{ .depth_stencil_target = true },
            null,
            window.width,
            window.height,
            ._1,
        );

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
                .sample_count = tex.SampleCount.toSdl(._1),
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
                .depth_stencil_format = self.depth_tex.format.toSdl(),
            },
        };

        self.graphics_pipeline = try sdlCheck(
            @src(),
            *c.SDL_GPUGraphicsPipeline,
            c.SDL_CreateGPUGraphicsPipeline(self.gpu_device.sdl_gpu_device, &gfx_pipeline_info),
            RendererError.FailedToCreateGpuGraphicsPipeline,
        );
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        // c.SDL_ReleaseGPUSampler(self.gpu_device.sdl_gpu_device, self.sampler);

        c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device.sdl_gpu_device, self.graphics_pipeline);

        self.depth_tex.deinit(&self.gpu_device);

        self.shaders.deinit(&self.gpu_device);

        self.material_cache.deinit(gpa, &self.gpu_device);

        self.draw_queue.deinit(gpa);

        self.gpu_device.deinit();
    }

    /// queues up a draw call to be submitted during the render function
    /// acquire a DrawCall from Mesh.drawCall
    pub fn queueDrawCall(self: *@This(), gpa: std.mem.Allocator, draw_call: msh.DrawCall) !void {
        try self.draw_queue.pushBack(gpa, draw_call);
    }

    pub fn render(self: *@This(), view_proj: *const ViewProj) !void {
        var command_buffer = try cmd.CommandBuffer.acquire(&self.gpu_device);

        const swapchain_tex = try command_buffer.waitAndAcquireSwapchainTexture(&self.gpu_device, self.window);

        const color_target_info = c.SDL_GPUColorTargetInfo{
            .texture = swapchain_tex.sdl_texture,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = .{ .r = 0.5, .g = 0.2, .b = 0.7, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
            .resolve_texture = null, // resolve fields can be ignored since a resolve store_op is not being used
            .cycle = true,
        };

        const depth_stencil_target_info = c.SDL_GPUDepthStencilTargetInfo{
            .texture = self.depth_tex.sdl_texture,
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
                command_buffer.sdl_command_buffer,
                &color_target_info,
                1,
                &depth_stencil_target_info,
            ),
            RendererError.FailedToBeginRenderPass,
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
