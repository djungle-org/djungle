pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
});

const log = @import("Logging");

pub fn sdlCheck(comptime T: type, check: ?T, fail: anyerror) !T {
    if (!check) {
        log.err(@src(), "{s}", .{c.SDL_GetError()});
        return fail;
    }

    return check.?;
}
