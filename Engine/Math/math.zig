pub const std = @import("std");

// all vectors origin is 0

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

pub const Mat2 = [2]@Vector(2, f32);
pub const Mat3 = [3]@Vector(3, f32);
pub const Mat4 = [4]@Vector(4, f32);

test "add 2 vectors" {
    const vec1 = Vec3{ 0, 5, 2 };
    const vec2 = Vec3{ 3, 0, 2 };

    const res = vec1 + vec2;

    try std.testing.expectEqual(Vec3{ 3, 5, 4 }, res);
}

fn assertVectorType(comptime T: type) void {
    comptime switch (@typeInfo(T)) {
        .vector => |info| {
            if (info.child != f32) {
                @compileError("Requires f32 vector, got" ++ @typeName(T));
            }
        },
        else => @compileError("Requires an @Vector type, got" ++ @typeName(T)),
    };
}

pub fn dot(comptime VectorType: type, vec1: VectorType, vec2: VectorType) f32 {
    comptime assertVectorType(VectorType);

    const products = vec1 * vec2;
    return @reduce(.Add, products);
}

test "dot product" {
    var vec1 = Vec2{ 0, 2 };
    var vec2 = Vec2{ 2, 1 };

    var res = dot(Vec2, vec1, vec2);

    try std.testing.expectEqual(2, res);

    vec1 = Vec2{ 7.81, 110.49 };
    vec2 = Vec2{ 29.46, 49.83 };

    res = dot(Vec2, vec1, vec2);

    try std.testing.expectEqual(5735.7993, res);
}

pub fn cross(lhs: Vec3, rhs: Vec3) Vec3 {
    const lhs_zxy = Vec3{ lhs[2], lhs[0], lhs[1] };
    const lhs_yzx = Vec3{ lhs[1], lhs[2], lhs[0] };

    const rhs_zxy = Vec3{ rhs[2], rhs[0], rhs[1] };
    const rhs_yzx = Vec3{ rhs[1], rhs[2], rhs[0] };

    return (lhs_yzx * rhs_zxy) - (lhs_zxy * rhs_yzx);
}

test "cross product" {
    const vec1 = Vec3{ 1, 2, 3 };
    const vec2 = Vec3{ 3, 4, 5 };

    const res = cross(vec1, vec2);

    try std.testing.expectEqual(Vec3{ -2, 4, -2 }, res);
}
