# Polyformalism — Same Constraint Kernel, Every Language

The same three functions implemented across 13 programming languages, tested with 2,100 differential test vectors, benchmarked on real hardware, and simulated with fleet-scale CRDT and cascade models.

**The math doesn't change. Only the expression does.**

## The Three Functions

1. **`constraint_check(lower, upper, values) → bool`** — Bounded lattice membership
2. **`bloom_merge(dst, src)`** — Join semilattice (bitwise OR, CRDT-compatible)
3. **`eisenstein_norm(a, b) → int`** — Hexagonal lattice distance: a²−ab+b²

## Languages (13)

| Dir | Language | Lines | Key Insight |
|-----|----------|-------|-------------|
| `c/` | **C + AVX2** | 183 | 3.85B ops/s, 116 GB/s Bloom merge, baseline |
| `zig/` | **Zig** | 149 | @Vector SIMD, comptime, aggressive optimizer |
| `nim/` | **Nim** | 219 | Purity pragmas, compiles to C, idempotency test |
| `python/` | **Python** | 92 | numpy vectorization, 2100/2100 differential pass |
| `flux/` | **FLUX (our ISA)** | 361 | 9 opcodes, 172-line VM, proves minimal ISA |
| `odin/` | **Odin** | 227 | SIMD as language feature |
| `c3/` | **C3** | 118 | C fixed: foreach, slices, defer |
| `v/` | **V** | 184 | Value arrays, no GC |
| `jai/` | **Jai** | 297 | Data-oriented, no hidden allocs |
| `r/` | **R** | 198 | APL inheritance, single-expression check |
| `matlab/` | **MATLAB** | 187 | `bitor()` built-in |
| `kotlin/` | **Kotlin** | 97 | Unsigned types, JVM |
| `haskell/` | **Haskell** | 105 | Lazy short-circuit, zipWith |
| `swift/` | **Swift** | 96 | inout mutation, SIMD module |

## Verified on Hardware

**5 compiled and tested** (Ryzen AI 9 HX 370, Zen 5):
- ✅ C (gcc -O2 -mavx2) — all pass, benchmarks run
- ✅ Zig (0.13, ReleaseSafe) — all pass
- ✅ Nim (2.2.10, -d:release) — all pass + idempotency
- ✅ Python (3.10 + numpy 2.2) — all pass
- ✅ FLUX VM (Python) — all pass

**2,100 differential test vectors**: zero mismatches between C and Python.

## Key Experimental Results

| Finding | Number |
|---------|--------|
| SIMD speedup (AVX2) | 3.7-6.9x |
| Bloom merge peak bandwidth | 116 GB/s |
| CRDT convergence (20 nodes) | 50 ticks to 100% |
| Byzantine resistance | Canary propagates unaffected |
| Eisenstein repair advantage | 26% fewer violations |
| Precision safe range | INT16 coordinates, INT32 norms |
| Cross-language correctness | 2100/2100 pass |

See [EXPERIMENTS.md](EXPERIMENTS.md) for full hardware results.
See [RESULTS.md](RESULTS.md) for language comparison.
See [SYNTHESIS.md](SYNTHESIS.md) for philosophical analysis.

## Simulations

- `simulations/fleet_crdt_sim.py` — 20-node Bloom CRDT gossip convergence + cascade
- `simulations/eisenstein_explorer.py` — Lattice generation, D6 symmetry, precision loss, packing density

## Quick Start

```bash
# Run Python (fastest to verify)
python3 python/constraints.py

# Run FLUX VM (our custom ISA)
python3 flux/vm.py

# Run benchmark suite
python3 run_all.py

# Compile and run C reference (requires gcc + AVX2)
cd c && gcc -O2 -mavx2 -o constraints_c constraints.c && ./constraints_c

# Compile and run Zig (requires zig)
cd zig && zig build-exe constraints.zig -OReleaseSafe && ./constraints

# Run differential tests (C → Python)
cd experiments && gcc -O2 -o exp4_differential exp4_differential.c
./exp4_differential > results/diff_vectors.txt
python3 exp4_verify_python.py
```

## Why

Because the same math in different languages reveals what's essential. R and MATLAB express the constraint check in one line. FLUX does it in 9 opcodes. C needs 200 characters of AVX2 intrinsics. The math is identical.

**The language that makes your domain primitive wins.**

## License

Apache-2.0
