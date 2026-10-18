#!/usr/bin/env python3
"""Download pinned, hash-verified updater distributions into ignored build storage."""
import hashlib
import io
from pathlib import Path
import sys
import tarfile
import urllib.request
import zipfile

root = Path(__file__).resolve().parent.parent / '.build/updaters'
root.mkdir(parents=True, exist_ok=True)
packages = {
 'macos': ('https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz',
           'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c', 'Sparkle.tar.xz'),
 'windows': ('https://github.com/vslavik/winsparkle/releases/download/v0.9.4/WinSparkle-0.9.4.zip',
             '6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976', 'WinSparkle.zip')}
for platform in sys.argv[1:] or packages:
    url, digest, name = packages[platform]
    archive = root/name
    if not archive.exists():
        with urllib.request.urlopen(url, timeout=60) as response:
            archive.write_bytes(response.read())
    data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f'Invalid SHA-256: {archive}; remove it and retry')
    marker = root/(platform + '.verified')
    required = root/('Sparkle.framework/Sparkle' if platform == 'macos' else 'WinSparkle-0.9.4/x64/Release/WinSparkle.dll')
    if marker.exists() and marker.read_text() == digest and required.exists():
        print(f'Verified {platform} updater (cached)')
        continue
    if name.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(data)) as z: z.extractall(root)
    else:
        # Archive bytes are pinned above; Sparkle intentionally contains symlinks.
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as t: t.extractall(root)
    marker.write_text(digest)
    print(f'Verified {platform} updater')
