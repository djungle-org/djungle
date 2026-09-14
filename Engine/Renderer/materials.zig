const std = @import("std");
const c_util = @import("C");
const c = c_util.c;

const lalg = @import("Lalg");
const sh = @import("Shaders");

const dev = @import("gpu_device.zig");
const tex = @import("textures.zig");
const rdr = @import("renderer.zig");
const cmd = @import("command_buffer.zig");

pub const Material = struct {
    base_texture: tex.Texture,
    base_color_factor: lalg.Vec4,
    gfx_pipeline_kind: rdr.GraphicsPipelineKind,

    pub fn init(base_texture: tex.Texture, base_color_factor: lalg.Vec4, gfx_pipeline_kind: rdr.GraphicsPipelineKind) !@This() {
        return .{
            .base_texture = base_texture,
            .base_color_factor = base_color_factor,
            .gfx_pipeline_kind = gfx_pipeline_kind,
        };
    }

    pub fn createFromFile(renderer: *rdr.Renderer, path: [:0]const u8, texture_format: tex.TextureFormat) !@This() {
        var image = try rdr.img.Image.init(path);
        defer image.deinit();

        var texture = try tex.Texture.init(
            &renderer.gpu_device,
            ._2d,
            texture_format,
            .{ .sampler = true },
            .{},
            image.width,
            image.height,
            ._1,
        );

        var cmd_buf = try cmd.CommandBuffer.acquire(&renderer.gpu_device);
        const copy_pass = try cmd_buf.beginCopyPass();

        try texture.upload(&renderer.gpu_device, copy_pass, &image);

        c.SDL_EndGPUCopyPass(copy_pass);

        try cmd_buf.submit();

        return .{
            .texture = texture,
        };
    }

    pub fn deinit(self: *@This(), renderer: *rdr.Renderer) void {
        self.base_texture.deinit(&renderer.gpu_device);
    }
};

pub const MaterialCache = struct {
    /// to prevent duplicate texture loading
    /// keyed by gltf material index
    loaded_materials: std.AutoHashMap(usize, *Material),

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{
            .loaded_materials = .init(gpa),
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator, renderer: *rdr.Renderer) void {
        var iter = self.loaded_materials.valueIterator();

        while (iter.next()) |mat_ptr| {
            mat_ptr.*.deinit(renderer);
            gpa.destroy(mat_ptr.*);
        }

        self.loaded_materials.deinit();
    }

    pub fn getMaterial(self: *@This(), key: usize) ?*const Material {
        return self.loaded_materials.get(key);
    }

    pub fn putMaterial(self: *@This(), gpa: std.mem.Allocator, key: usize, mat: Material) !*const Material {
        const mat_ptr = try gpa.create(Material);
        mat_ptr.* = mat;

        try self.loaded_materials.put(key, mat_ptr);

        return mat_ptr;
    }
};
