#!/usr/bin/env python3
"""
constraint_cascade.py — Constraint Cascade Through 50-Node Network

Each node has 16 INT32 constraint values. When any value drifts beyond bounds,
it triggers a "repair" adjusting neighbors. With 1% probability per tick, a
random node's value drifts ±5.

Compares two strategies:
  1. Baseline repair — random-order neighbor repair
  2. Eisenstein-weighted repair — closer lattice neighbors repaired first
     using Eisenstein norm (a^2 - ab + b^2) as distance metric

Runs 5000 ticks, visualizes violation count over time for both strategies.
"""

import numpy as np
import matplotlib
import sys

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from collections import deque

# ── Parameters ──────────────────────────────────────────────────────────────
NUM_NODES = 50
NUM_CONSTRAINTS = 16  # per node
TICKS = 5000
DRIFT_PROB = 0.01
DRIFT_MAGNITUDE = 5
CONSTRAINT_LOWER = -20
CONSTRAINT_UPPER = 20

# Eisenstein integer lattice: map 50 nodes onto a grid of ~7x8
GRID_COLS = 10
GRID_ROWS = 5  # 10*5 = 50


def node_positions():
    """Return (row, col) for each node on a 2D lattice."""
    pos = {}
    idx = 0
    for r in range(GRID_ROWS):
        for c in range(GRID_COLS):
            if idx < NUM_NODES:
                pos[idx] = (r, c)
                idx += 1
    return pos


def eisenstein_norm_sq(a, b):
    """Eisenstein norm squared: a^2 - a*b + b^2.
    This defines distance in the Eisenstein integer lattice.
    """
    return a * a - a * b + b * b


def eisenstein_distance(p1, p2):
    """Dist between two (row, col) nodes in Eisenstein metric."""
    dr = p1[0] - p2[0]
    dc = p1[1] - p2[1]
    # For a 2D grid of integers, the Eisenstein norm treats
    # (dr, dc) coordinates as Eisenstein integers: dr + dc * ω
    # where ω = (-1 + i√3)/2. The norm = dr^2 - dr*dc + dc^2.
    return eisenstein_norm_sq(dr, dc)


def get_neighbors(nid, positions):
    """Manhattan-adjacent neighbors on the lattice (wrapping at edges)."""
    r, c = positions[nid]
    neighbors = []
    for nr, nc in [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]:
        # Wrap around
        nr_w = nr % GRID_ROWS
        nc_w = nc % GRID_COLS
        # Find node at this position
        for other, pos in positions.items():
            if pos == (nr_w, nc_w) and other != nid:
                neighbors.append(other)
                break
    return neighbors


def init_state():
    """Initialize 50 nodes, each with 16 constraint values."""
    rng = np.random.default_rng(42)
    state = rng.integers(-10, 11, size=(NUM_NODES, NUM_CONSTRAINTS), dtype=np.int32)
    positions = node_positions()
    return state, positions


def count_violations(state):
    """Count how many nodes have at least one constraint out of bounds."""
    violations = np.logical_or(state < CONSTRAINT_LOWER, state > CONSTRAINT_UPPER)
    n_violations_per_node = np.sum(violations, axis=1)
    return n_violations_per_node, int(np.sum(n_violations_per_node > 0))


