const std = @import("std");
const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const log = @import("Logging");

pub const Window = struct {
    /// readonly
    sdl_window: *c.SDL_Window,
    /// readonly
    width: u32,
    /// readonly
    height: u32,
    /// readonly
    focused: bool = false,

    pub const Error = error{
        SdlInitFailed,
        SdlWindowCreationFailed,
        SdlSetHintFailed,
        FailedToSetLockAndHideCursor,
        FailedToGetWindowSize,
    };

    pub fn init(width: u32, height: u32, name: [:0]const u8) !@This() {
        try sdlCheckBool(@src(), c.SDL_Init(c.SDL_INIT_VIDEO), Error.SdlInitFailed);

        try sdlCheckBool(@src(), c.SDL_SetHint(c.SDL_HINT_APP_ID, name), Error.SdlSetHintFailed);

        const sdl_window = try sdlCheck(
            @src(),
            *c.SDL_Window,
            c.SDL_CreateWindow(name, @intCast(width), @intCast(height), c.SDL_WINDOW_RESIZABLE),
            Error.SdlWindowCreationFailed,
        );

        return Window{
            .width = width,
            .height = height,
            .focused = false,
            .sdl_window = sdl_window,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyWindow(self.sdl_window);
        c.SDL_Quit();
    }

    pub fn setCursorLockAndHide(self: *@This(), enable: bool) !void {
        self.focused = enable;

        try sdlCheckBool(
            @src(),
            c.SDL_SetWindowRelativeMouseMode(self.sdl_window, enable),
            Error.FailedToSetLockAndHideCursor,
        );
    }

    pub fn handleEvent(self: *@This(), event: *const c.SDL_Event) !bool {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                return false;
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                var w: c_int = undefined;
                var h: c_int = undefined;

                try sdlCheckBool(
                    @src(),
                    c.SDL_GetWindowSizeInPixels(self.sdl_window, &w, &h),
                    Error.FailedToGetWindowSize,
                );

                self.width = @intCast(w);
                self.height = @intCast(h);
            },
            c.SDL_EVENT_KEY_DOWN => {
                if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                    try self.setCursorLockAndHide(!self.focused);
                }
            },
            else => {},
        }

        return true;
    }
};
