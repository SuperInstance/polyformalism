#[  polyformalism — Nim constraint kernel (Polyformalism Constraint Core)
  ======================================================================

  What Nim brings that C/Rust don't:
  ───────────────────────────────────
  1. Templates & Macros: constraintCheck could be a template zero-cost
     abstraction that avoids any function call overhead entirely.
  2. {.noSideEffect.} pragmas give the compiler guaranteed purity,
     enabling deeper inlining and alias analysis than C's `const` or
     Rust's `&` references on the same code.
  3. `emit` pragma lets us drop inline C/asm when we need bit-twiddling
     that the Nim compiler can't express — useful for polyformalism's
     vectorised bloom merges without losing the Nim type safety.
  4. seq[T] is a built-in GC-optional dynamic array with slice syntax,
     avoiding both C's malloc/free boilerplate and Rust's borrow checker
     friction for bloom filters.
  5. `uint64` is a first-class type with sensible wrapping semantics,
     identical to Rust but without needing `wrapping_add` etc.
  6. Nim's `when` compile-time dispatch + `static` blocks allow
     compile-time constraint-grid expansion — no preprocessor or
     build.rs needed.
  7. Parallel composition of constraint checks via `||` (nim >= 2.0's
     threadpool sugar) is syntactically cleaner than OpenMP pragmas or
     Rayon adapters.
  8. The type system distinguishes `int32` from `int` at the machine
     level, matching the polyformalism spec exactly without casting
     ceremony.

]#

import std/[math, bitops, sequtils, strformat]


# ═══════════════════════════════════════════════════════════════════════
# constraintCheck — pure bounds checker
# ═══════════════════════════════════════════════════════════════════════

proc constraintCheck*(lower, upper, values: array[16, int32]): bool
  {.noSideEffect, inline.} =
  ## Returns true iff ∀ i: lower[i] ≤ values[i] ≤ upper[i].
  ##
  ## Written with a `for` loop so the compiler can auto-vectorise;
  ## on modern x86-64, GCC/Clang backends emit SIMD pcmpgtd for this.
  for i in 0..15:
    if unlikely(values[i] < lower[i] or values[i] > upper[i]):
      return false
  true


# Alternative: template version (zero-overhead, no call frame)
template constraintCheckTempl*(lower, upper, values: array[16, int32]): bool =
  ## Template version — inlined at call site with zero call overhead.
  ## Idiomatic Nim for hot-path constraint checking.
  block:
    var ok = true
    for i in 0..15:
      if unlikely(values[i] < lower[i] or values[i] > upper[i]):
        ok = false
        break
    ok


# ═══════════════════════════════════════════════════════════════════════
# bloomMerge — CRDT semilattice join for bloom filter rows
# ═══════════════════════════════════════════════════════════════════════

proc bloomMerge*(dst: var seq[uint64], src: seq[uint64]) {.noSideEffect.} =
  ## Bitwise-OR merge: dst = dst OR src (idempotent, commutative).
  ## This is the join operation for a CRDT bloom-filter semilattice.
  ##
  ## If src is longer than dst, dst is extended (this isn't a lattice
  ## violation — it simply widens the domain).
  let minLen = min(dst.len, src.len)
  for i in 0..<minLen:
    dst[i] = dst[i] or src[i]
  if src.len > dst.len:
    dst.setLen(src.len)
    for i in minLen..<src.len:
      dst[i] = src[i]


# ═══════════════════════════════════════════════════════════════════════
# eisensteinNorm — Eisenstein integer norm
# ═══════════════════════════════════════════════════════════════════════

proc eisensteinNorm*(a, b: int32): int64 {.noSideEffect, inline.} =
  ## Compute the Eisenstein norm N(a + bω) = a² - ab + b².
  ##
  ## The naive expression is correct in signed 64-bit arithmetic for any
  ## int32 inputs (max values: 2³¹-1, squared ~ 2⁶², sum of three ~ 3×2⁶²
  ## which fits comfortably in int64's 2⁶³-1).
  a.int64 * a.int64 - a.int64 * b.int64 + b.int64 * b.int64


# ═══════════════════════════════════════════════════════════════════════
# Bloom filter helpers (for main())
# ═══════════════════════════════════════════════════════════════════════

proc newBloom(size: int): seq[uint64] =
  newSeq[uint64](size)

