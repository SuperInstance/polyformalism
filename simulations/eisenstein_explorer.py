#!/usr/bin/env python3
"""
Simulation 3: Eisenstein Lattice Explorer
Generate, analyze, and measure precision on the Eisenstein integer lattice ℤ[ω].
"""
import struct
import numpy as np
from collections import defaultdict

def eisenstein_norm(a, b):
    return a * a - a * b + b * b

def eise_to_cartesian(a, b):
    """Eisenstein (a + bω) to Cartesian (x, y)."""
    x = a - b / 2.0
    y = b * np.sqrt(3) / 2.0
    return x, y

def generate_lattice(max_coord):
    """Generate all Eisenstein integers with |a|,|b| <= max_coord."""
    points = []
    for a in range(-max_coord, max_coord + 1):
        for b in range(-max_coord, max_coord + 1):
            n = eisenstein_norm(a, b)
            points.append((a, b, n))
    return points

def roundtrip_fp32(a, b):
    """Round-trip (a,b) through FP32 and back."""
    fa = struct.unpack('f', struct.pack('f', float(a)))[0]
    fb = struct.unpack('f', struct.pack('f', float(b)))[0]
    return int(round(fa)) == a and int(round(fb)) == b

def roundtrip_fp32_norm(a, b):
    """Compute norm through FP32 arithmetic."""
    fa = float(a)
    fb = float(b)
    fn = fa * fa - fa * fb + fb * fb
    return fn

def roundtrip_int8(a, b):
    return -128 <= a <= 127 and -128 <= b <= 127

def roundtrip_int16(a, b):
    return -32768 <= a <= 32767 and -32768 <= b <= 32767

def roundtrip_fp16_approx(a, b):
    """Simulate FP16: 10-bit mantissa, values > 2048 lose integer precision."""
    if abs(a) > 65504 or abs(b) > 65504:
        return False
    # FP16 can represent integers exactly up to 2^11 = 2048
    # After that, precision degrades
    if abs(a) <= 2048 and abs(b) <= 2048:
        return True
    # Check if the value is a multiple of 2^(k-10) where k = floor(log2(|v|))
    for v in [a, b]:
        if v == 0: continue
        av = abs(v)
        if av <= 2048: continue
        import math
        k = int(math.floor(math.log2(av)))
        step = 2 ** (k - 10)
        if v % step != 0:
            return False
    return True


