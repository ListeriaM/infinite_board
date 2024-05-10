const std = @import("std");

pub fn divFloor(num: anytype, denom: anytype) @TypeOf(num, denom) {
    if (@TypeOf(denom) == comptime_int) {
        if (comptime denom > 0 and std.math.isPowerOfTwo(denom)) {
            return num >> std.math.log2(denom);
        }
    }
    return @divFloor(num, denom);
}

pub fn mod(num: anytype, denom: anytype) if (@TypeOf(denom) == comptime_int) std.math.IntFittingRange(0, denom - 1) else @TypeOf(num, denom) {
    return if (@TypeOf(denom) == comptime_int)
        comptimeMod(num, denom)
    else
        @mod(num, denom);
}

fn comptimeMod(num: anytype, comptime denom: comptime_int) std.math.IntFittingRange(0, denom - 1) {
    return @intCast(if (denom > 0 and std.math.isPowerOfTwo(denom)) num & denom - 1 else @mod(num, denom));
}
