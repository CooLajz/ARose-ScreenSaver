#!/usr/bin/env python3
"""Create release appcasts on the signing Mac, using the ARose Keychain key.

This does not upload or publish anything. Both final update payloads are
required so the latest release can always serve both platform feeds.
"""
import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import plistlib
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from prepare_signing_tools import prepare

ROOT = Path(__file__).resolve().parent.parent
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)
BASE = 'https://github.com/CooLajz/ARose-ScreenSaver/releases/download/'


def appcast(version, build, platform, payload, signature):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('Expected stable version and increasing numeric build')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid Ed25519 signature')
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'ARose ScreenSaver'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'ARose ' + version
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f'{{{NS}}}version').text = build
    ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '13.0' if platform == 'macos' else '10.0.22000'
    attrs = {
        'url': BASE + 'v' + version + '/' + payload.name,
        'length': str(payload.stat().st_size),
        'type': 'application/octet-stream',
        f'{{{NS}}}version': build,
        f'{{{NS}}}shortVersionString': version,
        f'{{{NS}}}edSignature': signature,
        f'{{{NS}}}os': 'macos' if platform == 'macos' else 'windows-x64',
    }
    if platform == 'windows':
        attrs[f'{{{NS}}}installerArguments'] = '/SILENT /SUPPRESSMSGBOXES /NORESTART'
    ET.SubElement(item, 'enclosure', attrs)
    ET.indent(rss)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT/'dist/releases')
    args = parser.parse_args()
    with (ROOT/'Resources/Preview-Info.plist').open('rb') as f:
        info = plistlib.load(f)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    signer = prepare()
    verifier = ROOT/'.build/verify_update'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT/'.build/ModuleCache'),
                    str(ROOT/'script/verify_update.swift'), '-o', str(verifier)], check=True)
    files = {
        'macos': args.directory/f'ARose-ScreenSaver-v{version}-macOS-update.zip',
        'windows': args.directory/f'ARose-ScreenSaver-v{version}-Windows-x64-Setup.exe',
    }
    for payload in files.values():
        if not payload.is_file(): raise SystemExit(f'Missing final payload: {payload.name}')
    for platform, payload in files.items():
        signature = subprocess.check_output([str(signer), '--account', 'cz.coolajz.ARose', '-p', str(payload)], text=True).strip()
        subprocess.run([str(verifier), str(payload), signature, info['SUPublicEDKey']], check=True)
        output = args.directory/f'appcast-{platform}.xml'
        output.write_bytes(appcast(version, build, platform, payload, signature))
        print(f'Created {output.name}')


if __name__ == '__main__': main()
