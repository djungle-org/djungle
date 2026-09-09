const std = @import("std");

const Seconds = f32;
const Milliseconds = f32;
const Nanoseconds = i96;

delta_time: Seconds = 0,
ms_per_frame: Milliseconds = 0,
last_time: Nanoseconds = 0,

pub fn calculate(self: *@This(), io: std.Io, clock: std.Io.Clock) void {
    const current_timestamp = clock.now(io);
    const current_time = current_timestamp.toNanoseconds();

    const delta_time_nano = current_time - self.last_time;

    self.delta_time = @as(f32, @floatFromInt(delta_time_nano)) / 1_000_000_000;
    self.ms_per_frame = self.delta_time * 1000;

    self.last_time = current_time;
}
