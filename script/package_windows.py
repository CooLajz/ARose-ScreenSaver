#!/usr/bin/env python3
"""Package an unsigned Windows development candidate on any build host."""
import argparse
import re
import hashlib
import plistlib
import struct
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', default='build-windows/Release/ARose.scr')
parser.add_argument('--label', default='development')
args = parser.parse_args()
if not re.fullmatch(r'[a-z0-9-]+', args.label):
    raise SystemExit('Invalid package label')
binary = Path(args.binary)
if not binary.is_absolute():
    binary = root / binary
payload = binary.read_bytes()
if payload[:2] != b'MZ':
    raise SystemExit('Expected a Windows PE executable')
pe = struct.unpack_from('<I', payload, 60)[0]
if payload[pe:pe+4] != b'PE\0\0' or struct.unpack_from('<H', payload, pe+4)[0] != 0x8664:
    raise SystemExit('Expected a Windows x64 executable')
if struct.unpack_from('<H', payload, pe+24+68)[0] != 2:
    raise SystemExit('Expected the Windows GUI subsystem, not a console executable')
with (root/'Resources/Saver-Info.plist').open('rb') as f:
    info = plistlib.load(f)
version = info['CFBundleShortVersionString']
expected = tuple(map(int, version.split('.'))) + (int(info['CFBundleVersion']),)
signature = payload.find(struct.pack('<I', 0xFEEF04BD))
if signature < 0:
    raise SystemExit('Missing Windows version resource')
ms, ls = struct.unpack_from('<II', payload, signature+8)
if (ms >> 16, ms & 65535, ls >> 16, ls & 65535) != expected:
    raise SystemExit('Windows and macOS versions differ; update resources and rebuild')
name = f'ARose-ScreenSaver-v{version}-Windows-x64-{args.label}'
folder = root/'dist/releases'
folder.mkdir(parents=True, exist_ok=True)
archive = folder/f'{name}.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.write(binary, f'{name}/ARose.scr')
    companion = binary.parent/'ARose Control.exe'
    updater = binary.parent/'WinSparkle.dll'
    if companion.is_file() and updater.is_file():
        z.write(companion, f'{name}/ARose Control.exe')
        z.write(updater, f'{name}/WinSparkle.dll')
        for notice in (root/'.build/updaters/WinSparkle-0.9.4').glob('COPYING*'):
            z.write(notice, f'{name}/Licenses/WinSparkle/{notice.name}')
    for src, dst in [('LICENSE','LICENSE'), ('THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'), ('Windows/INSTALL.txt','INSTALL.txt')]:
        z.write(root/src, f'{name}/{dst}')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
# Also offer the truly standalone saver, without a companion or DLL.
import shutil
standalone = folder/f'ARose-ScreenSaver-v{version}-Windows-x64.scr'
shutil.copy2(binary, standalone)
standalone.with_suffix('.scr.sha256').write_text(f'{hashlib.sha256(payload).hexdigest()}  {standalone.name}\n')
print(f'Development candidate: {archive.relative_to(root)}')
