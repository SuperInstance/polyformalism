/**
 * polyformalism/constraints.jai — Constraint Kernel
 * ==================================================
 *
 * A polyformalism constraint kernel demonstrating three core operations
 * from the Cocapn fleet constraint-theory framework, ported to Jai.
 *
 * ## Functions
 *
 *   constraint_check :: (lower, upper, values) → bool
 *     Boundedness predicate — verifies every value lies within [lowerᵢ, upperᵢ].
 *
 *   bloom_merge :: (dst, src) → ∅
 *     CRDT semilattice merge — bitwise OR over two Bloom filter vectors.
 *     Commutative, associative, idempotent. Meets monotonic join semantics.
 *
 *   eisenstein_norm :: (a, b) → s64
 *     Eisenstein integer norm: N(a + bω) = a² − ab + b².
 *     Key invariant: multiplication is subadditive under this norm.
 *
 * ==========================================================================
 *
 * Jai's Data-Oriented Design Philosophy
 * --------------------------------------
 * Jai is Jonathan Blow's in-development language for high-performance game
 * development. Its design revolves around these principles:
 *
 * 1. **Data orientation over abstraction.**
 *    The language encourages you to think about data layout, access patterns,
 *    and cache lines before thinking about inheritance or polymorphism.
 *    There are no classes, no virtual methods, no vtables — you compose data
 *    as structs and operate on it with procedures.
 *
 * 2. **Explicit memory and control.**
 *    No garbage collector, no hidden allocations, no implicit copies you
 *    can't see. Arrays are passed by pointer + count (slices); the
 *    programmer chooses where and how memory lives.
 *
 * 3. **Compile-time metaprogramming via #run.**
 *    Code can be executed at compile time to generate data tables,
 *    unroll loops, or specialize polymorphic procedures — without a
 *    separate macro language. This replaces templates, generics, and
 *    codegen in one unified mechanism.
 *
 * 4. **"Simple things are simple; hard things are possible."**
 *    The syntax is minimal: `:=` for local declarations, `::` for
 *    top-level constants and type definitions, `#import` for modules,
 *    `if` without parentheses, braces for blocks. You write what you mean.
 *
 * 5. **No hidden control flow.**
 *    No operator overloading that calls unknown code, no implicit
 *    conversions that run constructors, no RAII destructor cascade.
 *    Every cycle is accounted for in the source text.
 *
 * 6. **Containers are raw arrays or slices.**
 *    There is no std::vector or std::map with hidden heap behavior.
 *    You build your data structures from fixed-size arrays, dynamic
 *    arrays (which are just a struct wrapping a pointer + count + cap),
 *    or hash tables built on top of those.
 *
 * 7. **Manual hot-reload support baked in.**
 *    The compiler links a "list of things to update" into the binary so
 *    game code can be recompiled and swapped at runtime without stopping
 *    the simulation. This shaped the type system — no globals that lose
 *    their address, no function pointers that dangle.
 *
 * 8. **The module system is flat, fast, and file-based.**
 *    #import "foo" loads foo.jai. There is no build system — the compiler
 *    is the build system. It sees every file as a compilation unit and
 *    caches them in a .build directory.
 *
 * In practice, this means Jai code tends to look like a series of flat
 * procedure definitions operating on plain structs and arrays — which
 * maps naturally to the constraint kernel pattern below.
 * ==========================================================================
 */

/* ------------------------------------------------------------------ */
/*  1. CONSTRAINT CHECK — Boundedness Predicate                       */
/* ------------------------------------------------------------------ */

constraint_check :: (lower: [16]s32, upper: [16]s32, values: [16]s32) -> bool
{
    for values {
        index := it_index;
        if it < lower[index] return false;
        if it > upper[index] return false;
    }
    return true;
}

/* ------------------------------------------------------------------ */
/*  2. BLOOM FILTER MERGE — CRDT Semilattice Join                     */
/* ------------------------------------------------------------------ */

bloom_merge :: (dst: []u64, src: []u64)
{
    // dst and src must be same length (caller's responsibility).
    // This is an idempotent, commutative, associative merge — a
    // join in the semilattice of Bloom-filter vectors.
    for 0 .. dst.count - 1 {
        dst[it] |= src[it];
    }
}

/* ------------------------------------------------------------------ */
/*  3. EISENSTEIN NORM — Quadratic Integer Form                       */
/* ------------------------------------------------------------------ */

eisenstein_norm :: (a: s32, b: s32) -> s64
{
    // N(a + bω) = a² − ab + b²   (ω = (-1 + i√3)/2)
    // Compute in s64 to avoid overflow: max input ~|46340|.
    aa := cast(s64)a * cast(s64)a;
    ab := cast(s64)a * cast(s64)b;
    bb := cast(s64)b * cast(s64)b;
    return aa - ab + bb;
}

/* ------------------------------------------------------------------ */
/*  4. TEST HARNESS                                                   */
/* ------------------------------------------------------------------ */

#run main_with_print;   // Run main at compile time, print results to console

