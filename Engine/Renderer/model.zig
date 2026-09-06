const std = @import("std");
const c = @import("C").c;
const log = @import("Logging");

const rdr = @import("renderer.zig");
const msh = @import("mesh.zig");
const cmd = @import("command_buffer.zig");
const img = @import("image.zig");
const tex = @import("textures.zig");
const dev = @import("gpu_device.zig");

pub const ModelError = error{
    FailedToParseFile,
    FailedToGetGltfParseData,
    FailedToLoadBuffers,
    MissingPositionAttributes,
    MissingIndices,
    CgltfAccessorFailedToReadUint,
    MissingMaterial,
    MissingMaterialTexture,
    InvalidGltfPath,
    MissingImageUri,
};

fn cgltfErrorText(cgltf_result: c_uint) []const u8 {
    return switch (cgltf_result) {
        c.cgltf_result_success => "success",
        c.cgltf_result_data_too_short => "data too short",
        c.cgltf_result_unknown_format => "unknown format",
        c.cgltf_result_invalid_json => "invalid json",
        c.cgltf_result_invalid_gltf => "invalid gltf",
        c.cgltf_result_invalid_options => "invalid options",
        c.cgltf_result_file_not_found => "file not found",
        c.cgltf_result_io_error => "io error",
        c.cgltf_result_out_of_memory => "out of memory",
        c.cgltf_result_legacy_gltf => "legacy gltf (unsupported)",
        else => "unknown cgltf error",
    };
}

pub const MaterialCache = struct {
    /// to prevent duplicate texture loading
    loaded_materials: std.AutoHashMap(usize, *msh.Material),

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{
            .loaded_materials = .init(gpa),
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator, gpu_device: *dev.GpuDevice) void {
        var iter = self.loaded_materials.valueIterator();

        while (iter.next()) |mat_ptr| {
            mat_ptr.*.deinit(gpu_device);
            gpa.destroy(mat_ptr.*);
        }

        self.loaded_materials.deinit();
    }

    pub fn getMaterial(self: *@This(), key: usize) ?*const msh.Material {
        return self.loaded_materials.get(key);
    }

    pub fn putMaterial(self: *@This(), gpa: std.mem.Allocator, key: usize, mat: msh.Material) !*const msh.Material {
        const mat_ptr = try gpa.create(msh.Material);
        mat_ptr.* = mat;

        try self.loaded_materials.put(key, mat_ptr);

        return mat_ptr;
    }
};

