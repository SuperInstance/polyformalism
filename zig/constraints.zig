// =============================================================================
// Polyformalism Constraint Kernel — Zig Implementation
// =============================================================================
//
// This module demonstrates three core concepts of Zig's metaprogramming and
// performance model:
//
// ── comptime ────────────────────────────────────────────────────────────────
//   Zig's "comptime" executes code at compile time rather than runtime. This
//   enables generic data structures, zero-cost abstractions, and compile-time
//   evaluation without a separate macro language. In this module, comptime is
//   used to generate test arrays, derive array sizes, and verify invariants
//   before the binary even runs. Everything with a comptime-known value can be
//   evaluated during compilation, producing tighter code.
//
// ── @Vector ────────────────────────────────────────────────────────────────
//   The @Vector builtin maps directly to CPU SIMD registers (SSE/AVX/NEON).
//   Operations on vectors — comparisons, arithmetic, bitwise — generate single
//   instructions on supporting hardware. Zig makes SIMD explicit without
//   requiring intrinsics: you declare a vector type, operate on it with normal
//   operators, and the compiler lowers it to vector instructions. The compiler
//   also auto-vectorizes scalar loops when it can prove independence, but
//   @Vector gives deterministic, guaranteed SIMD.
//
// ── Safety without runtime cost ─────────────────────────────────────────────
//   Zig provides bounds-checked slices, optional types, and undefined-behavior
//   detection in Debug and ReleaseSafe modes. In ReleaseFast these checks are
//   removed, yielding C-level performance. The same source code can be built
//   for safety (development) or speed (production).
//
// ── Comptime + @Vector synergy ──────────────────────────────────────────────
//   By declaring [16]i32 arrays and operating on them as @Vector(16, i32), we
//   ensure the compiler emits a single SIMD compare instruction for 16 values
//   at once. Compile-time known array sizes let us use comptime to dimension
//   test vectors without runtime allocation.
// =============================================================================

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const bit_set = std.bit_set;

// ── 1. Constraint Check ────────────────────────────────────────────────────
// Uses SIMD vectors to check all values lie within [lower, upper].

/// Returns true iff every value in [values] satisfies lower[i] <= values[i] <=
/// upper[i]. Uses @Vector for a single SIMD compare against each bound.
pub fn constraintCheck(lower: [16]i32, upper: [16]i32, values: [16]i32) bool {
    const vec_lower: @Vector(16, i32) = lower;
    const vec_upper: @Vector(16, i32) = upper;
    const vec_values: @Vector(16, i32) = values;

    // Single SIMD instruction pair (or one with predicated compare):
    //   values >= lower  AND  values <= upper
    const ge = vec_values >= vec_lower;
    const le = vec_values <= vec_upper;

    // @reduce with .And gives one bool: true iff all lanes satisfied both.
    return @reduce(.And, ge) and @reduce(.And, le);
}

// ── 2. Bloom Filter Merge (CRDT Semilattice) ───────────────────────────────
// Bitwise OR merge for bloom filters. Since OR is idempotent, commutative, and
// associative, this forms a join-semilattice — perfect for CRDT synchronization
// of probabilistic set representations.

/// Bitwise-OR merge dst into src (dst |= src). This is a CRDT semilattice join:
/// monotonic, idempotent, commutative, associative. After merging, dst
/// contains the union of both filters. Handles arbitrary-length arrays.
pub fn bloomMerge(dst: []u64, src: []u64) void {
    // Use comptime to split into 64-bit SIMD lanes where possible.
    // For simplicity and correctness, we iterate in comptime-known chunks
    // using the smallest common SIMD width.
    var i: usize = 0;
    const simd_len = 8; // 8 × u64 = 512-bit AVX-512 width
    while (i + simd_len <= dst.len and i + simd_len <= src.len) {
        const dst_vec: @Vector(simd_len, u64) = dst[i..][0..simd_len].*;
        const src_vec: @Vector(simd_len, u64) = src[i..][0..simd_len].*;
        dst[i..][0..simd_len].* = dst_vec | src_vec;
        i += simd_len;
    }
    // Tail — handle any remaining elements scalar.
    while (i < dst.len and i < src.len) : (i += 1) {
        dst[i] |= src[i];
    }
}

// ── 3. Eisenstein Integer Norm ──────────────────────────────────────────────
// Norm of the Eisenstein integer a + bω, where ω = e^(2πi/3) = (-1 + i√3)/2.
//   N(a + bω) = a² - ab + b²
// This is the squared modulus in the Eisenstein integer ring Z[ω].

/// Compute the norm of an Eisenstein integer a + bω.
/// Returns a*a - a*b + b*b as an i64 (the squared magnitude).
pub fn eisensteinNorm(a: i32, b: i32) i64 {
    const aa = @as(i64, a) * @as(i64, a);
    const ab = @as(i64, a) * @as(i64, b);
    const bb = @as(i64, b) * @as(i64, b);
    return aa - ab + bb;
}

// ── Helper: Hash to bloom filter indices ────────────────────────────────────

fn hashToIndex(key: u64, num_bits: u64) u64 {
    // SplitMix64 — fast, deterministic hash suitable for bloom filters.
    var h = key;
    h ^= h >> 30;
    h *%= 0xbf58476d1ce4e5b9;
    h ^= h >> 27;
    h *%= 0x94d049bb133111eb;
    h ^= h >> 31;
    return h % num_bits;
}

