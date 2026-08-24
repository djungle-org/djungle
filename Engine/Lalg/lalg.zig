const std = @import("std");

pub const VectorError = error{
    DivByZero,
};

// all vectors origin is 0

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

// column major, each element of array is a column

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
                @compileError("Requires f32 vector, got " ++ @typeName(T));
            }
        },
        else => @compileError("Requires an @Vector type, got " ++ @typeName(T)),
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

/// for now matrices have to be square
fn assertMatrixType(comptime T: type) void {
    comptime switch (@typeInfo(T)) {
        .array => |info| {
            assertVectorType(info.child);

            if (info.len != vecLanes(info.child)) {
                @compileError("Matrices must be square, got " ++ @typeName(T));
            }
        },
        else => @compileError("Matrix must be an array of @Vectors, got " ++ @typeName(T)),
    };
}

fn MatChild(comptime T: type) type {
    comptime assertMatrixType(T);

    return @typeInfo(T).array.child;
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
    comptime assertMatrixType(MatrixType);

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
pub fn toColumns(comptime MatrixType: type, mat: MatrixType) MatrixType {
    comptime assertMatrixType(MatrixType);

    return transpose(MatrixType, mat);
}

test "transpose" {
    const mat = comptime transpose(Mat3, .{
        .{ 1, 2, 3 },
        .{ 3, 2, 1 },
        .{ 1, 3, 2 },
    });

    const expected = Mat3{
        .{ 1, 3, 1 },
        .{ 2, 2, 3 },
        .{ 3, 1, 2 },
    };

    try std.testing.expectEqual(expected, mat);
}

pub fn identityMat(comptime MatrixType: type) MatrixType {
    comptime assertMatrixType(MatrixType);

    var identity = std.mem.zeroes(MatrixType);

    inline for (0..@typeInfo(MatrixType).array.len) |i| {
        identity[i][i] = 1;
    }

    return identity;
}

test "identity matrix" {
    const identity = identityMat(Mat4);

    const expected = toColumns(Mat4, .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(identity, expected);
}

pub fn addMat(comptime MatrixType: type, mat1: MatrixType, mat2: MatrixType) MatrixType {
    comptime assertMatrixType(MatrixType);

    var result = mat1;

    inline for (0..mat1.len) |i| {
        result[i] += mat2[i];
    }

    return result;
}

test "matrix addition" {
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

    const result = addMat(Mat3, mat1, mat2);

    const expected = toColumns(Mat3, .{
        .{ 5, 7, 9 },
        .{ 9, 7, 5 },
        .{ 5, 9, 7 },
    });

    try std.testing.expectEqual(expected, result);
}

pub fn mulMatScalar(comptime MatrixType: type, mat: MatrixType, scalar: f32) MatrixType {
    var result: MatrixType = undefined;

    inline for (0..mat.len) |i| {
        result[i] = scaleVec(MatChild(MatrixType), mat[i], scalar);
    }

    return result;
}

test "matrix-scalar multiply" {
    const mat = toColumns(Mat4, .{
        .{ 1, 0, 2, 3 },
        .{ 4, 2, 1, 7 },
        .{ 9, 3, 8, 4 },
        .{ 1, 6, 2, 5 },
    });

    const res = mulMatScalar(Mat4, mat, 2);

    const expected = toColumns(Mat4, .{
        .{ 2, 0, 4, 6 },
        .{ 8, 4, 2, 14 },
        .{ 18, 6, 16, 8 },
        .{ 2, 12, 4, 10 },
    });

    try std.testing.expectEqual(expected, res);
}

pub fn mulMatVec(comptime MatrixType: type, mat: MatrixType, vec: MatChild(MatrixType)) @typeInfo(MatrixType).array.child {
    comptime assertMatrixType(MatrixType);

    const VectorType = @typeInfo(MatrixType).array.child;

    var result: VectorType = @splat(0);

    inline for (0..mat.len) |i| {
        const scaled_column = scaleVec(VectorType, mat[i], vec[i]);

        result += scaled_column;
    }

    return result;
}

test "matrix-vector multiply" {
    const mat = toColumns(Mat4, .{
        .{ 1, 2, 3, 7 },
        .{ 3, 2, 1, 2 },
        .{ 1, 4, 3, 9 },
        .{ 5, 3, 6, 8 },
    });

    const vec = Vec4{ 4, 5, 6, 2 };

    const res = mulMatVec(Mat4, mat, vec);

    try std.testing.expectEqual(Vec4{ 46, 32, 60, 87 }, res);
}

pub fn mulMat(comptime MatrixType: type, mat1: MatrixType, mat2: MatrixType) MatrixType {
    comptime assertMatrixType(MatrixType);

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

    var res = mulMat(Mat3, mat1, mat2);

    var expected = toColumns(Mat3, .{
        .{ 28, 33, 29 },
        .{ 28, 31, 31 },
        .{ 30, 32, 28 },
    });

    try std.testing.expectEqual(expected, res);

    // non commutative
    res = mulMat(Mat3, mat2, mat1);

    expected = toColumns(Mat3, .{
        .{ 25, 36, 29 },
        .{ 25, 34, 31 },
        .{ 27, 35, 28 },
    });

    try std.testing.expectEqual(expected, res);
}

pub fn translate(offset: Vec3) Mat4 {
    return toColumns(Mat4, .{
        .{ 1, 0, 0, offset[0] },
        .{ 0, 1, 0, offset[1] },
        .{ 0, 0, 1, offset[2] },
        .{ 0, 0, 0, 1 },
    });
}

test "matrix translate" {
    const translation = translate(.{ 3, 4, 5 });

    var expected = toColumns(Mat4, .{
        .{ 1, 0, 0, 3 },
        .{ 0, 1, 0, 4 },
        .{ 0, 0, 1, 5 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(expected, translation);

    const mat = toColumns(Mat4, .{
        .{ 3, 2, 4, 1 },
        .{ 6, 5, 2, 1 },
        .{ 2, 3, 5, 1 },
        .{ 1, 1, 1, 1 },
    });

    const translated = mulMat(Mat4, translation, mat);

    expected = toColumns(Mat4, .{
        .{ 6, 5, 7, 4 },
        .{ 10, 9, 6, 5 },
        .{ 7, 8, 10, 6 },
        .{ 1, 1, 1, 1 },
    });

    try std.testing.expectEqual(expected, translated);
}

/// axis will be normalized
pub fn rotate(axis: Vec3, radians: f32) !Mat4 {
    const axis_n = try normalize(Vec3, axis);

    const axis_mat = toColumns(Mat3, .{
        .{ 0, -axis_n[2], axis_n[1] },
        .{ axis_n[2], 0, -axis_n[0] },
        .{ -axis_n[1], axis_n[0], 0 },
    });

    const axis_mat_sqr = mulMat(Mat3, axis_mat, axis_mat);

    const identity = identityMat(Mat3);
    const sin = mulMatScalar(Mat3, axis_mat, @sin(radians));
    const cos = mulMatScalar(Mat3, axis_mat_sqr, 1 - @cos(radians));

    const rotation = addMat(Mat3, identity, addMat(Mat3, sin, cos));

    const mat4 = toColumns(Mat4, .{
        .{ rotation[0][0], rotation[1][0], rotation[2][0], 0 },
        .{ rotation[0][1], rotation[1][1], rotation[2][1], 0 },
        .{ rotation[0][2], rotation[1][2], rotation[2][2], 0 },
        .{ 0, 0, 0, 1 },
    });

    return mat4;
}

test "matrix rotate" {
    const rotated = try rotate(.{ 0, 0, 1 }, std.math.degreesToRadians(90));

    const expected = toColumns(Mat4, .{
        .{ 0, -1, 0, 0 },
        .{ 1, 0, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(expected, rotated);
}

pub fn scale(vec: Vec3) Mat4 {
    return toColumns(Mat4, .{
        .{ vec[0], 0, 0, 0 },
        .{ 0, vec[1], 0, 0 },
        .{ 0, 0, vec[2], 0 },
        .{ 0, 0, 0, 1 },
    });
}

test "matrix scale" {
    const scaled = scale(.{ 4, 3, 1 });

    const expected = toColumns(Mat4, .{
        .{ 4, 0, 0, 0 },
        .{ 0, 3, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(expected, scaled);
}

pub fn lookAt(eye: Vec3, target: Vec3, world_up: Vec3) !Mat4 {
    const forward = try normalize(Vec3, eye - target);
    const right = try normalize(Vec3, cross(world_up, forward));
    const up = cross(forward, right);

    const translation = translate(.{
        -dot(Vec3, right, eye),
        -dot(Vec3, up, eye),
        -dot(Vec3, forward, eye),
    });

    const rotation = toColumns(Mat4, .{
        .{ right[0], right[1], right[2], 0 },
        .{ up[0], up[1], up[2], 0 },
        .{ forward[0], forward[1], forward[2], 0 },
        .{ 0, 0, 0, 1 },
    });

    return mulMat(Mat4, rotation, translation);
}

test "matrix lookAt" {
    var result = try lookAt(.{ 0, 0, 0 }, .{ 0, 0, -1 }, .{ 0, 1, 0 });

    var expected = toColumns(Mat4, .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(expected, result);

    result = try lookAt(.{ 2, 3, 5 }, .{ 2, 3, 4 }, .{ 0, 1, 0 });

    expected = toColumns(Mat4, .{
        .{ 1, 0, 0, -2 },
        .{ 0, 1, 0, -3 },
        .{ 0, 0, 1, -5 },
        .{ 0, 0, 0, 1 },
    });

    try std.testing.expectEqual(expected, result);
}

pub fn perspective(comptime MatrixType: type) MatrixType {
    comptime assertMatrixType(MatrixType);
}

test "matrix perspective" {}