main_with_print :: ()
{
    // ──────────────────────────────────────────────
    // 4a. Constraint check — passing case
    lower_pass: [16]s32 = #run // all zeros
    {
        result: [16]s32;
        for result result[it_index] = 0;
        return result;
    };
    upper_pass: [16]s32 = #run // all 100
    {
        result: [16]s32;
        for result result[it_index] = 100;
        return result;
    };
    values_pass: [16]s32 = #run
    {
        result: [16]s32;
        for result result[it_index] = cast(s32)(it_index * 7);
        return result;
    };
    // Values: 0, 7, 14, ..., 105 → indices 0-14 in [0,100], index 15 = 105 > 100

    // ──────────────────────────────────────────────
    // 4b. Constraint check — failing case
    lower_fail: [16]s32 = #run
    {
        result: [16]s32;
        for result result[it_index] = 0;
        return result;
    };
    upper_fail: [16]s32 = #run
    {
        result: [16]s32;
        for result result[it_index] = 100;
        return result;
    };
    values_fail: [16]s32 = #run
    {
        result: [16]s32;
        for result result[it_index] = 25 + cast(s32)it_index;
        return result;
    };
    // Values: 25..40 → all in [0,100] → should pass

    // We need a true failure. Override one value.
    values_fail_override: [16]s32 = #run
    {
        result: [16]s32;
        for result result[it_index] = 25 + cast(s32)it_index;
        result[15] = 200;  // out of bounds
        return result;
    };

    print("=== Constraint Kernel Tests ===\n");
    print("---\n");

    // 4a: Constraint check — values 0..105 in [0,100]; index 15 fails
    result_a := constraint_check(lower_pass, upper_pass, values_pass);
    print("[4a] constraint_check([0..105], bounds=[0,100]) → %\n", result_a);
    // Expected: false (105 > 100)

    // 4b: Constraint check — range [25..40] in [0,100] should pass
    result_b := constraint_check(lower_fail, upper_fail, values_fail);
    print("[4b] constraint_check([25..40], bounds=[0,100]) → %\n", result_b);
    // Expected: true

    // 4c: Constraint check — override last to 200
    result_c := constraint_check(lower_fail, upper_fail, values_fail_override);
    print("[4c] constraint_check([25..40,200], bounds=[0,100]) → %\n", result_c);
    // Expected: false

    // ──────────────────────────────────────────────
    // 4d: Bloom filter merge (1000 u64s)
    BLOOM_SIZE :: 1000;
    bloom_a: [BLOOM_SIZE]u64;
    bloom_b: [BLOOM_SIZE]u64;

    // Populate bloom_a: every element at even index
    for 0 .. BLOOM_SIZE - 1 {
        if it & 1 == 0 {
            bloom_a[it] = 0xAAAAAAAAAAAAAAAA;
        } else {
            bloom_a[it] = 0;
        }
    }

    // Populate bloom_b: every element at odd index
    for 0 .. BLOOM_SIZE - 1 {
        if it & 1 == 1 {
            bloom_b[it] = 0xBBBBBBBBBBBBBBBB;
        }
    }

    // Verify pre-merge: bloom_a odd slots are zero, bloom_b even slots are zero
    verify_a_odd_is_zero := true;
    for 0 .. BLOOM_SIZE - 1 {
        if it & 1 == 1 {
            if bloom_a[it] != 0 {
                verify_a_odd_is_zero = false;
                break;
            }
        }
    }

    verify_b_even_is_zero := true;
    for 0 .. BLOOM_SIZE - 1 {
        if it & 1 == 0 {
            if bloom_b[it] != 0 {
                verify_b_even_is_zero = false;
                break;
            }
        }
    }

    print("[4d.1] Pre-merge — bloom_a odd slots zero: %\n", verify_a_odd_is_zero);
    print("[4d.2] Pre-merge — bloom_b even slots zero: %\n", verify_b_even_is_zero);

    // Merge: bloom_a |= bloom_b
    bloom_merge(bloom_a, bloom_b);

    // Post-merge: every slot should be non-zero
    all_nonzero := true;
    for bloom_a {
        if it == 0 {
            all_nonzero = false;
            break;
        }
    }

    // Verify idempotency: merging again should not change anything
    bloom_snapshot: [BLOOM_SIZE]u64;
    for 0 .. BLOOM_SIZE - 1 bloom_snapshot[it] = bloom_a[it];
    bloom_merge(bloom_a, bloom_b);
    idempotent := true;
    for 0 .. BLOOM_SIZE - 1 {
        if bloom_a[it] != bloom_snapshot[it] {
            idempotent = false;
            break;
        }
    }

    print("[4d.3] Post-merge — all slots non-zero: %\n", all_nonzero);
    print("[4d.4] Idempotency check (merge again, no change): %\n", idempotent);

    // ──────────────────────────────────────────────
    // 4e: Eisenstein norms
    en1 := eisenstein_norm(3,  0);   // 9 + 0 + 0 = 9
    en2 := eisenstein_norm(0,  1);   // 0 - 0 + 1 = 1
    en3 := eisenstein_norm(2, -1);   // 4 - (-2) + 1 = 7
    en4 := eisenstein_norm(-1, 2);   // 1 - (-2) + 4 = 7
    en5 := eisenstein_norm(5,  5);   // 25 - 25 + 25 = 25

    print("[4e.1] eisenstein_norm(3,  0) = %  (expected 9)\n", en1);
    print("[4e.2] eisenstein_norm(0,  1) = %  (expected 1)\n", en2);
    print("[4e.3] eisenstein_norm(2, -1) = %  (expected 7)\n", en3);
    print("[4e.4] eisenstein_norm(-1, 2) = %  (expected 7)\n", en4);
    print("[4e.5] eisenstein_norm(5,  5) = %  (expected 25)\n", en5);

    print("---\n");
    print("All tests complete.\n");
}

/* ------------------------------------------------------------------ */
/*  5. RUNTIME ENTRY POINT                                            */
/* ------------------------------------------------------------------ */

main :: ()
{
    main_with_print();
}
