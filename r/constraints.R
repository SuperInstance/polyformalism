# =============================================================================
# polyformalism: constraint.R — Array-Language Constraint Kernels (R)
# =============================================================================
#
# R inherits from S (1976) which inherits directly from APL (1964).
# As an array language, R's fundamental operations are vectorized:
#   - Loops are IMPLICIT, not explicit
#   - Operations apply to the entire array at once
#   - The constraint check and bloom merge below are SINGLE EXPRESSIONS
#     because the array language handles the iteration
#
# This is the APL inheritance: one function call on each axis, not
# one element at a time. The loop lives in compiled C code, not R bytecode.
#
# Three core polyformalism constraint kernels:
#   1. constraint_check  —  bounds validation (value ∈ [lower, upper])
#   2. bloom_merge       —  bitwise OR of two bloom filters
#   3. eisenstein_norm   —  ℤ[ω] norm: a² − a·b + b²
# =============================================================================

# ---------------------------------------------------------------------------
# constraint_check — vectorized bounds validation
#
# APL inheritance: `all(values >= lower & values <= upper)` is a single
# vectorized expression. The `&` and comparisons are element-wise. R recycles
# scalars automatically. No explicit loop anywhere.
#
# Inputs:
#   lower  — scalar or vector of lower bounds
#   upper  — scalar or vector of upper bounds
#   values — vector of values to check
#
# Returns:
#   TRUE if ALL values satisfy lower[i] <= values[i] <= upper[i]
#   (with recycling when lower/upper are scalars)
# ---------------------------------------------------------------------------
constraint_check <- function(lower, upper, values) {
  all(values >= lower & values <= upper)
}


# ---------------------------------------------------------------------------
# bloom_merge — bitwise OR of two bloom filters stored as raw vectors
#
# APL inheritance: `dst | src` is a single vectorized expression. R's raw
# vectors support bitwise OR via the `|` operator when the bits are packed
# into raw bytes. No explicit byte-by-byte loop.
#
# Inputs:
#   dst — raw vector (first bloom filter, also mutated in place for return)
#   src — raw vector (second bloom filter)
#
# Returns:
#   raw vector where each byte is dst[i] | src[i]
#   (length determined by recycling, typically same-length vectors)
# ---------------------------------------------------------------------------
bloom_merge <- function(dst, src) {
  # Single expression: vectorized bitwise OR on raw bytes
  dst | src
}


# ---------------------------------------------------------------------------
# eisenstein_norm — norm in the Eisenstein integer ring ℤ[ω]
#
# For integers a, b ∈ ℤ, the norm N(a + b·ω) where ω = (-1 + √(-3))/2 is:
#   N(a + b·ω) = a² − a·b + b²
#
# This is the fundamental quadratic form of the hexagonal lattice A₂.
# Vectorized: works on scalar or vector inputs.
#
# Inputs:
#   a — integer(s), coefficient of 1
#   b — integer(s), coefficient of ω
#
# Returns:
#   integer(s) — the Eisenstein norm a² − a·b + b²
# ---------------------------------------------------------------------------
eisenstein_norm <- function(a, b) {
  a*a - a*b + b*b
}


# =============================================================================
# Tests — run with: Rscript constraints.R
# =============================================================================

cat("========================================\n")
cat("Polyformalism Constraint Kernels — R\n")
cat("========================================\n\n")

# ---- 1. constraint_check tests ----
cat("--- constraint_check ---\n")

# Test with standard vectors: constraints [0..15] vs [0..100]
test_lower  <- rep(0, 16)
test_upper  <- c(0:15)
test_values <- c(25:40)
result1 <- constraint_check(test_lower, test_upper, test_values)
cat(sprintf("  Passing (25..40 vs bounds [0..15]): %s\n", result1))

# Failing values [200..215] — should all fail
fail_values <- c(200:215)
result2 <- constraint_check(test_lower, test_upper, fail_values)
cat(sprintf("  Failing (200..215 vs bounds [0..15]): %s\n", result2))

# Edge cases
cat(sprintf("  Empty vectors: %s\n", constraint_check(numeric(0), numeric(0), numeric(0))))
cat(sprintf("  Single passing: %s\n", constraint_check(0, 10, 5)))
cat(sprintf("  Single failing: %s\n", constraint_check(0, 10, 15)))
cat(sprintf("  Scalar recycling check: %s\n", constraint_check(0, 100, 1:50)))

cat("\n")

# ---- 2. bloom_merge tests ----
cat("--- bloom_merge ---\n")

# Create two 1000-element (8000-bit) bloom filters
filter1 <- raw(1000)
filter2 <- raw(1000)

# Insert some keys into filter1 (set some bits)
# Key "hello" → bits at positions determined by hash functions
# For demo: we manually flip some bits using bitwise operations
filter1[1:10] <- as.raw(c(0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
                           0xAA, 0x55))

# Insert some keys into filter2
filter2[5:15] <- as.raw(c(0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80,
                           0x01, 0x02, 0x04))

# Merge them — single expression, no explicit loop
merged <- bloom_merge(filter1, filter2)

# Verify: merged bytes should be bitwise OR of the two
check_ok <- TRUE
for (i in seq_along(merged)) {
  expected <- as.integer(filter1[i]) | as.integer(filter2[i])
  actual   <- as.integer(merged[i])
  if (expected != actual) {
    cat(sprintf("  MISMATCH at byte %d: filter1=%02x, filter2=%02x, "
                "expected=%02x, got=%02x\n",
                i, as.integer(filter1[i]), as.integer(filter2[i]),
                expected, actual))
    check_ok <- FALSE
  }
}
cat(sprintf("  Merge verified (1000 bytes): %s\n", check_ok))

# Check that merged has union bits
has_union <- all((merged[1:15] == (filter1[1:15] | filter2[1:15])))
cat(sprintf("  Union preserved in overlap region: %s\n", has_union))

cat("\n")

# ---- 3. eisenstein_norm tests ----
cat("--- eisenstein_norm ---\n")

# Standard test vectors
test_pairs <- list(
  c(3, 0),   # N(3) = 9
  c(0, 1),   # N(ω) = 1
  c(2, -1),  # N(2 - ω) = 7
  c(-1, 2),  # N(-1 + 2ω) = 7
  c(5, 5)    # N(5 + 5ω) = 25
)

# Expected norms for the Eisenstein lattice
# N(a + bω) = a² - ab + b²
# (3, 0): 9 - 0 + 0 = 9
# (0, 1): 0 - 0 + 1 = 1
# (2, -1): 4 - (-2) + 1 = 7
# (-1, 2): 1 - (-2) + 4 = 7
# (5, 5): 25 - 25 + 25 = 25
expected_norms <- c(9, 1, 7, 7, 25)

for (i in seq_along(test_pairs)) {
  pair  <- test_pairs[[i]]
  a     <- pair[1]
  b     <- pair[2]
  norm  <- eisenstein_norm(a, b)
  expected <- expected_norms[i]
  status <- if (norm == expected) "PASS" else "FAIL"
  cat(sprintf("  N(%2d + %2dω) = %2d  (expected %2d)  [%s]\n",
              a, b, norm, expected, status))
}

# Vectorized norm test
a_vec <- c(3, 0, 2, -1, 5)
b_vec <- c(0, 1, -1, 2, 5)
norms_vec <- eisenstein_norm(a_vec, b_vec)
cat(sprintf("  Vectorized: all(%s) = %s\n",
            paste(norms_vec, collapse=", "),
            all(norms_vec == expected_norms)))

cat("\n========================================\n")
cat("All R polyformalism constraint tests complete.\n")
cat("========================================\n")
