const c = @import("C").c;

const win = @import("Window");
const ipt = @import("Input");

focused: bool = true,

/// returns bool, true: the app should stay running, false: app should close
pub fn handleEvents(self: *@This(), window: *win.Window, input: *ipt.Input) !bool {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        if (!window.handleEvent(&event)) return false;
        input.handleEvent(&event);

        switch (event.type) {
            c.SDL_EVENT_KEY_DOWN => {
                if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                    self.focused = !self.focused;

                    try input.setCursorLockAndHide(window, self.focused);
                }
            },
            else => {},
        }
    }

    return true;
}
