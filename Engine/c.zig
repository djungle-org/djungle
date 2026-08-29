pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("stb_image.h");
});

const std = @import("std");
const log = @import("Logging");

pub fn sdlCheck(comptime src: std.builtin.SourceLocation, comptime T: type, check: ?T, fail: anyerror) !T {
    if (check) |check_non_opt| {
        return check_non_opt;
    }

    log.err(src, "{s}", .{c.SDL_GetError()});
    return fail;
}

pub fn sdlCheckBool(comptime src: std.builtin.SourceLocation, check: bool, fail: anyerror) !void {
    if (!check) {
        log.err(src, "{s}", .{c.SDL_GetError()});
        return fail;
    }
}
