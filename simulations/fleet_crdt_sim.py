#!/usr/bin/env python3
"""
Simulation 1b: Fixed CRDT convergence — nodes converge on a STATIC constraint set,
then measure how fast gossip propagates new constraints.
"""
import numpy as np
from collections import Counter

class BloomCRDT:
    def __init__(self, n_words=125):  # 1000 bits = small filter for fast convergence
        self.data = np.zeros(n_words, dtype=np.uint64)
        self.n_words = n_words
        self.total_bits = n_words * 64

    def insert(self, key):
        pos = abs(hash(str(key))) % self.total_bits
        self.data[pos // 64] |= np.uint64(1 << (pos % 64))

    def contains(self, key):
        pos = abs(hash(str(key))) % self.total_bits
        return bool(self.data[pos // 64] & np.uint64(1 << (pos % 64)))

    def merge_from(self, other):
        np.bitwise_or(self.data, other.data, out=self.data)
        return self.n_words * 8

    def popcount(self):
        return sum(bin(x).count('1') for x in self.data)

    def state_hash(self):
        return self.data.tobytes()

    def copy(self):
        b = BloomCRDT(self.n_words)
        b.data = self.data.copy()
        return b


def simulate_convergence(n_nodes=20, n_ticks=500, gossip_interval=5,
                          keys_per_node=50, new_key_interval=50,
                          byzantine_nodes=0, seed=42):
    """Phase 1: Each node inserts static keys. Phase 2: Gossip until converged.
    Phase 3: Inject new keys and measure propagation speed."""
    np.random.seed(seed)

    nodes = [BloomCRDT(125) for _ in range(n_nodes)]
    byzantine = set(range(byzantine_nodes))

    # Phase 1: Each node inserts its own keys (NOT shared yet)
    for i, node in enumerate(nodes):
        for k in range(keys_per_node):
            node.insert(f"node_{i}_key_{k}")

    convergence = []
    propagation_speed = []  # how fast a new key spreads

    for tick in range(n_ticks):
        # Gossip
        if tick % gossip_interval == 0:
            n_pairs = n_nodes // 2
            for _ in range(n_pairs):
                i, j = np.random.choice(n_nodes, 2, replace=False)
                nodes[i].merge_from(nodes[j])
                nodes[j].merge_from(nodes[i])

        # Byzantine nodes inject junk
        for b in byzantine:
            nodes[b].insert(f"byzantine_tick_{tick}_{np.random.randint(0,10000)}")

        # Inject a new "global" key at tick 0 on node 0, track propagation
        if tick == 0:
            nodes[0].insert("GLOBAL_CANARY_KEY")
        if tick < 200:
            count = sum(1 for n in nodes if n.contains("GLOBAL_CANARY_KEY"))
            propagation_speed.append(count)

        # Measure convergence
        states = [n.state_hash() for n in nodes]
        counts = Counter(states)
        majority_pct = counts.most_common(1)[0][1] / n_nodes * 100
        convergence.append(majority_pct)

    # Find convergence time
    t90 = next((i for i, c in enumerate(convergence) if c >= 90), -1)
    t95 = next((i for i, c in enumerate(convergence) if c >= 95), -1)
    t100 = next((i for i, c in enumerate(convergence) if c >= 100), -1)

    # Propagation: time for canary to reach all nodes
    t_full_prop = next((i for i, c in enumerate(propagation_speed) if c == n_nodes), -1)

    print(f"  Nodes={n_nodes}, gossip={gossip_interval}, keys/node={keys_per_node}, byz={byzantine_nodes}")
    print(f"    Convergence: t90={t90}, t95={t95}, t100={t100}")
    print(f"    Canary reached all nodes at tick: {t_full_prop if t_full_prop >= 0 else 'NOT REACHED'}")
    print(f"    Final convergence: {convergence[-1]:.0f}%")

    return convergence, propagation_speed


def simulate_cascade(n_nodes=100, n_ticks=10000, drift_prob=0.05, drift_amount=15, seed=42):
    """Cascade with aggressive drift — values near boundary, big drifts."""
    np.random.seed(seed)

    # Values near boundary: 85-95 (bounds are ±100)
    values = np.random.uniform(85, 95, size=(n_nodes, 16)).astype(np.float64)
    lower = np.full((n_nodes, 16), -100.0)
    upper = np.full((n_nodes, 16), 100.0)

    # Small-world network
    neighbors = [[] for _ in range(n_nodes)]
    for i in range(n_nodes):
        neighbors[i].extend([(i + 1) % n_nodes, (i - 1) % n_nodes])
        for _ in range(3):
            j = np.random.randint(0, n_nodes)
            if j != i and j not in neighbors[i]:
                neighbors[i].append(j)

    def eisenstein_norm(a, b):
        return a * a - a * b + b * b

    # Eisenstein coordinates for each node
    coords = [(int(i * 7 % 31) - 15, int(i * 13 % 31) - 15) for i in range(n_nodes)]

    # Strategy 1: Random order repair
    vals_r = values.copy()
    viol_r = []
    for tick in range(n_ticks):
        # Drift
        for i in range(n_nodes):
            if np.random.random() < drift_prob:
                dim = np.random.randint(0, 16)
                vals_r[i, dim] += np.random.uniform(-drift_amount, drift_amount)

        in_viol = np.any((vals_r < lower) | (vals_r > upper), axis=1)
        viol_r.append(np.sum(in_viol))

        # Repair random order
        for i in np.random.permutation(n_nodes):
            if in_viol[i]:
                vals_r[i] = np.clip(vals_r[i], lower[i], upper[i])
                for j in neighbors[i]:
                    vals_r[j] += (vals_r[i] - vals_r[j]) * 0.1

    # Strategy 2: Eisenstein-weighted (repair by lattice distance from center first)
    vals_e = values.copy()
    viol_e = []
    center_dist = [eisenstein_norm(*c) for c in coords]

    for tick in range(n_ticks):
        for i in range(n_nodes):
            if np.random.random() < drift_prob:
                dim = np.random.randint(0, 16)
                vals_e[i, dim] += np.random.uniform(-drift_amount, drift_amount)

        in_viol = np.any((vals_e < lower) | (vals_e > upper), axis=1)
        viol_e.append(np.sum(in_viol))

        # Repair Eisenstein order
        viol_idx = np.where(in_viol)[0]
        dists = np.array([center_dist[i] for i in viol_idx])
        repair_order = viol_idx[np.argsort(dists)]

        for i in repair_order:
            if np.any((vals_e[i] < lower[i]) | (vals_e[i] > upper[i])):
                vals_e[i] = np.clip(vals_e[i], lower[i], upper[i])
                for j in neighbors[i]:
                    dist = eisenstein_norm(coords[i][0] - coords[j][0],
                                          coords[i][1] - coords[j][1])
                    weight = 0.1 / (1.0 + dist * 0.1)
                    vals_e[j] += (vals_e[i] - vals_e[j]) * weight

    print(f"\n  === Cascade: {n_nodes} nodes, {n_ticks} ticks, drift={drift_prob}±{drift_amount} ===")
    print(f"  Random:      avg={np.mean(viol_r):.2f}, max={np.max(viol_r)}, last1k={np.mean(viol_r[-1000:]):.2f}")
    print(f"  Eisenstein:  avg={np.mean(viol_e):.2f}, max={np.max(viol_e)}, last1k={np.mean(viol_e[-1000:]):.2f}")
    improvement = (np.mean(viol_r) - np.mean(viol_e)) / max(np.mean(viol_r), 0.001) * 100
    print(f"  Advantage:   {improvement:+.1f}%")
    for t in [0, 100, 500, 1000, 2000, 5000, 9999]:
        print(f"    tick {t:5d}: random={viol_r[t]:3d}  eise={viol_e[t]:3d}")

    return viol_r, viol_e


if __name__ == "__main__":
    print("=" * 60)
    print("POLYFORMALISM: CRDT CONVERGENCE & CASCADE SIMULATIONS")
    print("=" * 60)

    # Exp 1: Convergence with various parameters
    print("\n--- Experiment 1: CRDT Convergence ---")
    print("\nA) Baseline (20 nodes, 50 keys/node, gossip every 5):")
    simulate_convergence(n_nodes=20, keys_per_node=50, gossip_interval=5, byzantine_nodes=0)

    print("\nB) With Byzantine nodes (2 of 20):")
    simulate_convergence(n_nodes=20, keys_per_node=50, gossip_interval=5, byzantine_nodes=2)

    print("\nC) More nodes (50):")
    simulate_convergence(n_nodes=50, keys_per_node=30, gossip_interval=5, byzantine_nodes=0)

    print("\nD) Faster gossip (every 2 ticks):")
    simulate_convergence(n_nodes=20, keys_per_node=50, gossip_interval=2, byzantine_nodes=0)

    print("\nE) Slow gossip (every 20 ticks):")
    simulate_convergence(n_nodes=20, keys_per_node=50, gossip_interval=20, byzantine_nodes=0)

    # Exp 2: Cascade
    print("\n\n--- Experiment 2: Constraint Cascade ---")
    simulate_cascade(n_nodes=100, n_ticks=10000, drift_prob=0.05, drift_amount=15)
