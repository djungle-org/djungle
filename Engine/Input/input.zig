const std = @import("std");

const temp_sdl = @cImport({
    @cInclude("SDL3/SDL_scancode.h");
});

const c_util = @import("C");
const c = c_util.c;
const win = @import("Window");

/// auto conversion of sdl scancodes to zig enum
/// the scancode name will be the SDL_SCANCODE_[key name here] without the SDL_SCANCODE_ prefix
/// so find the scancode names on sdl docs and just remove the SDL_SCANCODE_ prefix
pub const Scancode = blk: {
    @setEvalBranchQuota(100_000);

    const decls = @typeInfo(temp_sdl).@"struct".decls;
    var field_names: [decls.len][]const u8 = undefined;
    var field_values: [decls.len]c_int = undefined;
    var count: usize = 0;

    const prefix = "SDL_SCANCODE_";
    for (decls) |decl| {
        if (!std.mem.startsWith(u8, decl.name, prefix))
            continue;

        if (std.mem.eql(u8, decl.name, "SDL_SCANCODE_COUNT"))
            continue;

        const value = @field(temp_sdl, decl.name);

        if (@TypeOf(value) != c_int)
            continue;

        field_names[count] = decl.name[prefix.len..];
        field_values[count] = value;

        count += 1;
    }

    break :blk @Enum(c_int, .exhaustive, field_names[0..count], field_values[0..count]);
};

pub const Input = struct {
    /// readonly, use only after updated with updateMouseState()
    mouse_x: f32 = 0,
    /// readonly, use only after updated with updateMouseState()
    mouse_y: f32 = 0,
    /// readonly, use only after updated with updateMouseState()
    mouse_dx: f32 = 0,
    /// readonly, use only after updated with updateMouseState()
    mouse_dy: f32 = 0,

    /// internal
    state: []const bool,

    pub fn init() @This() {
        var state_count: c_int = undefined;
        const sdl_state = c.SDL_GetKeyboardState(&state_count);

        var mouse_x: f32 = undefined;
        var mouse_y: f32 = undefined;
        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);

        return .{
            .state = sdl_state[0..@intCast(state_count)],
        };
    }

    /// for continuous input
    pub fn getKeyState(self: *const @This(), scancode: Scancode) bool {
        return self.state[@intCast(@intFromEnum(scancode))];
    }

    /// call every frame, resets mouse deltas
    pub fn resetMouseState(self: *@This()) void {
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    pub fn handleEvent(self: *@This(), event: *const c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_x = event.motion.x;
                self.mouse_y = event.motion.y;

                self.mouse_dx += event.motion.xrel;
                self.mouse_dy += event.motion.yrel;
            },
            else => {},
        }
    }
};