def simulate_baseline(state, positions):
    """Baseline: random-order neighbor repair."""
    n_violations_per_node, total_violating = count_violations(state)
    violation_history = [total_violating]
    cascade_depth_history = [0]

    rng = np.random.default_rng(42)

    for tick in range(1, TICKS + 1):
        # ── Drift ──
        for nid in range(NUM_NODES):
            if rng.random() < DRIFT_PROB:
                drift = rng.integers(-DRIFT_MAGNITUDE, DRIFT_MAGNITUDE + 1)
                col = rng.integers(0, NUM_CONSTRAINTS)
                state[nid, col] = np.int32(int(state[nid, col]) + drift)

        # ── Repair ──
        max_cascade = 0
        # Track nodes that just violated — propagate repair outward
        fringe = deque()
        visited = set()
        for nid in range(NUM_NODES):
            vcount = 0
            for c in range(NUM_CONSTRAINTS):
                val = int(state[nid, c])
                if val < CONSTRAINT_LOWER or val > CONSTRAINT_UPPER:
                    # Clamp
                    clamped = max(CONSTRAINT_LOWER, min(CONSTRAINT_UPPER, val))
                    state[nid, c] = np.int32(clamped)
                    vcount += 1
            if vcount > 0:
                fringe.append((nid, 0))
                visited.add(nid)

        # BFS cascade through neighbors
        cascade_count = 0
        while fringe:
            nid, depth = fringe.popleft()
            cascade_count += 1
            if depth > max_cascade:
                max_cascade = depth
            for nb in get_neighbors(nid, positions):
                if nb in visited:
                    continue
                # Check if neighbor needs repair
                needs_repair = False
                for c in range(NUM_CONSTRAINTS):
                    val = int(state[nb, c])
                    if val < CONSTRAINT_LOWER or val > CONSTRAINT_UPPER:
                        clamped = max(CONSTRAINT_LOWER, min(CONSTRAINT_UPPER, val))
                        state[nb, c] = np.int32(clamped)
                        needs_repair = True
                if needs_repair:
                    visited.add(nb)
                    fringe.append((nb, depth + 1))

        cascade_depth_history.append(max_cascade)

        # Record violations
        n_violations_per_node, total_violating = count_violations(state)
        violation_history.append(total_violating)

    return violation_history, cascade_depth_history


def simulate_eisenstein(state, positions):
    """Eisenstein-weighted: closer lattice neighbors repaired first."""
    n_violations_per_node, total_violating = count_violations(state)
    violation_history = [total_violating]
    cascade_depth_history = [0]

    rng = np.random.default_rng(42)

    for tick in range(1, TICKS + 1):
        # ── Drift ──
        for nid in range(NUM_NODES):
            if rng.random() < DRIFT_PROB:
                drift = rng.integers(-DRIFT_MAGNITUDE, DRIFT_MAGNITUDE + 1)
                col = rng.integers(0, NUM_CONSTRAINTS)
                state[nid, col] = np.int32(int(state[nid, col]) + drift)

        # ── Repair (Eisenstein-weighted) ──
        max_cascade = 0
        fringe = deque()
        visited = set()

        for nid in range(NUM_NODES):
            vcount = 0
            for c in range(NUM_CONSTRAINTS):
                val = int(state[nid, c])
                if val < CONSTRAINT_LOWER or val > CONSTRAINT_UPPER:
                    clamped = max(CONSTRAINT_LOWER, min(CONSTRAINT_UPPER, val))
                    state[nid, c] = np.int32(clamped)
                    vcount += 1
            if vcount > 0:
                fringe.append((nid, 0))
                visited.add(nid)

        cascade_count = 0
        while fringe:
            nid, depth = fringe.popleft()
            cascade_count += 1
            if depth > max_cascade:
                max_cascade = depth
            # Get neighbors sorted by Eisenstein distance (closest first)
            my_pos = positions[nid]
            neighbors = get_neighbors(nid, positions)
            # Compute distance for each neighbor
            neighbor_dist = [(nb, eisenstein_distance(my_pos, positions[nb]))
                             for nb in neighbors]
            neighbor_dist.sort(key=lambda x: x[1])  # closest first

            for nb, _ in neighbor_dist:
                if nb in visited:
                    continue
                needs_repair = False
                for c in range(NUM_CONSTRAINTS):
                    val = int(state[nb, c])
                    if val < CONSTRAINT_LOWER or val > CONSTRAINT_UPPER:
                        clamped = max(CONSTRAINT_LOWER, min(CONSTRAINT_UPPER, val))
                        state[nb, c] = np.int32(clamped)
                        needs_repair = True
                if needs_repair:
                    visited.add(nb)
                    fringe.append((nb, depth + 1))

        cascade_depth_history.append(max_cascade)

        n_violations_per_node, total_violating = count_violations(state)
        violation_history.append(total_violating)

    return violation_history, cascade_depth_history