/// zig wrapper around cgltf.h
/// meshes field meant to be read, but not modified
pub const Model = struct {
    /// internal
    meshes: []msh.Mesh,

    pub fn init(gltf_path: [:0]const u8, gpa: std.mem.Allocator, renderer: *rdr.Renderer, path_resolver: *const rdr.PathResolver) !@This() {
        const cgltf_options = std.mem.zeroes(c.cgltf_options);

        var data_opt: ?*c.cgltf_data = null;
        var result = c.cgltf_parse_file(&cgltf_options, gltf_path, &data_opt);
        if (result != c.cgltf_result_success) {
            log.err(@src(), "{s}", .{cgltfErrorText(result)});
            return ModelError.FailedToParseFile;
        }

        const data = data_opt orelse return ModelError.FailedToGetGltfParseData;
        defer c.cgltf_free(data);

        result = c.cgltf_load_buffers(&cgltf_options, data, gltf_path);
        if (result != c.cgltf_result_success) {
            log.err(@src(), "{s}", .{cgltfErrorText(result)});
            return ModelError.FailedToLoadBuffers;
        }

        var primitive_count: usize = 0;
        for (0..data.meshes_count) |i| {
            primitive_count += data.meshes[i].primitives_count;
        }

        const meshes = try gpa.alloc(msh.Mesh, primitive_count);

        var mesh_idx: usize = 0;

        var cmd_buf = try cmd.CommandBuffer.acquire(&renderer.gpu_device);

        const copy_pass = try cmd_buf.beginCopyPass();

        for (0..data.meshes_count) |i| {
            const c_mesh = data.meshes[i];

            const primitives = c_mesh.primitives[0..c_mesh.primitives_count];

            for (primitives) |*primitive| {
                const vertices = try loadPrimitiveVertices(gpa, primitive);
                defer gpa.free(vertices);
                const indices = try loadPrimitiveIndices(gpa, primitive);
                defer gpa.free(indices);

                try meshes[mesh_idx].init(
                    renderer,
                    vertices,
                    indices,
                    try loadPrimitiveMaterial(
                        gpa,
                        &renderer.gpu_device,
                        copy_pass,
                        primitive,
                        data,
                        gltf_path,
                        &renderer.material_cache,
                        path_resolver,
                    ),
                );

                mesh_idx += 1;
            }
        }

        c.SDL_EndGPUCopyPass(copy_pass);

        try cmd_buf.submit();

        return .{
            .meshes = meshes,
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator, renderer: *rdr.Renderer) void {
        for (self.meshes) |*mesh| {
            mesh.deinit(renderer);
        }

        gpa.free(self.meshes);
    }
};

fn loadPrimitiveVertices(gpa: std.mem.Allocator, primitive: *const c.cgltf_primitive) ![]const msh.Vertex {
    const attributes = primitive.attributes[0..primitive.attributes_count];

    var positions: ?[]f32 = null;
    var colors: ?[]f32 = null;
    var uvs: ?[]f32 = null;

    for (attributes) |attr| {
        const accessor = attr.data;
        const num_components = c.cgltf_num_components(accessor.*.type);
        const total_floats = accessor.*.count * num_components;

        switch (attr.type) {
            c.cgltf_attribute_type_position => {
                const floats = try gpa.alloc(f32, total_floats);
                _ = c.cgltf_accessor_unpack_floats(accessor, floats.ptr, total_floats);
                positions = floats;
            },
            c.cgltf_attribute_type_color => {
                const floats = try gpa.alloc(f32, total_floats);
                _ = c.cgltf_accessor_unpack_floats(accessor, floats.ptr, total_floats);
                colors = floats;
            },
            c.cgltf_attribute_type_texcoord => {
                const floats = try gpa.alloc(f32, total_floats);
                _ = c.cgltf_accessor_unpack_floats(accessor, floats.ptr, total_floats);
                uvs = floats;
            },
            else => continue,
        }
    }

    defer if (positions) |p| gpa.free(p);
    defer if (colors) |col| gpa.free(col);
    defer if (uvs) |u| gpa.free(u);

    const pos = positions orelse return ModelError.MissingPositionAttributes;
    const vertex_count = pos.len / 3; // vec3

    const vertices = try gpa.alloc(msh.Vertex, vertex_count);

    for (0..vertex_count) |i| {
        const px = pos[i * 3 + 0];
        const py = pos[i * 3 + 1];
        const pz = pos[i * 3 + 2];

        // var r: f32 = 0;
        // var g: f32 = 0;
        // var b: f32 = 0;

        var u: f32 = 0;
        var v: f32 = 0;
        if (uvs) |uv_buf| {
            u = uv_buf[i * 2 + 0];
            v = uv_buf[i * 2 + 1];
        }

        vertices[i] = .{
            .pos = .{ px, py, pz },
            .col = .{ 1, 1, 1 },
            .uv = .{ u, v },
        };
    }

    return vertices;
}

fn loadPrimitiveIndices(gpa: std.mem.Allocator, primitive: *const c.cgltf_primitive) ![]const u32 {
    const index_accessor = (primitive.indices orelse return ModelError.MissingIndices).*;

    const indices = try gpa.alloc(u32, index_accessor.count);

    for (0..index_accessor.count) |i| {
        var idx: c.cgltf_uint = undefined;
        if (c.cgltf_accessor_read_uint(primitive.indices, i, &idx, 1) == 0)
            return ModelError.CgltfAccessorFailedToReadUint;

        indices[i] = @intCast(idx);
    }

    return indices;
}

fn loadPrimitiveMaterial(
    gpa: std.mem.Allocator,
    gpu_device: *dev.GpuDevice,
    copy_pass: *c.SDL_GPUCopyPass,
    primitive: *const c.cgltf_primitive,
    data: *const c.cgltf_data,
    gltf_path: []const u8,
    cache: *MaterialCache,
    path_resolver: *const rdr.PathResolver,
) !*const msh.Material {
    const material = primitive.material orelse return ModelError.MissingMaterial;
    const base_col_tex = material.*.pbr_metallic_roughness.base_color_texture.texture orelse return ModelError.MissingMaterialTexture;
    const cgltf_image = base_col_tex.*.image orelse return ModelError.MissingMaterialTexture;

    const image_idx = c.cgltf_image_index(data, cgltf_image);

    if (cache.getMaterial(image_idx)) |mat|
        return mat;

    const gltf_dir = std.Io.Dir.path.dirname(gltf_path) orelse return ModelError.InvalidGltfPath;

    const uri = cgltf_image.*.uri orelse return ModelError.MissingImageUri;
    const uri_slice = std.mem.span(uri);

    const img_path = try path_resolver.combine(gpa, gltf_dir, uri_slice);
    defer gpa.free(img_path);

    var image = try img.Image.init(img_path);
    defer image.deinit();

    var texture = try tex.Texture.init(
        gpu_device,
        ._2d,
        .R8G8B8A8_Srgb,
        .{ .sampler = true },
        .{},
        image.width,
        image.height,
        ._1,
    );

    try texture.upload(gpu_device, copy_pass, &image);

    const mat = try msh.Material.init(texture);

    return try cache.putMaterial(gpa, image_idx, mat);
}
