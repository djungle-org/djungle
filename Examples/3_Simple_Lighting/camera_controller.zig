const std = @import("std");

const rdr = @import("Renderer");
const la = @import("Lalg");
const ipt = @import("Input");

pub const Camera = struct {
    pos: la.Vec3 = .{ 0, 0, 0 },

    yaw: f32 = 0,
    pitch: f32 = 0,

    pub fn moveAndLook(
        self: *@This(),
        input: ipt.Input,
        target_aspect: f32,
        fov_deg: f32,
        near: f32,
        far: f32,
        sensitivity: f32,
        move_speed: f32,
    ) !rdr.ViewProj {
        const world_up = la.Vec3{ 0, 1, 0 };

        self.yaw += input.mouse_dx * sensitivity;
        self.pitch = std.math.clamp(
            self.pitch - input.mouse_dy * sensitivity,
            -89,
            89,
        );

        var forward = la.Vec3{ 0, 0, 0 };
        forward[0] = @cos(self.pitch) * @sin(self.yaw);
        forward[1] = @sin(self.pitch);
        forward[2] = -@cos(self.pitch) * @cos(self.yaw);

        const flat_forward = try la.normalize(la.Vec3, .{ forward[0], 0, forward[2] });
        const right = try la.normalize(la.Vec3, la.cross(world_up, flat_forward));

        var dir = la.Vec3{ 0, 0, 0 };

        if (input.getKeyState(.W)) dir += flat_forward;
        if (input.getKeyState(.S)) dir -= flat_forward;
        if (input.getKeyState(.A)) dir += right;
        if (input.getKeyState(.D)) dir -= right;
        if (input.getKeyState(.SPACE)) dir += world_up;
        if (input.getKeyState(.LSHIFT)) dir -= world_up;

        self.pos += la.scaleVec(la.Vec3, dir, move_speed);

        const target = self.pos + forward;

        return .{
            .view = try la.lookAt(self.pos, target, world_up),
            .proj = la.perspective(target_aspect, std.math.degreesToRadians(fov_deg), near, far),
        };
    }
};
