#!/usr/bin/env python3
"""Polyformalism Constraint Kernel — Python

Python is the lingua franca. Every data scientist, ML engineer, and fleet agent speaks it.
The constraint kernel in Python uses numpy for vectorized ops — the same "implicit loop"
as R/MATLAB. numpy's bitwise_or is a single C call that does the whole array at once.

What Python reveals: the constraint check is STILL one expression.
numpy makes Python an array language too.
"""

import numpy as np
from typing import List

def constraint_check(lower: np.ndarray, upper: np.ndarray, values: np.ndarray) -> bool:
    """Check if all values are within bounds. Single expression."""
    return bool(np.all((values >= lower) & (values <= upper)))

def bloom_merge(dst: np.ndarray, src: np.ndarray) -> None:
    """Bitwise OR merge in-place. CRDT semilattice join."""
    np.bitwise_or(dst, src, out=dst)

def eisenstein_norm(a: int, b: int) -> int:
    """Eisenstein integer norm: a² - ab + b²"""
    return a * a - a * b + b * b

def bloom_hash(key: int, total_bits: int) -> int:
    h = abs(key) & 0x7FFFFFFF
    h ^= h >> 16
    h = (h * 0x45d9f3b) & 0xFFFFFFFF
    h ^= h >> 16
    return h % total_bits

def bloom_insert(filter_arr: np.ndarray, key: int) -> None:
    total_bits = len(filter_arr) * 64
    pos = bloom_hash(key, total_bits)
    filter_arr[pos // 64] |= (1 << (pos % 64))

def bloom_contains(filter_arr: np.ndarray, key: int) -> bool:
    total_bits = len(filter_arr) * 64
    pos = bloom_hash(key, total_bits)
    return bool(filter_arr[pos // 64] & (1 << (pos % 64)))

def main():
    print("=== Polyformalism: Python (numpy) ===")

    # Constraint check
    lower = np.zeros(16, dtype=np.int32)
    upper = np.full(16, 100, dtype=np.int32)
    pass_vals = np.array([25, 30, 35, 40, 50, 60, 70, 80, 10, 20, 30, 40, 55, 65, 75, 85], dtype=np.int32)
    fail_vals = np.arange(200, 216, dtype=np.int32)

    print(f"Constraint check (pass): {constraint_check(lower, upper, pass_vals)}")
    print(f"Constraint check (fail): {constraint_check(lower, upper, fail_vals)}")

    # Bloom merge
    bloom_a = np.zeros(1000, dtype=np.uint64)
    bloom_b = np.zeros(1000, dtype=np.uint64)
    for k in [42, 100, 500]:
        bloom_insert(bloom_a, k)
    for k in [500, 999]:
        bloom_insert(bloom_b, k)

    bloom_merge(bloom_a, bloom_b)

    print(f"Bloom 42 in merged:   {bloom_contains(bloom_a, 42)}")
    print(f"Bloom 500 in merged:  {bloom_contains(bloom_a, 500)}")
    print(f"Bloom 999 in merged:  {bloom_contains(bloom_a, 999)}")
    print(f"Bloom 9999 in merged: {bloom_contains(bloom_a, 9999)}")

    # Eisenstein norms
    test_cases = [(3, 0), (0, 1), (2, -1), (-1, 2), (5, 5)]
    for a, b in test_cases:
        print(f"N({a},{b}) = {eisenstein_norm(a, b)}")

    # Verify
    assert constraint_check(lower, upper, pass_vals)
    assert not constraint_check(lower, upper, fail_vals)
    assert bloom_contains(bloom_a, 42)
    assert bloom_contains(bloom_a, 500)
    assert bloom_contains(bloom_a, 999)
    assert not bloom_contains(bloom_a, 9999)
    assert eisenstein_norm(3, 0) == 9
    assert eisenstein_norm(0, 1) == 1
    assert eisenstein_norm(2, -1) == 7
    assert eisenstein_norm(-1, 2) == 7
    assert eisenstein_norm(5, 5) == 25

    print("\nAll assertions passed.")

if __name__ == "__main__":
    main()