fn bloomInsert(filter: []u64, key: u64) void {
    const num_bits = filter.len * 64;
    // Three hash-derived indices for reasonable false-positive rate.
    const @

// ── Main ────────────────────────────────────────────────────────────────────

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // ── Test 1: Constraint Check ───────────────────────────────────────────

    try stdout.writeAll("=== Constraint Check ===\n");

    const lower = comptime blk: {
        var arr: [16]i32 = undefined;
        for (&arr, 0..) |*v, i| v.* = 0;
        break :blk arr;
    };
    const upper = comptime blk: {
        var arr: [16]i32 = undefined;
        for (&arr, 0..) |*v, i| v.* = 100;
        break :blk arr;
    };

    const values_pass = comptime blk: {
        break :blk [_]i32{
            25, 30, 35, 40,
            50, 60, 70, 80,
            10, 20, 30, 40,
            55, 65, 75, 85,
        };
    };

    const values_fail = comptime blk: {
        var arr: [16]i32 = undefined;
        for (&arr, 0..) |*v, i| v.* = @intCast(200 + i);
        break :blk arr;
    };

    const pass = constraintCheck(lower, upper, values_pass);
    try stdout.print("values in [0..100] (expect PASS): {s}\n", .{if (pass) "PASS" else "FAIL"});

    const fail = constraintCheck(lower, upper, values_fail);
    try stdout.print("values 200..215 in [0..100] (expect FAIL): {s}\n", .{if (fail) "PASS" else "FAIL"});

    // ── Test 2: Bloom Filter Merge ─────────────────────────────────────────

    try stdout.writeAll("\n=== Bloom Filter Merge ===\n");

    const bloom_len = 1000;
    var filter_a: [bloom_len]u64 = comptime blk: {
        break :blk [_]u64{0} ** bloom_len;
    };
    var filter_b: [bloom_len]u64 = comptime blk: {
        break :blk [_]u64{0} ** bloom_len;
    };

    // Insert keys into separate filters
    bloomInsert(&filter_a, 42);
    bloomInsert(&filter_a, 999);
    bloomInsert(&filter_b, 500);
    bloomInsert(&filter_b, 999);

    // Merge: filter_a |= filter_b (join/semilattice merge)
    bloomMerge(&filter_a, &filter_b);

    try stdout.print("contains 42  (should be true):  {}\n", .{bloomContains(&filter_a, 42)});
    try stdout.print("contains 500 (should be true):  {}\n", .{bloomContains(&filter_a, 500)});
    try stdout.print("contains 999 (should be true):  {}\n", .{bloomContains(&filter_a, 999)});
    try stdout.print("contains 9999 (should be false): {}\n", .{bloomContains(&filter_a, 9999)});

    // ── Test 3: Eisenstein Norms ───────────────────────────────────────────

    try stdout.writeAll("\n=== Eisenstein Norms ===\n");

    const test_cases = comptime [_]struct { a: i32, b: i32, expected: i64 }{
        .{ .a = 3, .b = 0, .expected = 9 },
        .{ .a = 0, .b = 1, .expected = 1 },
        .{ .a = 2, .b = -1, .expected = 7 },
        .{ .a = -1, .b = 2, .expected = 7 },
        .{ .a = 5, .b = 5, .expected = 25 },
    };

    inline for (test_cases) |tc| {
        const n = eisensteinNorm(tc.a, tc.b);
        const status = if (n == tc.expected) "OK" else "MISMATCH";
        try stdout.print("norm({d:3}, {d:3}) = {d:3}  (expected {d:3})  {s}\n", .{
            tc.a, tc.b, n, tc.expected, status,
        });
    }

    // ── Summary ────────────────────────────────────────────────────────────

    try stdout.writeAll("\nAll tests completed.\n");
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "constraintCheck: all values in bounds" {
    const lower = [_]i32{0} ** 16;
    const upper = [_]i32{100} ** 16;
    const values = [_]i32{
        25, 30, 35, 40,
        50, 60, 70, 80,
        10, 20, 30, 40,
        55, 65, 75, 85,
    };
    try testing.expect(constraintCheck(lower, upper, values));
}

test "constraintCheck: values out of bounds" {
    const lower = [_]i32{0} ** 16;
    const upper = [_]i32{100} ** 16;
    var values: [16]i32 = undefined;
    for (&values, 0..) |*v, i| v.* = @intCast(200 + i);
    try testing.expect(!constraintCheck(lower, upper, values));
}

test "bloomMerge: merge two filters" {
    var a: [8]u64 = [_]u64{0} ** 8;
    var b: [8]u64 = [_]u64{0} ** 8;
    a[0] = 0b0011;
    b[0] = 0b1100;
    bloomMerge(&a, &b);
    try testing.expect(a[0] == 0b1111);
}

test "bloomMerge: idempotent (dst ∩ dst == dst)" {
    var a: [8]u64 = [_]u64{0} ** 8;
    a[0] = 0xDEADBEEF;
    const original = a[0];
    bloomMerge(&a, &a);
    try testing.expect(a[0] == original);
}

test "eisensteinNorm: known values" {
    try testing.expect(eisensteinNorm(3, 0) == 9);
    try testing.expect(eisensteinNorm(0, 1) == 1);
    try testing.expect(eisensteinNorm(2, -1) == 7);
    try testing.expect(eisensteinNorm(-1, 2) == 7);
    try testing.expect(eisensteinNorm(5, 5) == 25);
}

test "eisensteinNorm: symmetric" {
    // N(a, b) = N(b, a) — the norm is symmetric
    const ab = eisensteinNorm(7, 3);
    const ba = eisensteinNorm(3, 7);
    try testing.expect(ab == ba);
}
