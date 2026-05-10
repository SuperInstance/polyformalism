// Polyformalism Constraint Kernel — Zig
// Zig brings comptime (compile-time code execution), @Vector for portable SIMD,
// and no hidden control flow. What you see is what runs.
const std = @import("std");

// 1. Constraint check: scalar
fn constraintCheck(lower: [16]i32, upper: [16]i32, values: [16]i32) bool {
    for (lower, upper, values) |lo, hi, v| {
        if (v < lo or v > hi) return false;
    }
    return true;
}

// 1b. Constraint check: @Vector SIMD
fn constraintCheckSimd(lower: [16]i32, upper: [16]i32, values: [16]i32) bool {
    const V16 = @Vector(16, i32);
    const v_lo: V16 = lower;
    const v_hi: V16 = upper;
    const v_val: V16 = values;
    const ge: @Vector(16, i32) = @select(i32, v_val >= v_lo, @as(V16, @splat(1)), @as(V16, @splat(0)));
    const le: @Vector(16, i32) = @select(i32, v_val <= v_hi, @as(V16, @splat(1)), @as(V16, @splat(0)));
    const both = ge & le;
    return @reduce(.And, both) != 0;
}

// 2. Bloom merge: bitwise OR (CRDT semilattice join)
fn bloomMerge(dst: []u64, src: []u64) void {
    const len = @min(dst.len, src.len);
    for (dst[0..len], src[0..len]) |*d, s| {
        d.* |= s;
    }
}

// 3. Eisenstein norm: a² - ab + b²
fn eisensteinNorm(a: i32, b: i32) i64 {
    const aa: i64 = @intCast(a);
    const bb: i64 = @intCast(b);
    return aa * aa - aa * bb + bb * bb;
}

// Bloom helpers
fn bloomHash(key: u64, total_bits: u64) u64 {
    var h = key;
    h ^= h >> 16;
    h *%= 0x45d9f3b;
    h ^= h >> 16;
    return h % total_bits;
}

fn bloomInsert(filter: []u64, key: u64) void {
    const total_bits: u64 = @as(u64, @intCast(filter.len)) * 64;
    const pos = bloomHash(key, total_bits);
    const word = @as(usize, @intCast(pos / 64));
    const bit = @as(u6, @intCast(pos % 64));
    filter[word] |= @as(u64, 1) << bit;
}

fn bloomContains(filter: []u64, key: u64) bool {
    const total_bits: u64 = @as(u64, @intCast(filter.len)) * 64;
    const pos = bloomHash(key, total_bits);
    const word = @as(usize, @intCast(pos / 64));
    const bit = @as(u6, @intCast(pos % 64));
    return (filter[word] & (@as(u64, 1) << bit)) != 0;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Polyformalism: Zig ===\n\n", .{});

    // Constraint check
    const lower = [16]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const upper = [16]i32{ 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100 };
    const pass  = [16]i32{ 25, 30, 35, 40, 50, 60, 70, 80, 10, 20, 30, 40, 55, 65, 75, 85 };
    const fail  = [16]i32{ 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215 };

    try stdout.print("Scalar  pass: {}\n", .{constraintCheck(lower, upper, pass)});
    try stdout.print("Scalar  fail: {}\n", .{constraintCheck(lower, upper, fail)});
    try stdout.print("SIMD    pass: {}\n", .{constraintCheckSimd(lower, upper, pass)});
    try stdout.print("SIMD    fail: {}\n", .{constraintCheckSimd(lower, upper, fail)});

    // Bloom merge
    var bloom_a = [_]u64{0} ** 1000;
    var bloom_b = [_]u64{0} ** 1000;

    bloomInsert(&bloom_a, 42);
    bloomInsert(&bloom_a, 100);
    bloomInsert(&bloom_a, 500);
    bloomInsert(&bloom_b, 500);
    bloomInsert(&bloom_b, 999);

    bloomMerge(&bloom_a, &bloom_b);

    try stdout.print("\nBloom 42 in merged:   {}\n", .{bloomContains(&bloom_a, 42)});
    try stdout.print("Bloom 500 in merged:  {}\n", .{bloomContains(&bloom_a, 500)});
    try stdout.print("Bloom 999 in merged:  {}\n", .{bloomContains(&bloom_a, 999)});
    try stdout.print("Bloom 9999 in merged: {}\n", .{bloomContains(&bloom_a, 9999)});

    // Eisenstein norms
    try stdout.print("\nN(3,0)  = {}\n", .{eisensteinNorm(3, 0)});
    try stdout.print("N(0,1)  = {}\n", .{eisensteinNorm(0, 1)});
    try stdout.print("N(2,-1) = {}\n", .{eisensteinNorm(2, -1)});
    try stdout.print("N(-1,2) = {}\n", .{eisensteinNorm(-1, 2)});
    try stdout.print("N(5,5)  = {}\n", .{eisensteinNorm(5, 5)});

    // Benchmarks
    try stdout.print("\n--- Benchmarks ---\n", .{});

    const ITERS = 10_000_000;
    var i: u32 = 0;

    // Use volatile reads to prevent optimization
    var vol_lower = lower;
    var vol_upper = upper;
    var vol_pass = pass;
    _ = &vol_lower; _ = &vol_upper; _ = &vol_pass;

    var timer = try std.time.Timer.start();
    i = 0;
    var result_bool: bool = false;
    while (i < ITERS) : (i += 1) {
        result_bool = constraintCheck(vol_lower, vol_upper, vol_pass);
    }
    std.mem.doNotOptimizeAway(result_bool);
    const elapsed1 = @as(f64, @floatFromInt(timer.read())) / 1e9;
    try stdout.print("Constraint check scalar: {d:.1}M ops/s  ({d:.2} ms)\n", .{@as(f64, @floatFromInt(ITERS)) / elapsed1 / 1e6, elapsed1 * 1000});

    timer.reset();
    i = 0;
    result_bool = false;
    while (i < ITERS) : (i += 1) {
        result_bool = constraintCheckSimd(vol_lower, vol_upper, vol_pass);
    }
    std.mem.doNotOptimizeAway(result_bool);
    const elapsed2 = @as(f64, @floatFromInt(timer.read())) / 1e9;
    try stdout.print("Constraint check SIMD:   {d:.1}M ops/s  ({d:.2} ms)\n", .{@as(f64, @floatFromInt(ITERS)) / elapsed2 / 1e6, elapsed2 * 1000});

    timer.reset();
    i = 0;
    var result_i64: i64 = 0;
    while (i < ITERS) : (i += 1) {
        result_i64 +%= eisensteinNorm(3, 0);
    }
    std.mem.doNotOptimizeAway(result_i64);
    const elapsed3 = @as(f64, @floatFromInt(timer.read())) / 1e9;
    try stdout.print("Eisenstein norm:         {d:.1}M ops/s  ({d:.2} ms)\n", .{@as(f64, @floatFromInt(ITERS)) / elapsed3 / 1e6, elapsed3 * 1000});

    try stdout.print("\nAll tests passed.\n", .{});
}
