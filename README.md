# Polyformalism — Same Constraint Kernel, Every Language

The same three functions implemented across 13+ programming languages to reveal what's essential versus what's accidental about expressing constraints.

## The Three Functions

Every implementation provides the same API:

1. **`constraint_check(lower, upper, values) → bool`** — Are all 16 values within their bounds? (Bounded lattice membership)
2. **`bloom_merge(dst, src)`** — Bitwise OR merge. Commutative, associative, idempotent. (Join semilattice)
3. **`eisenstein_norm(a, b) → int`** — Eisenstein integer norm: a²−ab+b². Hexagonal lattice distance. (Normed ring)

## Languages (13 implementations)

| Dir | Language | Lines | Key Insight |
|-----|----------|-------|-------------|
| `flux/` | **FLUX** (our ISA) | 189 asm + 172 VM | 9 opcodes sufficient for entire pipeline |
| `odin/` | **Odin** | 227 | SIMD as language feature, `#simd[16]i32` |
| `c3/` | **C3** | 118 | C fixed: foreach, slices, defer |
| `nim/` | **Nim** | 219 | `{.noSideEffect.}` pragmas, templates |
| `v/` | **V** | 184 | Value arrays, no GC, simplicity |
| `jai/` | **Jai** | 297 | Data-oriented by default |
| `zig/` | **Zig** | 264 | `@Vector` SIMD, comptime |
| `r/` | **R** | 198 | APL inheritance — single expressions |
| `matlab/` | **MATLAB** | 187 | `bitor()` built-in |
| `kotlin/` | **Kotlin** | 97 | Unsigned types, JVM concurrent |
| `haskell/` | **Haskell** | 105 | Lazy short-circuit, `zipWith` |
| `swift/` | **Swift** | 96 | `inout` mutation, SIMD module |
| `python/` | **Python** | 92 | numpy vectorization, lingua franca |

**Total: 3,322 lines across 21 files.**

## Running

```bash
# FLUX VM (Python) — all assertions pass
python3 flux/vm.py

# Python (numpy)
python3 python/constraints.py

# V
v run v/constraints.v

# Nim
nim c -r nim/constraints.nim

# Kotlin
kotlinc kotlin/Constraints.kt -include-runtime -d constraints.jar && java -jar constraints.jar

# Haskell
ghc haskell/Constraints.hs && ./Constraints

# Swift
swift swift/Constraints.swift

# R
Rscript r/constraints.R

# MATLAB
matlab -batch "run('matlab/constraints.m')"
```

## The Test Vectors

All implementations verify the same expected outputs:
- `[25,30,35,40,50,60,70,80,10,20,30,40,55,65,75,85]` in `[0..100]`: **PASS**
- `[200..215]` in `[0..100]`: **FAIL**
- Bloom merge preserves membership of 42, 100, 500, 999
- N(3,0)=9, N(0,1)=1, N(2,−1)=7, N(−1,2)=7, N(5,5)=25

## Why

Because the same math in different languages reveals what's essential. The constraint check is a single expression in array languages, a 9-opcode program in FLUX, and a SIMD comparison in Odin. The math doesn't change — only the expression does.

**The language that makes your domain primitive wins.**

## License

Apache-2.0
