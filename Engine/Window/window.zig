const std = @import("std");
const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const log = @import("Logging");

pub const Window = struct {
    /// read only
    sdl_window: *c.SDL_Window,
    /// read only
    width: u32,
    /// read only
    height: u32,

    pub const Error = error{
        SdlInitFailed,
        SdlWindowCreationFailed,
        SdlSetHintFailed,
        SdlCreateRendererFailed,
        SdlRendererSetDrawColor,
        SdlRendererClear,
        SdlRenderPresent,
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
            .sdl_window = sdl_window,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyWindow(self.sdl_window);
        c.SDL_Quit();
    }

    pub fn handleEvent(_: *@This(), event: *const c.SDL_Event) bool {
        return event.type != c.SDL_EVENT_QUIT;
    }
};
