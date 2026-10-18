#!/usr/bin/env python3
"""Keep the upstream signing executable at a stable path outside synced sources."""
from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent

def prepare():
    source = ROOT/'.build/updaters/bin/sign_update'
    destination = Path.home()/'Library/Application Support/ARose Release Tools/2.10.0/sign_update'
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        subprocess.run(['/usr/bin/ditto', '--norsrc', '--noextattr', str(source), str(destination)], check=True)
    if hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(destination.read_bytes()).digest():
        raise SystemExit('Signing tool differs from the pinned upstream distribution')
    return destination

if __name__ == '__main__': print(prepare())
