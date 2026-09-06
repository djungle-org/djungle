const std = @import("std");

const rdr = @import("Renderer");
const la = @import("Lalg");
const ipt = @import("Input");

pub const Camera = struct {
    pos: la.Vec3 = .{ 0, 0, 0 },

    pub fn move(self: *@This(), input: ipt.Input, width: f32, height: f32, fov_deg: f32, near: f32, far: f32) !rdr.ViewProj {
        var dir = la.Vec3{ 0, 0, 0 };

        if (input.getKeyState(.W)) dir[2] = 1;
        if (input.getKeyState(.S)) dir[2] = -1;
        if (input.getKeyState(.A)) dir[0] = 1;
        if (input.getKeyState(.D)) dir[0] = -1;
        if (input.getKeyState(.SPACE)) dir[1] = 1;
        if (input.getKeyState(.LSHIFT)) dir[1] = -1;

        self.pos += dir;

        const target = self.pos + la.Vec3{ -1, 0, 0 };

        return .{
            .view = try la.lookAt(self.pos, target, .{ 0, 1, 0 }),
            .proj = la.perspective(width / height, std.math.degreesToRadians(fov_deg), near, far),
        };
    }
};
