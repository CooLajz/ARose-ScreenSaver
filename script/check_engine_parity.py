#!/usr/bin/env python3
"""Compare snapshots with the Swift reference, including exact indexed pixels."""
import argparse
import math
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser(description=__doc__)
g = p.add_mutually_exclusive_group(required=True)
g.add_argument('--actual', type=Path)
g.add_argument('--executable', type=Path)
p.add_argument('--reference', type=Path, default=root/'Tests/Parity/reference.txt')
a = p.parse_args()
actual = a.actual.read_text(encoding='utf-8-sig') if a.actual else subprocess.check_output([str(a.executable.resolve())], text=True)
x = actual.splitlines()
y = a.reference.read_text().splitlines()
if len(x) != len(y):
    raise SystemExit('Parity failed: snapshot count differs')
for line, (cpp, swift) in enumerate(zip(x, y), 1):
    left, right = cpp.split(), swift.split()
    if len(left) != len(right):
        raise SystemExit(f'Parity failed: column count at line {line}')
    for col, (u, v) in enumerate(zip(left, right)):
        match = math.isclose(float(u), float(v), rel_tol=1e-12, abs_tol=1e-9) if len(left) == 13 and col >= 4 else u == v
        if not match:
            raise SystemExit(f'Parity failed at line {line}, column {col}: {u} != {v}')
print('PASS: exact indexed pixel hashes/palettes and modern coordinates at all 24 checkpoints')