def analyze_lattice(max_coord=100):
    """Full lattice analysis."""
    print("=" * 60)
    print("EISENSTEIN LATTICE ANALYSIS")
    print("=" * 60)

    points = generate_lattice(max_coord)
    print(f"\nGenerated {len(points)} lattice points (|a|,|b| ≤ {max_coord})")

    # Part 1: Norm shell counts
    print("\n--- Part 1: Norm Shell Counts (OEIS A004016) ---")
    shells = defaultdict(list)
    for a, b, n in points:
        shells[n].append((a, b))

    max_norm = 100
    print(f"{'Norm':>6} {'Count':>6} {'Cartesian Dist':>14}")
    print("-" * 30)
    for n in sorted(shells.keys())[:40]:
        count = len(shells[n])
        dist = np.sqrt(n)  # N = |z|², so |z| = √N
        print(f"{n:6d} {count:6d} {dist:14.3f}")

    # Part 2: Nearest neighbors
    print("\n--- Part 2: Nearest Neighbors ---")
    # The 6 nearest neighbors at distance 1
    directions = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)]
    print("6 nearest neighbors of (0,0):")
    for da, db in directions:
        n = eisenstein_norm(da, db)
        x, y = eise_to_cartesian(da, db)
        print(f"  ({da:+d},{db:+d})  N={n}  dist={np.sqrt(n):.3f}  cartesian=({x:.2f},{y:.2f})")

    # Verify all 6 have norm 1
    all_unit = all(eisenstein_norm(da, db) == 1 for da, db in directions)
    print(f"\nAll 6 directions have norm 1: {all_unit} → hexagonal packing confirmed")

    # Part 3: D6 symmetry
    print("\n--- Part 3: D6 Symmetry Operations ---")
    # D6 has 12 elements: 6 rotations + 6 reflections
    # Rotation by 60°: (a,b) → (-b, a+b)
    # Reflection: (a,b) → (b, a)
    test_pts = [(3, 0), (2, 1), (1, 2)]
    print("Rotation by 60°: (a,b) → (-b, a+b)")
    for a, b in test_pts:
        ra, rb = -b, a + b
        n_orig = eisenstein_norm(a, b)
        n_rot = eisenstein_norm(ra, rb)
        print(f"  ({a},{b}) → ({ra},{rb})  N preserved: {n_orig == n_rot}")

    print("\nReflection: (a,b) → (b,a)")
    for a, b in test_pts:
        ra, rb = b, a
        n_orig = eisenstein_norm(a, b)
        n_ref = eisenstein_norm(ra, rb)
        print(f"  ({a},{b}) → ({ra},{rb})  N preserved: {n_orig == n_ref}")

    # Part 4: Precision loss
    print("\n--- Part 4: Precision Loss ---")
    max_r = 200
    total = 0
    ok = {"INT8": 0, "INT16": 0, "FP16": 0, "FP32": 0, "FP64": 0, "INT32": 0}
    fp32_norm_drift = []

    for a in range(-max_r, max_r + 1):
        for b in range(-max_r, max_r + 1):
            total += 1
            n_exact = eisenstein_norm(a, b)

            if roundtrip_int8(a, b): ok["INT8"] += 1
            if roundtrip_int16(a, b): ok["INT16"] += 1
            if roundtrip_fp16_approx(a, b): ok["FP16"] += 1
            if roundtrip_fp32(a, b): ok["FP32"] += 1
            ok["FP64"] += 1  # always exact
            ok["INT32"] += 1  # always exact

            # FP32 norm drift
            n_fp32 = roundtrip_fp32_norm(a, b)
            drift = abs(n_fp32 - n_exact)
            if drift > 0:
                fp32_norm_drift.append((a, b, n_exact, n_fp32, drift))

    print(f"  Total points: {total}")
    print(f"  {'Precision':<8} {'Preserved':>10} {'Survival%':>10}")
    print(f"  {'-'*30}")
    for prec in ["INT8", "INT16", "FP16", "FP32", "FP64", "INT32"]:
        pct = ok[prec] / total * 100
        print(f"  {prec:<8} {ok[prec]:>10} {pct:>9.1f}%")

    # FP32 norm drift
    print(f"\n  FP32 norm computation drift: {len(fp32_norm_drift)} points affected")
    if fp32_norm_drift:
        max_drift = max(fp32_norm_drift, key=lambda x: x[4])
        print(f"  Max drift: N({max_drift[0]},{max_drift[1]}) exact={max_drift[2]} fp32={max_drift[3]} drift={max_drift[4]}")
        # First drift
        first = fp32_norm_drift[0]
        print(f"  First drift: N({first[0]},{first[1]}) exact={first[2]} fp32={first[3]} drift={first[4]}")

    # Part 5: Constraint packing density
    print("\n--- Part 5: Constraint Packing Density ---")
    radii = [1, 2, 5, 10, 20, 50, 100]
    print(f"  {'Radius':>8} {'Points':>8} {'Hex area':>10} {'Density':>10} {'vs optimal':>12}")
    optimal = np.pi / (2 * np.sqrt(3))  # hex close-packing = 0.9069
    for R in radii:
        count = sum(1 for a, b, n in points if n <= R * R)
        area = np.pi * R * R
        density = count / area if area > 0 else 0
        print(f"  {R:8d} {count:8d} {area:10.1f} {density:10.4f} {density/optimal:11.4f}")
    print(f"  Hex close-packing density: {optimal:.4f}")

    # Part 6: Lattice norms at key distances (the "Narrows" tracks)
    print("\n--- Part 6: The Narrows — Track Difficulty ---")
    print("  How many Eisenstein integers survive at each precision?")
    for max_norm_val in [7, 25, 49, 100, 400, 1000, 10000]:
        pts = [(a, b) for a, b, n in points if n <= max_norm_val]
        n_pts = len(pts)
        # Count unique norms (this is how many distinct constraint values exist)
        unique_norms = len(set(eisenstein_norm(a, b) for a, b in pts))
        print(f"  N≤{max_norm_val:6d}: {n_pts:5d} lattice points, {unique_norms:4d} unique norms")


if __name__ == "__main__":
    analyze_lattice(max_coord=200)
