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
pub const gfx = @import("graphics_pipeline.zig");
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
    col_tex_initialized: bool = false,
    /// internal
    col_tex: tex.Texture,
    /// internal
    depth_tex: tex.Texture,
    /// internal
    target_aspect: f32,
    /// internal
    gfx_pipeline: gfx.GraphicsPipeline,
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
        path_resolver: *const core.PathResolver,
        window: *win.Window,
        target_aspect: f32,
        gpu_driver: gpu.GpuDevice.Driver,
        debug: bool,
        multisamples: tex.SampleCount,
    ) !void {
        self.allocator = gpa;

        self.delque = try .initCapacity(self.allocator, 5);

        self.window = window;
        self.target_aspect = target_aspect;

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

        try self.createColorAndDepthTex(self.window.width, self.window.height);
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.col_tex, &self.gpu_device });
        try self.delque.push(self.allocator, tex.Texture.deinit, .{ &self.depth_tex, &self.gpu_device });

        const vert_shader = try self.shaders.get("vert");
        const frag_shader = try self.shaders.get("frag");

        self.gfx_pipeline = try gfx.GraphicsPipeline.init(
            &self.gpu_device,
            &vert_shader,
            &frag_shader,
            self.swapchain_format,
            self.depth_tex.format,
            multisamples,
            &msh.vertex_buf_description,
            &msh.vertex_attribs,
        );
        try self.delque.push(gpa, gfx.GraphicsPipeline.deinit, .{ &self.gfx_pipeline, &self.gpu_device });
    }

    pub fn deinit(self: *@This()) void {
        self.delque.deinit(self.allocator);
    }

    /// queues up a draw call to be submitted during the render function
    /// acquire a DrawCall from Mesh.drawCall
    pub fn queueDrawCall(self: *@This(), draw_call: msh.DrawCall) !void {
        try self.draw_queue.pushBack(self.allocator, draw_call);
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

    pub fn render(self: *@This(), view_proj: *const ViewProj) !void {
        var command_buffer = try cmd.CommandBuffer.acquire(&self.gpu_device);

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

        self.gfx_pipeline.bind(render_pass);

        // --- drawing

        command_buffer.pushVertexUniformData(0, ViewProj, view_proj);

        while (self.draw_queue.popFront()) |draw_call| {
            draw_call.pushModelMatrix(&command_buffer);
            draw_call.draw(render_pass);
        }

        c.SDL_EndGPURenderPass(render_pass);

        try command_buffer.submit();
    }
};
