const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const testing = std.testing;
const time = std.time;

// everything is in microseconds because that's what the zig readOSTimer implementation uses

fn readOSTimer(io: Io) u64 {
    return @intCast(Io.Timestamp.now(io, .awake).toMicroseconds());
}

pub inline fn readCPUTimer() u64 {
    var result: u64 = undefined;

    asm volatile ("mrs %[result], cntvct_el0"
        : [result] "=r" (result),
    );

    return result;
}

// returns cpu ticks per second
pub fn estimateCPUTimerFreq(io: Io, timeToWaitMicroseconds: u64) u64 {
    const cpuStart = readCPUTimer();
    const osStart = readOSTimer(io);

    var osElapsed: u64 = 0;
    while (osElapsed < timeToWaitMicroseconds) {
        osElapsed = readOSTimer(io) - osStart;
    }

    const cpuElapsed = readCPUTimer() - cpuStart;

    return cpuElapsed * time.us_per_s / osElapsed;
}

// on my (apple silicon) chip there's a way to just read this
// fortunately, it shows that the estimate was pretty accurate
pub fn getCPUTimerFreq() u64 {
    var result: u64 = undefined;

    asm volatile ("mrs %[result], cntfrq_el0"
        : [result] "=r" (result),
    );

    return result;
}

test "CPU Frequency" {
    _ = struct {
        test "estimateCPUFreq" {
            const result = estimateCPUTimerFreq(testing.io, 100_000);

            debug.print("{}\n", .{result});
        }

        test "getCPUFreq" {
            const result = getCPUTimerFreq();

            debug.print("{}\n", .{result});
        }

        test "compareImplementations" {
            const estimate = estimateCPUTimerFreq(testing.io, 100_000);
            const get = getCPUTimerFreq();

            try testing.expectApproxEqAbs(@as(f64, @floatFromInt(get)), @as(f64, @floatFromInt(estimate)), 512);
        }
    };
}
