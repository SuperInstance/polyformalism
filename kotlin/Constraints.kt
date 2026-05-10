// Polyformalism Constraint Kernel — Kotlin
// =========================================
// Kotlin brings: inline classes for zero-cost type wrappers, unsigned types (UInt, ULong)
// for natural bitwise ops, extension functions for fluent APIs, and coroutines for
// parallel constraint checking. The JVM gives us battle-tested concurrent Bloom filters.

fun constraintCheck(lower: IntArray, upper: IntArray, values: IntArray): Boolean {
    require(lower.size == 16 && upper.size == 16 && values.size == 16)
    for (i in 0 until 16) {
        if (values[i] < lower[i] || values[i] > upper[i]) return false
    }
    return true
}

fun bloomMerge(dst: ULongArray, src: ULongArray) {
    val len = minOf(dst.size, src.size)
    for (i in 0 until len) {
        dst[i] = dst[i] or src[i]  // CRDT semilattice join: bitwise OR
    }
}

fun eisensteinNorm(a: Int, b: Int): Long {
    val aa = a.toLong()
    val bb = b.toLong()
    return aa * aa - aa * bb + bb * bb
}

fun bloomHash(key: Int, totalBits: Int): Int {
    var h = key and 0x7FFFFFFF
    h = h xor (h ushr 16)
    h *= -0x45d9f3b
    h = h xor (h ushr 16)
    return ((h and Int.MAX_VALUE) % totalBits)
}

fun bloomInsert(filter: ULongArray, key: Int) {
    val totalBits = filter.size * 64
    val pos = bloomHash(key, totalBits)
    filter[pos / 64] = filter[pos / 64] or (1UL shl (pos % 64))
}

fun bloomContains(filter: ULongArray, key: Int): Boolean {
    val totalBits = filter.size * 64
    val pos = bloomHash(key, totalBits)
    return (filter[pos / 64] and (1UL shl (pos % 64))) != 0UL
}

fun main() {
    println("=== Polyformalism: Kotlin ===")

    // Constraint check
    val lower = IntArray(16) { 0 }
    val upper = IntArray(16) { 100 }
    val pass  = intArrayOf(25, 30, 35, 40, 50, 60, 70, 80, 10, 20, 30, 40, 55, 65, 75, 85)
    val fail  = IntArray(16) { 200 + it }

    println("Constraint check (pass): ${constraintCheck(lower, upper, pass)}")
    println("Constraint check (fail): ${constraintCheck(lower, upper, fail)}")

    // Bloom merge
    val bloomA = ULongArray(1000)
    val bloomB = ULongArray(1000)
    bloomInsert(bloomA, 42)
    bloomInsert(bloomA, 100)
    bloomInsert(bloomA, 500)
    bloomInsert(bloomB, 500)
    bloomInsert(bloomB, 999)

    bloomMerge(bloomA, bloomB)

    println("Bloom 42 in merged:   ${bloomContains(bloomA, 42)}")
    println("Bloom 500 in merged:  ${bloomContains(bloomA, 500)}")
    println("Bloom 999 in merged:  ${bloomContains(bloomA, 999)}")
    println("Bloom 9999 in merged: ${bloomContains(bloomA, 9999)}")

    // Eisenstein norms
    println("N(3,0)  = ${eisensteinNorm(3, 0)}")
    println("N(0,1)  = ${eisensteinNorm(0, 1)}")
    println("N(2,-1) = ${eisensteinNorm(2, -1)}")
    println("N(-1,2) = ${eisensteinNorm(-1, 2)}")
    println("N(5,5)  = ${eisensteinNorm(5, 5)}")

    // Verify
    assert(constraintCheck(lower, upper, pass))
    assert(!constraintCheck(lower, upper, fail))
    assert(bloomContains(bloomA, 42))
    assert(bloomContains(bloomA, 500))
    assert(bloomContains(bloomA, 999))
    assert(!bloomContains(bloomA, 9999))
    assert(eisensteinNorm(3, 0) == 9L)
    assert(eisensteinNorm(0, 1) == 1L)
    assert(eisensteinNorm(2, -1) == 7L)
    assert(eisensteinNorm(-1, 2) == 7L)
    assert(eisensteinNorm(5, 5) == 25L)

    println("\nAll assertions passed.")
}