def run():
    print("=" * 60)
    print("  Constraint Cascade Simulation — 50 Nodes × 16 Constraints")
    print("=" * 60)
    print(f"  Nodes:           {NUM_NODES}")
    print(f"  Constraints/node: {NUM_CONSTRAINTS}")
    print(f"  Ticks:           {TICKS}")
    print(f"  Drift probability: {DRIFT_PROB} (±{DRIFT_MAGNITUDE})")
    print(f"  Constraint bounds: [{CONSTRAINT_LOWER}, {CONSTRAINT_UPPER}]")
    print(f"  Grid:            {GRID_ROWS}×{GRID_COLS} (torus)")
    print()

    # ── Baseline ──
    state_bl, positions = init_state()
    baseline_violations, baseline_cascade = simulate_baseline(state_bl.copy(), positions)

    # ── Eisenstein ──
    state_ei, _ = init_state()
    eisenstein_violations, eisenstein_cascade = simulate_eisenstein(state_ei.copy(), positions)

    # ── Statistics ──
    print("  Baseline Repair:")
    print(f"    Mean violations/tick: {np.mean(baseline_violations):.2f}")
    print(f"    Peak violations:      {max(baseline_violations)}")
    print(f"    Mean cascade depth:   {np.mean(baseline_cascade):.3f}")
    print(f"    Max cascade depth:    {max(baseline_cascade)}")
    print(f"    Violations at end:    {baseline_violations[-1]}")
    print()
    print("  Eisenstein-Weighted Repair:")
    print(f"    Mean violations/tick: {np.mean(eisenstein_violations):.2f}")
    print(f"    Peak violations:      {max(eisenstein_violations)}")
    print(f"    Mean cascade depth:   {np.mean(eisenstein_cascade):.3f}")
    print(f"    Max cascade depth:    {max(eisenstein_cascade)}")
    print(f"    Violations at end:    {eisenstein_violations[-1]}")

    # Improvement metrics
    baseline_total = np.sum(baseline_violations)
    eisenstein_total = np.sum(eisenstein_violations)
    reduction = ((baseline_total - eisenstein_total) / baseline_total) * 100
    print()
    print(f"  Eisenstein improvement: {reduction:.1f}% fewer violations over run")
    print("=" * 60)

    # ── Plotting ──────────────────────────────────────────────────────────
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10), sharex=True)

    ticks_arr = np.arange(TICKS + 1)
    ax1.plot(ticks_arr, baseline_violations, color="#d62728", linewidth=0.6,
             alpha=0.8, label="Baseline Repair")
    ax1.plot(ticks_arr, eisenstein_violations, color="#2ca02c", linewidth=0.6,
             alpha=0.8, label="Eisenstein-Weighted Repair")
    ax1.set_ylabel("Violating Nodes")
    ax1.set_title("Constraint Violations Over Time — Baseline vs Eisenstein-Weighted")
    ax1.legend()
    ax1.grid(alpha=0.3)

    # Rolling average (window=100) for smoother comparison
    window = 100
    if len(baseline_violations) > window:
        baseline_smooth = np.convolve(baseline_violations,
                                       np.ones(window) / window, mode="valid")
        eisenstein_smooth = np.convolve(eisenstein_violations,
                                         np.ones(window) / window, mode="valid")
        smooth_ticks = np.arange(len(baseline_smooth))
        ax2.plot(smooth_ticks, baseline_smooth, color="#d62728", linewidth=1.2,
                 label=f"Baseline (MA-{window})")
        ax2.plot(smooth_ticks, eisenstein_smooth, color="#2ca02c", linewidth=1.2,
                 label=f"Eisenstein (MA-{window})")
    ax2.set_ylabel("Violating Nodes (MA)")
    ax2.set_xlabel("Tick")
    ax2.set_title(f"Rolling Mean Violations (window={window})")
    ax2.legend()
    ax2.grid(alpha=0.3)

    plt.tight_layout()
    outpath = "/tmp/polyformalism-repo/simulations/constraint_cascade.png"
    plt.savefig(outpath, dpi=150)
    plt.close()
    print(f"\n  Plot saved to: {outpath}")
    print("=" * 60)


if __name__ == "__main__":
    run()
