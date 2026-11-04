const std = @import("std");
const math = std.math;
const testing = std.testing;

// translated, I hope correctly, from /perfaware/part2/listing_0065_haversine_formula.cpp

pub fn haversine(x0: f64, y0: f64, x1: f64, y1: f64) f64 {
    const lat1 = radiansFromDegrees(y0);
    const lat2 = radiansFromDegrees(y1);

    const dLat = radiansFromDegrees(y1 - y0);
    const dLon = radiansFromDegrees(x1 - x0);

    const a = math.pow(f64, @sin(dLat / 2.0), 2) + @cos(lat1) * @cos(lat2) * math.pow(f64, @sin(dLon / 2.0), 2);

    return 2.0 * math.asin(@sqrt(a));
}

const PI_DIVIDED_BY_180 = math.pi / 180.0;

fn radiansFromDegrees(degrees: f64) f64 {
    return PI_DIVIDED_BY_180 * degrees;
}

test "sanity check from https://www.vcalc.com/wiki/vcalc/haversine-distance" {
    const actual = haversine(0, 0, 1, 1) * 6371; // approx average radius of earth in km according to https://en.wikipedia.org/wiki/Earth_radius
    // meant to match what mine returns (central angle) with their generator (great circle distance on earth's surface in km)

    try testing.expectApproxEqRel(157.25, actual, 0.00001);
}
