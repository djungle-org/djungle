const std = @import("std");
const c = @import("C").c;
const sdlCheck = @import("C").sdlCheck;
const sdlCheckBool = @import("C").sdlCheckBool;
const log = @import("Logging");

pub const WindowError = error{
    SdlInitFailed,
    SdlWindowCreationFailed,
    SdlSetHintFailed,
    SdlCreateRendererFailed,
    SdlRendererSetDrawColor,
    SdlRendererClear,
    SdlRenderPresent,
};

pub const Window = struct {
    _width: u32,
    _height: u32,

    _sdl_window: *c.SDL_Window,

    pub fn init(width: u32, height: u32, comptime name: [:0]const u8) !@This() {
        try sdlCheckBool(@src(), c.SDL_Init(c.SDL_INIT_VIDEO), WindowError.SdlInitFailed);

        try sdlCheckBool(@src(), c.SDL_SetHint(c.SDL_HINT_APP_ID, name), WindowError.SdlSetHintFailed);

        const sdl_window = try sdlCheck(
            @src(),
            *c.SDL_Window,
            c.SDL_CreateWindow(name, @intCast(width), @intCast(height), c.SDL_WINDOW_RESIZABLE),
            WindowError.SdlWindowCreationFailed,
        );

        return Window{
            ._width = width,
            ._height = height,
            ._sdl_window = sdl_window,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyWindow(self._sdl_window);
        c.SDL_Quit();
    }

    pub fn getWidth(self: @This()) u32 {
        return self._width;
    }

    pub fn getHeight(self: @This()) u32 {
        return self._height;
    }

    pub fn toSdl(self: *@This()) *c.SDL_Window {
        return self._sdl_window;
    }

    pub fn pollEvents(_: @This()) bool {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                return false;
            }
        }

        return true;
    }
};
