// Polyformalism Experiment — Constraint Kernel in Odin
// ========================================================
//
// This is part of a cross-language experiment implementing the same
// constraint kernel in multiple programming languages (C, Rust, Odin, Zig,
// Go, etc.) to compare expressiveness, performance characteristics, and
// language-level differences for solver/constraint workloads.
//
// Functions implemented (same API across all languages):
//   1. constraint_check  — bounds check using SIMD vectors
//   2. bloom_merge       — bitwise OR merge of Bloom filters (CRDT semilattice join)
//   3. eisenstein_norm   — Eisenstein integer norm: a² - a*b + b²
//
// How Odin differs from C/Rust:
//   - Odin's #simd[N]T is a built-in language construct, not a library.
//     SIMD vectors are first-class: you can compare them with <, >, <=, >=
//     operators directly, and results are mask vectors (all-ones / all-zeroes).
//   - No traits, generics, or templates needed for simple array ops.
//     Odin leans on procedural polymorphism via param-poly procedures.
//   - Slices in Odin are fat pointers (ptr + len) without a separate
//     borrow-checker — memory is managed with explicit allocators.
//   - The entire standard library is one self-contained `core` package
//     (no libc dependency for most operations), making cross-compilation
//     and embedding trivial.
//   - Odin's `reduce_all` on a SIMD mask vector gives a single bool
//     without any explicit horizontal reduction logic — the compiler
//     picks the right PTEST/MOVMSK instruction for the target.
//   - `context` is an implicit allocator parameter threading through every
//     procedure, making allocator-switching trivial vs. C's global
//     malloc/free or Rust's complicated Allocator trait.

package constraints

import "core:fmt"
import "core:simd"

// ---------------------------------------------------------------------------
// 1. Constraint Check (SIMD vectorized)
// ---------------------------------------------------------------------------

// constraint_check returns true iff lower[i] <= values[i] <= upper[i] for all i.
// Uses a 512-bit SIMD vector (16 × i32) for a single pass comparison.
constraint_check :: proc(lower: [16]i32, upper: [16]i32, values: [16]i32) -> bool {
    // Load arrays into SIMD vectors
    v_lower := transmute(simd.i32x16, lower)
    v_upper := transmute(simd.i32x16, upper)
    v_values := transmute(simd.i32x16, values)

    // Element-wise: (values >= lower) AND (values <= upper)
    // SIMD comparison operators in Odin return mask vectors.
    mask_ge: simd.i32x16 = v_values >= v_lower
    mask_le: simd.i32x16 = v_values <= v_upper

    // Combine masks — lanes where both are true remain 0xFFFFFFFF, others 0.
    v_ok := mask_ge & mask_le

    // Horizontal reduction: all lanes must be set (non-zero).
    return simd.reduce_all(v_ok)
}

// ---------------------------------------------------------------------------
// 2. Bloom Filter Merge (CRDT semilattice join)
// ---------------------------------------------------------------------------

// bloom_merge performs dst = dst OR src elementwise.
// This is the CRDT merge operation for a Bloom filter: the join in a
// semilattice where the partial order is subset-of-bits.
bloom_merge :: proc(dst: []u64, src: []u64) {
    // Odin slices carry length; no separate len parameter needed.
    // The idiomatic approach uses a range-based for loop, but for
    // performance we use an explicit index loop (the compiler will
    // auto-vectorize this in release builds).
    n := min(len(dst), len(src))
    for i in 0 ..< n {
        dst[i] |= src[i]
    }
}

// ---------------------------------------------------------------------------
// 3. Eisenstein Integer Norm
// ---------------------------------------------------------------------------

// eisenstein_norm computes a² - a*b + b² for Eisenstein integers.
// Eisenstein integers are complex numbers of the form a + b*ω where
// ω = (-1 + sqrt(-3))/2 is a primitive cube root of unity.
// The norm N(a + bω) = a² - ab + b² is a quadratic form with
// hexagonal symmetry — the distance metric on the triangular lattice.
eisenstein_norm :: proc(a: i32, b: i32) -> i64 {
    // Promote to 64-bit to avoid overflow on moderate inputs.
    // Max safe for i32: a,b up to ~2.1e9 would overflow i64 at 2.2e18,
    // but typical use is well within range.
    ai := i64(a)
    bi := i64(b)
    return ai * ai - ai * bi + bi * bi
}

// ---------------------------------------------------------------------------
// 4. Main — Demo / Test Driver
// ---------------------------------------------------------------------------

