const std = @import("std");
const ArrayList = std.ArrayList;
const Io = std.Io;
const Random = std.Random;
const math = std.math;
const mem = std.mem;

const ref = @import("./haversine_reference.zig");

pub const Input = struct {
    size: u64,
    seed: u64,
    sum: f64,
    pairs: [][2]Point,

    pub fn initRandom(a: mem.Allocator, size: u64, seed: u64) !Input {
        var prng = Random.DefaultPrng.init(seed);
        const rand = prng.random();

        // TODO:: it'd be fun to generate these in threads, one per chunk of the array
        var pairs = try ArrayList([2]Point).initCapacity(a, size);
        var sum: f64 = 0.0;
        for (0..size) |_| {
            const p0 = Point.initRandom(rand);
            const p1 = Point.initRandom(rand);
            pairs.appendAssumeCapacity(.{ p0, p1 });
            sum += ref.haversine(p0.x, p0.y, p1.x, p1.y);
        }

        return .{
            .size = size,
            .seed = seed,
            .sum = sum,
            .pairs = try pairs.toOwnedSlice(a),
        };
    }

    pub fn format(s: *const Input, w: *Io.Writer) !void {
        const fmt =
            \\{{
            \\  size: {d},
            \\  seed: {d},
            \\  sum: {d},
            \\  pairs: [ ... ],
            \\}}
        ;

        try w.print(fmt, .{ s.size, s.seed, s.sum });
    }
};

pub const Point = struct {
    x: f64,
    y: f64,

    pub fn initRandom(rand: Random) Point {
        // see https://www.jasondavies.com/maps/random-points/
        const xUnitSphere = rand.float(f64);
        const yUnitSphere = math.acos(2 * rand.float(f64) - 1);

        return .{
            .x = (xUnitSphere * 360) - 180,
            .y = (yUnitSphere * 180) - 90,
        };
    }
};
