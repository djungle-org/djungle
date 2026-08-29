const std = @import("std");

const c = @import("C").c;
const log = @import("Logging");

pub const ImageError = error{
    FailedToLoad,
};

pub const Image = struct {
    /// readonly
    pixels: []u8,
    /// readonly
    width: u32,
    /// readonly
    height: u32,

    pub fn init(path: [:0]const u8) !@This() {
        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;

        const pixels = c.stbi_load(
            path,
            &width,
            &height,
            &channels,
            c.STBI_rgb_alpha,
        ) orelse {
            log.err(@src(), "stbi_load failed: {s}", .{c.stbi_failure_reason()});
            return ImageError.FailedToLoad;
        };

        const w: usize = @intCast(width);
        const h: usize = @intCast(width);

        const pixels_len = w * h * c.STBI_rgb_alpha;

        return .{
            .pixels = pixels[0..pixels_len],
            .width = @intCast(width),
            .height = @intCast(height),
        };
    }

    pub fn deinit(self: *@This()) void {
        c.stbi_image_free(@ptrCast(self.pixels.ptr));
    }
};