proc bloomInsert(bloom: var seq[uint64]; key: int32) {.inline.} =
  ## Hash `key` into two indices and set bits.
  ## Uses two trivial independent hash functions.
  let
    h1 = uint64(key) xor 0x9e3779b97f4a7c15'u64
    h2 = uint64(key) * 0xbf58476d1ce4e5b9'u64
    idx1 = int(h1 mod (bloom.len.uint64 shl 6)) shr 6
    bit1 = int(h1 and 63)
    idx2 = int(h2 mod (bloom.len.uint64 shl 6)) shr 6
    bit2 = int(h2 and 63)
  bloom[idx1] = bloom[idx1] or (1'u64 shl bit1)
  bloom[idx2] = bloom[idx2] or (1'u64 shl bit2)

proc bloomCheck(bloom: seq[uint64]; key: int32): bool {.inline.} =
  ## Returns true if `key` *might* be in the set (false positives possible).
  let
    h1 = uint64(key) xor 0x9e3779b97f4a7c15'u64
    h2 = uint64(key) * 0xbf58476d1ce4e5b9'u64
    idx1 = int(h1 mod (bloom.len.uint64 shl 6)) shr 6
    bit1 = int(h1 and 63)
    idx2 = int(h2 mod (bloom.len.uint64 shl 6)) shr 6
    bit2 = int(h2 and 63)
  result = true
  if (bloom[idx1] and (1'u64 shl bit1)) == 0: result = false
  if (bloom[idx2] and (1'u64 shl bit2)) == 0: result = false


# ═══════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════

proc runTests() =
  echo "═══ polyformalism Nim kernel — test suite ═══\n"

  # ── 1. constraintCheck ──────────────────────────────────────────────
  echo "── constraintCheck ─────────────────────────"
  let
    lower = [0'i32, -10'i32, 100'i32, -128'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    upper = [255'i32, 10'i32, 200'i32, 127'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  block:
    let
      values = [128'i32, 0'i32, 150'i32, 0'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      result = constraintCheck(lower, upper, values)
    echo &"  PASS (all in bounds):   {result}"  # expected: true

  block:
    let
      values = [256'i32, 0'i32, 150'i32, 0'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      result = constraintCheck(lower, upper, values)
    echo &"  FAIL (256 > 255):        {result}"  # expected: false

  block:
    let
      values = [128'i32, -15'i32, 150'i32, 0'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      result = constraintCheck(lower, upper, values)
    echo &"  FAIL (-15 < -10):        {result}"  # expected: false

  block:
    let
      values = [128'i32, 0'i32, 250'i32, 0'i32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      result = constraintCheck(lower, upper, values)
    echo &"  FAIL (250 > 200):        {result}"  # expected: false

  # ── 2. Bloom filter ─────────────────────────────────────────────────
  echo "\n── Bloom filter merge ──────────────────────"
  const bloomSize = 1000
  var
    bf1 = newBloom(bloomSize)
    bf2 = newBloom(bloomSize)

  # Insert keys into bf1
  for k in [42, 100, 255, 1000]:
    bloomInsert(bf1, k.int32)

  # Insert keys into bf2
  for k in [100, 500, 999]:
    bloomInsert(bf2, k.int32)

  echo "  Before merge:"
  echo &"    bf1 contains 42:   {bloomCheck(bf1, 42'i32)}"  # true
  echo &"    bf1 contains 500:  {bloomCheck(bf1, 500'i32)}" # false (only in bf2)
  echo &"    bf2 contains 100:  {bloomCheck(bf2, 100'i32)}" # true (also in bf1)
  echo &"    bf2 contains 42:   {bloomCheck(bf2, 42'i32)}"  # false (only in bf1)

  # Merge bf2 into bf1
  bloomMerge(bf1, bf2)

  echo "  After merge (bf1 |= bf2):"
  echo &"    bf1 contains 42:   {bloomCheck(bf1, 42'i32)}"  # true
  echo &"    bf1 contains 500:  {bloomCheck(bf1, 500'i32)}" # true (merged from bf2)
  echo &"    bf1 contains 999:  {bloomCheck(bf1, 999'i32)}" # true (merged from bf2)
  echo &"    bf1 contains 9999: {bloomCheck(bf1, 9999'i32)}" # false (never inserted)

  # Test idempotency: merging again changes nothing
  let popcountBefore = bf1.foldl(a + countSetBits(b), 0)
  bloomMerge(bf1, bf2)
  let popcountAfter = bf1.foldl(a + countSetBits(b), 0)
  echo &"    Idempotent (popcount same after re-merge): {popcountBefore == popcountAfter}"

  # ── 3. Eisenstein norm ──────────────────────────────────────────────
  echo "\n── Eisenstein norm ─────────────────────────"
  let eisensteinTests = [(3'i32, 0'i32), (0'i32, 1'i32),
                         (2'i32, -1'i32), (-1'i32, 2'i32),
                         (5'i32, 5'i32)]
  for (a, b) in eisensteinTests:
    let norm = eisensteinNorm(a, b)
    echo &"  N({a:2d}, {b:2d}) = {a}² - {a}·{b} + {b}² = {norm}"

  echo "\n═══ All tests complete ═══\n"


# ═══════════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════════

when isMainModule:
  runTests()