main :: proc() {
    fmt.println("=== Polyformalism Constraint Kernel (Odin) ===")
    fmt.println()

    // ----- Constraint Check Demo -----
    fmt.println("--- constraint_check ---")

    lower_all := [16]i32 {
        0, 10, 20, 30, 40, 50, 60, 70,
        80, 90, 100, 110, 120, 130, 140, 150,
    }
    upper_all := [16]i32 {
        5, 15, 25, 35, 45, 55, 65, 75,
        85, 95, 105, 115, 125, 135, 145, 155,
    }

    // Test 1: All values in bounds
    values_ok := [16]i32 {
        3, 12, 22, 32, 42, 52, 62, 72,
        82, 92, 102, 112, 122, 132, 142, 152,
    }
    ok := constraint_check(lower_all, upper_all, values_ok)
    fmt.printf("  All in-bounds values: %v → %b\n", values_ok, ok)

    // Test 2: One value out of bounds (too low)
    values_low := [16]i32 {
        -5, 12, 22, 32, 42, 52, 62, 72,
        82, 92, 102, 112, 122, 132, 142, 152,
    }
    ok = constraint_check(lower_all, upper_all, values_low)
    fmt.printf("  One too-low value:   %v → %b\n", values_low, ok)

    // Test 3: One value out of bounds (too high)
    values_high := [16]i32 {
        3, 12, 22, 32, 999, 52, 62, 72,
        82, 92, 102, 112, 122, 132, 142, 152,
    }
    ok = constraint_check(lower_all, upper_all, values_high)
    fmt.printf("  One too-high value:  %v → %b\n", values_high, ok)

    fmt.println()

    // ----- Bloom Filter Merge Demo -----
    fmt.println("--- bloom_merge ---")

    // Create two 1000-element Bloom filters
    // Using simple hash functions for demo purposes.
    BLOOM_SIZE :: 1000

    bloom_a := make([]u64, BLOOM_SIZE)
    defer delete(bloom_a)
    bloom_b := make([]u64, BLOOM_SIZE)
    defer delete(bloom_b)

    // Helper to set bits for a key (simple hash: key mod 63, key mod 67, key mod 71)
    bloom_insert :: proc(bloom: []u64, key: int) {
        n := len(bloom)
        for modulus in [3]u64{63, 67, 71} {
            idx := (u64(key) * modulus) % u64(n)
            // Set bit at position idx % 64 within word idx / 64
            word := idx / 64
            bit  := idx % 64
            bloom[word] |= u64(1) << uint(bit)
        }
    }

    // Insert some keys into bloom_a
    for k in [5]int{42, 128, 256, 512, 777} {
        bloom_insert(bloom_a, k)
    }

    // Insert different keys into bloom_b
    for k in [5]int{128, 256, 999, 500, 777} {
        bloom_insert(bloom_b, k)
    }

    // Check membership before merge
    bloom_check :: proc(bloom: []u64, key: int) -> bool {
        n := len(bloom)
        for modulus in [3]u64{63, 67, 71} {
            idx := (u64(key) * modulus) % u64(n)
            word := idx / 64
            bit  := idx % 64
            if bloom[word] & (u64(1) << uint(bit)) == 0 {
                return false
            }
        }
        return true
    }

    fmt.println("  Before merge:")
    for key in [7]int{42, 128, 256, 512, 777, 999, 500} {
        in_a := bloom_check(bloom_a, key)
        in_b := bloom_check(bloom_b, key)
        fmt.printf("    key %4d: a=%b b=%b\n", key, in_a, in_b)
    }

    // Merge: bloom_a = bloom_a OR bloom_b
    bloom_merge(bloom_a, bloom_b)

    fmt.println("  After merge (dst = dst | src):")
    for key in [7]int{42, 128, 256, 512, 777, 999, 500} {
        in_a := bloom_check(bloom_a, key)
        fmt.printf("    key %4d: merged=%b\n", key, in_a)
    }

    fmt.println()

    // ----- Eisenstein Norm Demo -----
    fmt.println("--- eisenstein_norm ---")

    test_points := [][2]i32{
        { 3,  0},
        { 0,  1},
        { 2, -1},
        {-1,  2},
        { 5,  5},
    }

    for pt in test_points {
        nrm := eisenstein_norm(pt.x, pt.y)
        fmt.printf("  Eisenstein norm(%4d, %4d) = %d\n", pt.x, pt.y, nrm)
    }

    fmt.println()
    fmt.println("=== Odin constraint kernel complete. ===")
}
