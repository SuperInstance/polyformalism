# Polyformalism — Same Constraint Kernel, Every Language

The same three functions implemented across 10+ programming languages to reveal what's essential versus what's accidental about expressing constraints.

## The Three Functions

Every implementation provides the same API:

1. **`constraint_check(lower, upper, values) → bool`** — Are all 16 values within their bounds? (Bounded lattice membership)
2. **`bloom_merge(dst, src) → merged`** — Bitwise OR merge. Commutative, associative, idempotent. (Join semilattice)
3. **`eisenstein_norm(a, b) → norm`** — Eisenstein integer norm: a²−ab+b². Hexagonal lattice distance. (Normed ring)

## Languages

| Directory | Language | Lines | Key Insight |
|-----------|----------|-------|-------------|
| `flux/` | FLUX (our ISA) | 120 (VM) | 9 opcodes sufficient for entire pipeline |
| `odin/` | Odin | 227 | SIMD as language feature, not library |
| `c3/` | C3 | 110 | C fixed, not replaced |
| `nim/` | Nim | 219 | Purity pragmas, zero-cost templates |
| `v/` | V | 184 | Simplicity without sacrifice |
| `jai/` | Jai | 297 | Data-oriented by default |
| `r/` | R | 198 | APL inheritance — vectorized single expressions |
| `matlab/` | MATLAB | 187 | `bitor()` built-in, array-native |

Also see `constraint-theory-core` (Rust, 184 tests) and `crdt-bench` (Fortran, C, Zig, Go, CUDA) in the SuperInstance org.

## Running

### FLUX VM (Python)
```bash
python3 flux/vm.py
```

### V
```bash
v run v/constraints.v
```

### Nim
```bash
nim c -r nim/constraints.nim
```

### R
```r
source("r/constraints.R")
```

### MATLAB
```matlab
constraints
```

## The Test Vectors

All implementations verify the same expected outputs:
- Constraint [25..85] in [0..100]: **PASS**
- Constraint [200..215] in [0..100]: **FAIL**
- Bloom merge preserves membership of 42, 100, 500, 999
- N(3,0)=9, N(0,1)=1, N(2,-1)=7, N(-1,2)=7, N(5,5)=25

## Why

Because the same math in different languages reveals what's essential about constraint expression. Fortran's `dst = MAX(dst, src)` is one line because whole-array operations are primitives. FLUX's 9 opcodes prove constraints don't need general-purpose computation. R/MATLAB prove the check is a single expression.

**The language that makes your domain primitive wins.**

## License

Apache-2.0
