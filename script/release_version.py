#!/usr/bin/env python3
"""Read and validate shared release metadata before packaging/updater compilation."""
import argparse
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--format', choices=['version','build','header'], default='version')
args = parser.parse_args()
with (root/'Resources/Saver-Info.plist').open('rb') as f: saver=plistlib.load(f)
with (root/'Resources/Preview-Info.plist').open('rb') as f: app=plistlib.load(f)
with (root/'Resources/Extension-Info.plist').open('rb') as f: extension=plistlib.load(f)
version, build = saver['CFBundleShortVersionString'], saver['CFBundleVersion']
if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not re.fullmatch(r'[1-9]\d*',build):
    raise SystemExit('Invalid version/build')
if any(info['CFBundleShortVersionString'] != version or info['CFBundleVersion'] != build for info in [app, extension]):
    raise SystemExit('Saver and companion versions differ')
rc=(root/'Windows/ARose.rc').read_text()
expected=version.replace('.',',')+','+build
for key in ['FILEVERSION','PRODUCTVERSION']:
    if not re.search(r'\b'+key+r'\s+'+re.escape(expected)+r'\s',rc):
        raise SystemExit('Windows resource and macOS versions differ')
cmake=(root/'Windows/CMakeLists.txt').read_text()
if 'project(ARoseScreenSaver VERSION '+version+' ' not in cmake:
    raise SystemExit('CMake and bundle versions differ')
if args.format=='header':
    print(f'#pragma once\n#define AROSE_DISPLAY_VERSION L"{version}"\n#define AROSE_BUILD_VERSION L"{build}"')
else: print(version if args.format=='version' else build)
