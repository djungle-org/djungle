const c = @import("C").c;

const win = @import("Window");
const ipt = @import("Input");

/// returns bool, true: the app should stay running, false: app should close
pub fn handleEvents(window: *win.Window, input: *ipt.Input) !bool {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        if (!try window.handleEvent(&event)) return false;
        input.handleEvent(&event);
    }

    return true;
}
