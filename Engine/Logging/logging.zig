const std = @import("std");

pub fn err(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.log.err("{s}:{d} in {s}: " ++ fmt, .{ src.file, src.line, src.fn_name } ++ args);
}

pub fn warn(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.log.warn("{s}:{d} in {s}: " ++ fmt, .{ src.file, src.line, src.fn_name } ++ args);
}

pub fn debug(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.log.debug("{s}:{d} in {s}: " ++ fmt, .{ src.file, src.line, src.fn_name } ++ args);
}
