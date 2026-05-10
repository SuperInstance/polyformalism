#!/usr/bin/env python3
"""
Polyformalism Benchmark Runner
Compiles and runs all available implementations, collects results.
"""
import subprocess, time, json, os, sys

RESULTS = {}

def run_cmd(cmd, cwd=None, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except Exception as e:
        return -1, "", str(e)

print("=" * 70)
print("POLYFORMALISM BENCHMARK SUITE")
print("=" * 70)

BASE = "/tmp/polyformalism-repo"

# 1. C reference
print("\n[C] Compiling...")
rc, out, err = run_cmd("gcc -O2 -mavx2 -o constraints_c constraints.c -lm", cwd=f"{BASE}/c")
if rc == 0:
    print("[C] Running...")
    rc, out, err = run_cmd("./constraints_c", cwd=f"{BASE}/c")
    print(out)
    RESULTS["c"] = {"status": "PASS" if rc == 0 else "FAIL", "output": out}
else:
    print(f"[C] Compile failed: {err}")
    RESULTS["c"] = {"status": "COMPILE_FAIL"}

# 2. Python
print("\n[Python/numpy] Running...")
rc, out, err = run_cmd("python3 python/constraints.py", cwd=BASE)
print(out)
RESULTS["python"] = {"status": "PASS" if rc == 0 else "FAIL", "output": out}

# 3. FLUX VM
print("\n[FLUX VM] Running...")
rc, out, err = run_cmd("python3 flux/vm.py", cwd=BASE)
print(out)
RESULTS["flux"] = {"status": "PASS" if rc == 0 else "FAIL", "output": out}

# 4. Zig
print("\n[Zig] Compiling...")
zig_path = "/tmp/zig-linux-x86_64-0.13.0/zig"
rc, out, err = run_cmd(f"{zig_path} build-exe constraints.zig -OReleaseSafe", cwd=f"{BASE}/zig")
if rc == 0:
    print("[Zig] Running...")
    rc, out, err = run_cmd("./constraints", cwd=f"{BASE}/zig")
    print(out)
    RESULTS["zig"] = {"status": "PASS" if rc == 0 else "FAIL", "output": out}
else:
    print(f"[Zig] Compile failed: {err}")
    RESULTS["zig"] = {"status": "COMPILE_FAIL"}

# 5. Nim
print("\n[Nim] Compiling...")
nim_path = "/home/phoenix/.nimble/bin/nim"
rc, out, err = run_cmd(f"{nim_path} c -d:release -o:constraints_nim constraints.nim", cwd=f"{BASE}/nim", timeout=60)
if rc == 0:
    print("[Nim] Running...")
    rc, out, err = run_cmd("./constraints_nim", cwd=f"{BASE}/nim")
    print(out)
    RESULTS["nim"] = {"status": "PASS" if rc == 0 else "FAIL", "output": out}
else:
    print(f"[Nim] Compile failed: {err[:200]}")
    RESULTS["nim"] = {"status": "COMPILE_FAIL"}

# Summary
print("\n" + "=" * 70)
print("SUMMARY")
print("=" * 70)
for lang, data in RESULTS.items():
    print(f"  {lang:15s} {data['status']}")

passed = sum(1 for d in RESULTS.values() if d["status"] == "PASS")
print(f"\n  {passed}/{len(RESULTS)} implementations tested and passing")
