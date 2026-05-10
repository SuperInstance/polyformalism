#!/usr/bin/env python3
"""FLUX Constraint VM — Minimal interpreter for the fleet's constraint ISA.

This is the reference implementation. Every fleet agent can execute FLUX bytecode.
The VM is ~120 lines because constraints don't need a general-purpose processor.
"""
import struct
import sys

# Opcodes
OP_LOAD     = 0x01
OP_CHECK    = 0x02
OP_AND      = 0x03
OP_OR       = 0x04
OP_NORM     = 0x05
OP_EMIT     = 0x06
OP_HALT     = 0x07
OP_BLOOM_OR = 0x08
OP_NOT      = 0x09

class FluxVM:
    def __init__(self):
        self.regs = [0] * 64       # r0-r63 (i64)
        self.stack = []             # data stack (bools/i64)
        self.output = []
        self.pc = 0

    def load(self, bytecode):
        """Load flat list of integers as bytecode."""
        self.code = bytecode
        self.pc = 0

    def fetch(self):
        val = self.code[self.pc]
        self.pc += 1
        return val

    def run(self):
        while self.pc < len(self.code):
            op = self.fetch()
            if op == OP_HALT:
                break
            elif op == OP_LOAD:
                reg = self.fetch()
                imm = self.fetch()
                self.regs[reg] = imm
            elif op == OP_CHECK:
                lo = self.fetch()
                hi = self.fetch()
                val = self.fetch()
                result = self.regs[lo] <= self.regs[val] <= self.regs[hi]
                self.stack.append(1 if result else 0)
            elif op == OP_AND:
                b = self.stack.pop()
                a = self.stack.pop()
                self.stack.append(a & b)
            elif op == OP_OR:
                b = self.stack.pop()
                a = self.stack.pop()
                self.stack.append(a | b)
            elif op == OP_NORM:
                a = self.fetch()
                b = self.fetch()
                dst = self.fetch()
                va, vb = self.regs[a], self.regs[b]
                self.regs[dst] = va * va - va * vb + vb * vb
            elif op == OP_EMIT:
                reg = self.fetch()
                self.output.append(self.regs[reg])
            elif op == OP_BLOOM_OR:
                dst = self.fetch()
                src = self.fetch()
                self.regs[dst] = (self.regs[dst] & 0xFFFFFFFFFFFFFFFF) | (self.regs[src] & 0xFFFFFFFFFFFFFFFF)
            elif op == OP_NOT:
                v = self.stack.pop()
                self.stack.append(0 if v else 1)
            else:
                raise ValueError(f"Unknown opcode 0x{op:02x} at pc={self.pc-1}")

# === Test program (same as constraints.flux) ===
def main():
    vm = FluxVM()

    # Hand-assembled FLUX bytecode for the constraint pipeline
    code = [
        # Load values r0-r15
        OP_LOAD, 0, 25,  OP_LOAD, 1, 30,  OP_LOAD, 2, 35,  OP_LOAD, 3, 40,
        OP_LOAD, 4, 50,  OP_LOAD, 5, 60,  OP_LOAD, 6, 70,  OP_LOAD, 7, 80,
        OP_LOAD, 8, 10,  OP_LOAD, 9, 20,  OP_LOAD, 10, 30, OP_LOAD, 11, 40,
        OP_LOAD, 12, 55, OP_LOAD, 13, 65, OP_LOAD, 14, 75, OP_LOAD, 15, 85,

        # Load lower bounds r16-r31 (all 0)
        *[x for i in range(16) for x in (OP_LOAD, 16+i, 0)],

        # Load upper bounds r32-r47 (all 100)
        *[x for i in range(16) for x in (OP_LOAD, 32+i, 100)],

        # Check all 16 constraints with AND reduction
        OP_CHECK, 16, 32, 0,
        OP_CHECK, 17, 33, 1,  OP_AND,
        OP_CHECK, 18, 34, 2,  OP_AND,
        OP_CHECK, 19, 35, 3,  OP_AND,
        OP_CHECK, 20, 36, 4,  OP_AND,
        OP_CHECK, 21, 37, 5,  OP_AND,
        OP_CHECK, 22, 38, 6,  OP_AND,
        OP_CHECK, 23, 39, 7,  OP_AND,
        OP_CHECK, 24, 40, 8,  OP_AND,
        OP_CHECK, 25, 41, 9,  OP_AND,
        OP_CHECK, 26, 42, 10, OP_AND,
        OP_CHECK, 27, 43, 11, OP_AND,
        OP_CHECK, 28, 44, 12, OP_AND,
        OP_CHECK, 29, 45, 13, OP_AND,
        OP_CHECK, 30, 46, 14, OP_AND,
        OP_CHECK, 31, 47, 15, OP_AND,

        # Store constraint result in r48, emit it
        # (top of stack is the AND of all checks)
        # We'll peek at the stack after run instead

        # Bloom merge
        OP_LOAD, 56, 0x0000000000000001,  # dst: bit 0
        OP_LOAD, 57, 0x0000000000000008,  # dst: bit 3
        OP_LOAD, 58, 0x0000000000000010,  # src: bit 4
        OP_LOAD, 59, 0x0000000080000000,  # src: bit 31

        OP_BLOOM_OR, 56, 58,  # merge
        OP_BLOOM_OR, 57, 59,

        OP_EMIT, 56,
        OP_EMIT, 57,

        # Eisenstein norms
        OP_LOAD, 0, 3,   OP_LOAD, 1, 0,   OP_NORM, 0, 1, 48,  OP_EMIT, 48,
        OP_LOAD, 0, 0,   OP_LOAD, 1, 1,   OP_NORM, 0, 1, 49,  OP_EMIT, 49,
        OP_LOAD, 0, 2,   OP_LOAD, 1, -1,  OP_NORM, 0, 1, 50,  OP_EMIT, 50,
        OP_LOAD, 0, -1,  OP_LOAD, 1, 2,   OP_NORM, 0, 1, 51,  OP_EMIT, 51,
        OP_LOAD, 0, 5,   OP_LOAD, 1, 5,   OP_NORM, 0, 1, 52,  OP_EMIT, 52,

        OP_HALT,
    ]

    vm.load(code)
    vm.run()

    print("=== Polyformalism: FLUX VM ===")
    print(f"Stack (constraint result): {vm.stack}")
    print(f"Constraint check: {'PASS' if vm.stack and vm.stack[0] else 'FAIL'}")
    print()

    # Parse output
    print("Bloom word 0 (merged):", hex(vm.output[0]))
    print("Bloom word 1 (merged):", hex(vm.output[1]))
    print()

    norms = vm.output[2:]
    labels = ["N(3,0)", "N(0,1)", "N(2,-1)", "N(-1,2)", "N(5,5)"]
    for label, val in zip(labels, norms):
        print(f"{label} = {val}")

    # Verify
    assert vm.stack[0] == 1, "Constraint check should pass"
    assert vm.output[0] == 0x11, f"Bloom word 0 should be 0x11, got {hex(vm.output[0])}"
    assert vm.output[2] == 9,   "N(3,0) should be 9"
    assert vm.output[3] == 1,   "N(0,1) should be 1"
    assert vm.output[4] == 7,   "N(2,-1) should be 7"
    assert vm.output[5] == 7,   "N(-1,2) should be 7"
    assert vm.output[6] == 25,  "N(5,5) should be 25"

    print("\nAll assertions passed. FLUX VM works.")

if __name__ == "__main__":
    main()
