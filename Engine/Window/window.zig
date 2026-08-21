const std = @import("std");

const c = @import("C").c;

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
    _renderer: *c.SDL_Renderer,

    pub fn init(width: u32, height: u32, comptime name: [:0]const u8) WindowError!@This() {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return WindowError.SdlInitFailed;
        }

        if (!c.SDL_SetHint(c.SDL_HINT_APP_ID, name)) {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return WindowError.SdlSetHintFailed;
        }

        const sdl_window = c.SDL_CreateWindow(name, @intCast(width), @intCast(height), c.SDL_WINDOW_RESIZABLE) orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return WindowError.SdlWindowCreationFailed;
        };

        const renderer = c.SDL_CreateRenderer(sdl_window, null) orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return WindowError.SdlCreateRendererFailed;
        };

        return Window{
            ._width = width,
            ._height = height,
            ._sdl_window = sdl_window,
            ._renderer = renderer,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyRenderer(self._renderer);
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
