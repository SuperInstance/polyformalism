#!/usr/bin/env python3
"""
Experiment 4: Cross-Language Differential Testing
Verify Python/numpy and FLUX VM against C ground truth.
"""
import numpy as np
import sys

def constraint_check(lower, upper, values):
    return int(np.all((values >= lower) & (values <= upper)))

def eisenstein_norm(a, b):
    return a * a - a * b + b * b

def main():
    vec_file = "/tmp/polyformalism-repo/experiments/results/diff_vectors.txt"

    cc_tests = 0; cc_pass = 0
    en_tests = 0; en_pass = 0
    bm_tests = 0; bm_pass = 0

    section = None
    with open(vec_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith('['):
                section = line
                continue

            parts = line.split()
            if section == '[CONSTRAINT_CHECK]' and parts[0] == 'CC':
                lower = np.array([int(x) for x in parts[1:17]], dtype=np.int32)
                upper = np.array([int(x) for x in parts[17:33]], dtype=np.int32)
                values = np.array([int(x) for x in parts[33:49]], dtype=np.int32)
                expected = int(parts[49])
                result = constraint_check(lower, upper, values)
                cc_tests += 1
                if result == expected:
                    cc_pass += 1
                else:
                    print(f"  CC MISMATCH: expected={expected} got={result}")

            elif section == '[EISENSTEIN_NORM]' and parts[0] == 'EN':
                a, b = int(parts[1]), int(parts[2])
                expected = int(parts[3])
                result = eisenstein_norm(a, b)
                en_tests += 1
                if result == expected:
                    en_pass += 1
                else:
                    print(f"  EN MISMATCH: ({a},{b}) expected={expected} got={result}")

            elif section == '[BLOOM_MERGE]' and parts[0] == 'BM':
                dst = np.array([np.uint64(int(x)) for x in parts[1:11]])
                src = np.array([np.uint64(int(x)) for x in parts[11:21]])
                expected = np.array([np.uint64(int(x)) for x in parts[21:31]])
                result = dst | src
                bm_tests += 1
                if np.array_equal(result, expected):
                    bm_pass += 1
                else:
                    mismatches = np.sum(result != expected)
                    print(f"  BM MISMATCH: {mismatches} words differ")

    print("=" * 50)
    print("DIFFERENTIAL TEST RESULTS (Python vs C ground truth)")
    print("=" * 50)
    print(f"  Constraint check:  {cc_pass}/{cc_tests} pass ({cc_pass/cc_tests*100:.1f}%)")
    print(f"  Eisenstein norm:   {en_pass}/{en_tests} pass ({en_pass/en_tests*100:.1f}%)")
    print(f"  Bloom merge:       {bm_pass}/{bm_tests} pass ({bm_pass/bm_tests*100:.1f}%)")
    print(f"\n  TOTAL: {cc_pass+en_pass+bm_pass}/{cc_tests+en_tests+bm_tests} passing")

    if cc_pass + en_pass + bm_pass == cc_tests + en_tests + bm_tests:
        print("\n  ✓ ZERO DIFFERENTIAL MISMATCHES")
        print("  Python/numpy produces IDENTICAL results to C reference.")
    else:
        print("\n  ✗ MISMATCHES DETECTED")

if __name__ == "__main__":
    main()
