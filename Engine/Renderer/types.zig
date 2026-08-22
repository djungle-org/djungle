const c = @import("C").c;

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);

pub const SampleCount = enum {
    _1,
    _2,
    _4,
    _8,

    pub fn toSdl(self: @This()) c_uint {
        return switch (self) {
            ._1 => c.SDL_GPU_SAMPLECOUNT_1,
            ._2 => c.SDL_GPU_SAMPLECOUNT_2,
            ._4 => c.SDL_GPU_SAMPLECOUNT_4,
            ._8 => c.SDL_GPU_SAMPLECOUNT_8,
        };
    }
};
