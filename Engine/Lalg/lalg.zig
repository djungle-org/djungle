const std = @import("std");

pub const VectorError = error{
    DivByZero,
};

// all vectors origin is 0

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

/// column major, each element of array is a column
pub const Mat2 = [2]Vec2;
pub const Mat3 = [3]Vec3;
pub const Mat4 = [4]Vec4;

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

fn vecLanes(comptime T: type) comptime_int {
    comptime assertVectorType(T);

    return @typeInfo(T).vector.len;
}

fn VecChild(comptime T: type) type {
    comptime assertVectorType(T);

    return @typeInfo(T).vector.child;
}

pub fn scaleVec(comptime VectorType: type, vec: VectorType, scalar: f32) VectorType {
    comptime assertVectorType(VectorType);

    const scalar_simd: VectorType = @splat(scalar);

    return vec * scalar_simd;
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

    try std.testing.expectApproxEqAbs(5735.7993, res, std.math.floatEps(f32));
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

pub fn magSqr(comptime VectorType: type, vec: VectorType) f32 {
    comptime assertVectorType(VectorType);

    const sqr = vec * vec;

    return @reduce(.Add, sqr);
}

test "magSqr" {
    const vec = Vec3{ 3, 4, 0 };

    const res = magSqr(Vec3, vec);

    try std.testing.expectEqual(25, res);
}

pub fn mag(comptime VectorType: type, vec: VectorType) f32 {
    comptime assertVectorType(VectorType);

    const mag_sqr = magSqr(VectorType, vec);

    return @sqrt(mag_sqr);
}

test "mag" {
    const vec = Vec3{ 3, 4, 0 };

    const res = mag(Vec3, vec);

    try std.testing.expectEqual(5, res);
}

pub fn normalize(comptime VectorType: type, vec: VectorType) !VectorType {
    comptime assertVectorType(VectorType);

    const magnitude = mag(VectorType, vec);
    if (magnitude == 0.0) return VectorError.DivByZero;

    return scaleVec(VectorType, vec, 1 / magnitude);
}

test "normalize" {
    var vec = Vec3{ 3, 4, 0 };

    const res = try normalize(Vec3, vec);

    try std.testing.expectEqual(Vec3{ 0.6, 0.8, 0 }, res);

    vec = Vec3{ 0, 0, 0 };

    try std.testing.expectError(VectorError.DivByZero, normalize(Vec3, vec));
}

pub fn transpose(comptime MatrixType: type, mat: MatrixType) MatrixType {
    var result: MatrixType = undefined;

    inline for (0..mat.len) |i| {
        inline for (0..mat.len) |j| {
            result[i][j] = mat[j][i];
        }
    }

    return result;
}

/// helper so you can write matrices in row-major layout, which is more natural,
/// and then convert to column-major which is what is used in shaders and calculations
pub fn toColumns(comptime MatrixType: type, comptime mat: MatrixType) MatrixType {
    return transpose(MatrixType, mat);
}

test "transpose" {
    const mat = comptime transpose(Mat3, .{
        .{ 1, 2, 3 },
        .{ 3, 2, 1 },
        .{ 1, 3, 2 },
    });

    const res = Mat3{
        .{ 1, 3, 1 },
        .{ 2, 2, 3 },
        .{ 3, 1, 2 },
    };

    try std.testing.expectEqual(res, mat);
}

pub fn mulMatVec(comptime MatrixType: type, mat: MatrixType, vec: @typeInfo(MatrixType).array.child) @typeInfo(MatrixType).array.child {
    const VectorType = @typeInfo(MatrixType).array.child;

    var result: VectorType = @splat(0);

    inline for (0..mat.len) |i| {
        const scaled_column = scaleVec(VectorType, mat[i], vec[i]);

        result += scaled_column;
    }

    return result;
}

test "matrix-vector multiply" {
    const mat = toColumns(Mat3, .{
        .{ 1, 2, 3 },
        .{ 3, 2, 1 },
        .{ 1, 2, 3 },
    });

    const vec = Vec3{ 4, 5, 6 };

    const res = mulMatVec(Mat3, mat, vec);

    const expected = Vec3{ 32, 28, 32 };

    try std.testing.expectEqual(expected, res);
}

pub fn mulMat(comptime MatrixType: type, mat1: MatrixType, mat2: MatrixType) MatrixType {
    var result: MatrixType = undefined;

    inline for (0..mat2.len) |i| {
        result[i] = mulMatVec(MatrixType, mat1, mat2[i]);
    }

    return result;
}

test "matrix multiply" {
    const mat1 = toColumns(Mat3, .{
        .{ 1, 2, 3 },
        .{ 3, 2, 1 },
        .{ 1, 3, 2 },
    });

    const mat2 = toColumns(Mat3, .{
        .{ 4, 5, 6 },
        .{ 6, 5, 4 },
        .{ 4, 6, 5 },
    });

    const res = mulMat(Mat3, mat1, mat2);

    const expected = toColumns(Mat3, .{
        .{ 28, 33, 29 },
        .{ 28, 31, 31 },
        .{ 30, 32, 28 },
    });

    try std.testing.expectEqual(expected, res);
}

pub fn translate(comptime MatrixType: type) MatrixType {}

test "matrix translate" {}

pub fn rotate(comptime MatrixType: type) MatrixType {}

test "matrix rotate" {}

pub fn scale(comptime MatrixType: type) MatrixType {}

test "matrix scale" {}

pub fn lookAt(comptime MatrixType: type) MatrixType {}

test "matrix lookAt" {}

pub fn perspective(comptime MatrixType: type) MatrixType {}

test "matrix perspective" {}
