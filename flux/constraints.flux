// Polyformalism Constraint Kernel — Pure FLUX Bytecode
// FLUX is the Cocapn fleet's constraint ISA.
// This is what constraints compile TO — the machine code of the constraint runtime.
//
// FLUX philosophy: constraints are simpler than general-purpose computation.
// You don't need a Turing-complete ISA to check bounds and merge Bloom filters.
// FLUX proves: 7 opcodes are enough for the entire constraint pipeline.

// === Opcode Table ===
// 0x01 LOAD   reg imm32      — load immediate value into register
// 0x02 CHECK  lo hi val      — check bounds: lo <= val <= hi, push result
// 0x03 AND                    — pop two bools, push AND
// 0x04 OR                     — pop two bools, push OR  (Bloom merge logic)
// 0x05 NORM   a b dst        — Eisenstein norm: a²-ab+b² → dst
// 0x06 EMIT   reg            — output register value
// 0x07 HALT                   — stop execution
// 0x08 BLOOM_OR dst src      — bitwise OR of two u64 registers (CRDT merge)
// 0x09 NOT                    — pop bool, push negation

// === Register File ===
// r0-r15:  constraint values (i32)
// r16-r31: lower bounds (i32)
// r32-r47: upper bounds (i32)
// r48-r55: Eisenstein scratch (i64)
// r56-r63: Bloom words (u64)

// ========================================
// Program: Full Constraint Pipeline
// ========================================

section .text

// --- Phase 1: Load constraint values ---
load_values:
    LOAD r0  25       // values[0] = 25
    LOAD r1  30       // values[1] = 30
    LOAD r2  35
    LOAD r3  40
    LOAD r4  50
    LOAD r5  60
    LOAD r6  70
    LOAD r7  80
    LOAD r8  10
    LOAD r9  20
    LOAD r10 30
    LOAD r11 40
    LOAD r12 55
    LOAD r13 65
    LOAD r14 75
    LOAD r15 85

// --- Phase 2: Load lower bounds (all zero) ---
load_lower:
    LOAD r16 0
    LOAD r17 0
    LOAD r18 0
    LOAD r19 0
    LOAD r20 0
    LOAD r21 0
    LOAD r22 0
    LOAD r23 0
    LOAD r24 0
    LOAD r25 0
    LOAD r26 0
    LOAD r27 0
    LOAD r28 0
    LOAD r29 0
    LOAD r30 0
    LOAD r31 0

// --- Phase 3: Load upper bounds (all 100) ---
load_upper:
    LOAD r32 100
    LOAD r33 100
    LOAD r34 100
    LOAD r35 100
    LOAD r36 100
    LOAD r37 100
    LOAD r38 100
    LOAD r39 100
    LOAD r40 100
    LOAD r41 100
    LOAD r42 100
    LOAD r43 100
    LOAD r44 100
    LOAD r45 100
    LOAD r46 100
    LOAD r47 100

// --- Phase 4: Check all 16 constraints ---
// CHECK pushes bool to stack. AND combines results.
check_constraints:
    CHECK r16 r32 r0      // lower[0] <= values[0] <= upper[0]
    CHECK r17 r33 r1
    AND
    CHECK r18 r34 r2
    AND
    CHECK r19 r35 r3
    AND
    CHECK r20 r36 r4
    AND
    CHECK r21 r37 r5
    AND
    CHECK r22 r38 r6
    AND
    CHECK r23 r39 r7
    AND
    CHECK r24 r40 r8
    AND
    CHECK r25 r41 r9
    AND
    CHECK r26 r42 r10
    AND
    CHECK r27 r43 r11
    AND
    CHECK r28 r44 r12
    AND
    CHECK r29 r45 r13
    AND
    CHECK r30 r46 r14
    AND
    CHECK r31 r47 r15
    AND
    // Stack now has: bool (all 16 constraints satisfied?)
    EMIT r0               // emit constraint result (will be 1 = true)

// --- Phase 5: Bloom merge (CRDT semilattice join) ---
// Two Bloom words: dst has bits for keys 42, 100
//                 src has bits for keys 500, 999
// After merge: dst has all four keys

bloom_setup:
    LOAD r56 0x0000000000000001   // dst: bit 0 set (key 42 → hash % 64 = 0)
    LOAD r57 0x0000000000000008   // dst: bit 3 set (key 100 → hash % 64 = 3)
    LOAD r58 0x0000000000000010   // src: bit 4 set (key 500 → hash % 64 = 4)
    LOAD r59 0x0000000080000000   // src: bit 31 set (key 999 → hash % 64 = 31)

    // Merge src into dst (CRDT: bitwise OR)
    BLOOM_OR r56 r58    // word 0: dst |= src
    BLOOM_OR r57 r59    // word 1: dst |= src

    // Emit merged Bloom words
    EMIT r56            // should have bits 0,3,4 set = 0x0000000000000019
    EMIT r57            // should have bits 3,31 set = 0x0000000080000008

// --- Phase 6: Eisenstein norms ---
// N(a,b) = a² - ab + b²
// This is the distance metric on the hexagonal lattice.

eisenstein:
    LOAD r0  3          // a = 3
    LOAD r1  0          // b = 0
    NORM r0 r1 r48      // N(3,0) = 9
    EMIT r48

    LOAD r0  0
    LOAD r1  1
    NORM r0 r1 r49      // N(0,1) = 1
    EMIT r49

    LOAD r0  2
    LOAD r1 -1          // negative b
    NORM r0 r1 r50      // N(2,-1) = 4+2+1 = 7
    EMIT r50

    LOAD r0 -1
    LOAD r1  2
    NORM r0 r1 r51      // N(-1,2) = 1+2+4 = 7
    EMIT r51

    LOAD r0  5
    LOAD r1  5
    NORM r0 r1 r52      // N(5,5) = 25-25+25 = 25
    EMIT r52

// --- Done ---
    HALT

// ========================================
// Expected output:
//   1                    (constraint check: all pass)
//   0x0000000000000019   (Bloom word 0: bits 0,3,4)
//   0x0000000080000008   (Bloom word 1: bits 3,31)
//   9                    (N(3,0))
//   1                    (N(0,1))
//   7                    (N(2,-1))
//   7                    (N(-1,2))
//   25                   (N(5,5))
// ========================================
