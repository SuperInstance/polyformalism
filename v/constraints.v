// Polyformalism Constraint Kernel — V Language
// =============================================
//
// V is a statically-typed systems language designed for simplicity,
// performance, and safety. Key distinctions vs C and Rust:
//
// - **No GC but memory-safe**: V uses an ownership model with a single
//   mutable reference rule (similar to Rust but simpler — no borrow
//   checker, no lifetimes). Memory is freed when variables go out of
//   scope or via `unsafe` manual management.
//
// - **Arrays are value types**: `[]u64{len: 1000}` allocates inline;
//   no Box/Vec distinction. Slicing returns a new array, not a view
//   (though references to arrays are possible).
//
// - **No macros or generics** (yet): V uses codegen and interfaces
//   instead. Function overloading is done via sum types or separate
//   functions as shown here.
//
// - **Built-in ORM, JSON, GUI**: V ships with batteries included, but
//   this kernel uses only the core language.
//
// - **Compiles to C, C++, JS, WASM**: Backend flexibility without
//   rewriting.
//
// - **Error handling** via `or {}` blocks (for functions returning
//   Option/Result) or multi-return. Panics via `panic()`.
//
// Compared to Rust: no borrow checker complexity, faster compile times
// (sub-second), but less memory safety guarantees at compile time.
// Compared to C: memory-safe by default (bounds checking in debug mode),
// no header files, simpler syntax.

module main

// --- 1. Constraint Check ---
// Returns true if all values satisfy: lower[i] <= values[i] <= upper[i]
// Arrays must all be the same length.
fn constraint_check(lower []int, upper []int, values []int) bool {
	// V's 'or' block handles Option/Result; for simple length checks
	// we compare explicitly since arrays are value types.
	if lower.len != upper.len || lower.len != values.len {
		return false
	}

	for i, val in values {
		if val < lower[i] || val > upper[i] {
			return false
		}
	}
	return true
}

// --- 2. Bloom Filter Merge (CRDT Semilattice Join) ---
// Bitwise OR merge: dst = dst OR src. Mutable reference via `mut`.
fn bloom_merge(mut dst []u64, src []u64) {
	// V's `mut dst []u64` gives read-write access.
	// We iterate using index to write back into dst.
	for i := 0; i < dst.len && i < src.len; i++ {
		dst[i] = dst[i] | src[i]
	}
}

// --- Bloom Filter Helpers (Module-Level — no nested functions in V) ---

// FNV-1a 64-bit hash of a string key
fn bloom_hash(key string) (int, int) {
	mut h := u64(14695981039346656037)
	for c in key.bytes() {
		h = h ^ u64(c)
		h = h * u64(1099511628211)
	}

	// Two hash positions from a single 64-bit hash
	pos1 := int(h % u64(64000))
	pos2 := int((h >> 32) % u64(64000))
	return pos1, pos2
}

// Insert a key into a Bloom filter by setting hash-derived bits
fn insert_bloom(mut filter []u64, key string) {
	pos1, pos2 := bloom_hash(key)

	word1 := pos1 / 64
	bit1 := u64(1) << (pos1 % 64)
	if word1 < filter.len {
		filter[word1] = filter[word1] | bit1
	}

	word2 := pos2 / 64
	bit2 := u64(1) << (pos2 % 64)
	if word2 < filter.len {
		filter[word2] = filter[word2] | bit2
	}
}

// Check if a key is possibly in the Bloom filter (false positives possible)
fn check_bloom(filter []u64, key string) bool {
	pos1, pos2 := bloom_hash(key)

	word1 := pos1 / 64
	bit1 := u64(1) << (pos1 % 64)
	word2 := pos2 / 64
	bit2 := u64(1) << (pos2 % 64)

	if word1 < filter.len && (filter[word1] & bit1) == 0 {
		return false
	}
	if word2 < filter.len && (filter[word2] & bit2) == 0 {
		return false
	}
	return true
}

// --- 3. Eisenstein Norm ---
// Compute: a² - a·b + b² (norm of Eisenstein integer a + bω)
fn eisenstein_norm(a int, b int) i64 {
	na := i64(a)
	nb := i64(b)
	// Using i64 throughout to avoid overflow for larger inputs
	return na * na - na * nb + nb * nb
}

// --- 4. Main — Tests and Demos ---
fn main() {
	// --- Constraint Check Tests ---
	lower := [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150]
	upper := [5, 15, 25, 35, 45, 55, 65, 75, 85, 95, 105, 115, 125, 135, 145, 155]
	values_pass := [3, 12, 21, 33, 42, 51, 63, 72, 81, 92, 101, 112, 123, 132, 141, 153]
	values_fail := [3, 12, 21, 33, 42, 51, 63, 72, 81, 92, 101, 112, 123, 132, 200, 153]

	println('=== Constraint Check ===')
	pass := constraint_check(lower, upper, values_pass)
	fail := constraint_check(lower, upper, values_fail)
	println('  All-within-bounds: ${pass} (expect: true)')
	println('  Value 200 > upper[14]=145: ${fail} (expect: false)')

	// --- Bloom Filter Tests ---
	println('\n=== Bloom Filter (1000 u64s, ~64000 bits) ===')

	mut filter_a := []u64{len: 1000}
	mut filter_b := []u64{len: 1000}

	// Insert keys into filter A
	keys_a := ['apple', 'banana', 'cherry', 'date', 'elderberry']
	for k in keys_a {
		insert_bloom(mut filter_a, k)
	}

	// Insert different keys into filter B
	keys_b := ['cherry', 'date', 'fig', 'grape', 'honeydew']
	for k in keys_b {
		insert_bloom(mut filter_b, k)
	}

	// Merge B into A (CRDT semilattice join)
	bloom_merge(mut filter_a, filter_b)

	// Check membership in merged filter
	check_keys := ['apple', 'banana', 'cherry', 'date', 'elderberry', 'fig', 'grape', 'honeydew']
	println('  Membership checks on merged filter:')
	for k in check_keys {
		present := check_bloom(filter_a, k)
		println('    "${k}": ${present} (expect: true)')
	}

	// Check a key NOT in the union
	absent := check_bloom(filter_a, 'mango')
	println('    "mango": ${absent} (expect: false — may false-positive)')

	// --- Eisenstein Norm Tests ---
	println('\n=== Eisenstein Norms ===')
	tests := [
		[3, 0],
		[0, 1],
		[2, -1],
		[-1, 2],
		[5, 5],
	]
	for t in tests {
		norm := eisenstein_norm(t[0], t[1])
		println('  N(${t[0]:3}, ${t[1]:3}) = ${norm:6}')
	}
}
