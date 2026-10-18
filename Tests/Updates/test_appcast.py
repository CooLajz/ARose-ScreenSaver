import base64
import plistlib
import struct
import zipfile
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root/'script'))
spec = importlib.util.spec_from_file_location('appcasts', root/'script/create_appcasts.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
from release_payload import validate_payload, windows_version


def windows_fixture(version=(1, 2, 3, 9), pe64=True):
    """Small PE with a real type/name/language version resource tree."""
    optional_size = 240 if pe64 else 224
    data = bytearray(1024)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 128)
    data[128:132] = b'PE\0\0'
    struct.pack_into('<HH', data, 132, 0x8664 if pe64 else 0x14c, 1)
    struct.pack_into('<H', data, 148, optional_size)
    struct.pack_into('<H', data, 152, 0x20b if pe64 else 0x10b)
    directory = 112 if pe64 else 96
    struct.pack_into('<II', data, 152 + directory + 16, 0x1000, 512)
    struct.pack_into('<IIII', data, 152 + optional_size + 8, 512, 0x1000, 512, 512)
    for offset in [0, 24, 48]:
        struct.pack_into('<HH', data, 512 + offset + 12, 0, 1)
    struct.pack_into('<II', data, 528, 16, 0x80000018)
    struct.pack_into('<II', data, 552, 1, 0x80000030)
    struct.pack_into('<II', data, 576, 1033, 72)
    key = 'VS_VERSION_INFO\0'.encode('utf-16le')
    value = (6 + len(key) + 3) & ~3
    struct.pack_into('<IIII', data, 584, 0x1000 + 88, value + 52, 0, 0)
    start = 512 + 88
    struct.pack_into('<HHH', data, start, value + 52, 52, 0)
    data[start + 6:start + 6 + len(key)] = key
    a, b, c, d = version
    struct.pack_into('<IIII', data, start + value, 0xfeef04bd, 0x10000, a << 16 | b, c << 16 | d)
    return data

class AppcastTests(unittest.TestCase):
    def test_both_platforms_keep_signature_length_build_and_fixed_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp)/'ARose-update.zip'
            payload.write_bytes(b'fixture')
            signature = base64.b64encode(bytes(range(64))).decode()
            for platform in ['macos', 'windows']:
                xml = ET.fromstring(module.appcast('1.2.3', '9', platform, payload, signature))
                self.assertEqual(xml.findtext('./channel/item/{'+module.NS+'}minimumSystemVersion'),
                                 '14.0' if platform == 'macos' else '10.0.22000')
                enclosure = xml.find('./channel/item/enclosure')
                self.assertEqual(enclosure.get('length'), '7')
                self.assertEqual(enclosure.get('{'+module.NS+'}edSignature'), signature)
                self.assertEqual(enclosure.get('{'+module.NS+'}version'), '9')
                self.assertEqual(enclosure.get('url'), module.BASE+'v1.2.3/ARose-update.zip')
                self.assertEqual(enclosure.get('{'+module.NS+'}installerArguments') is not None, platform == 'windows')
    def test_platforms_share_public_key_and_disable_automatic_updates_by_default(self):
        with (root/'Resources/Preview-Info.plist').open('rb') as f: info=plistlib.load(f)
        self.assertEqual(len(base64.b64decode(info['SUPublicEDKey'])),32)
        self.assertIn(info['SUPublicEDKey'],(root/'Windows/Updates/main.cpp').read_text())
        self.assertFalse(info['SUEnableAutomaticChecks'])
        self.assertFalse(info['SUAutomaticallyUpdate'])
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
    def test_invalid_metadata_rejected(self):
        for version, build, signature in [('1.0.0-beta','4','x'),('1.0.0','0','x'),('1.0.0','4',base64.b64encode(b'bad').decode())]:
            with self.assertRaises(ValueError):
                module.appcast(version,build,'macos',Path('unused'),signature)

    def test_mac_payload_checks_app_and_extension_builds(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp)/'update.zip'
            for app_build, extension_build, valid in [('9', '9', True), ('8', '9', False), ('9', '8', False)]:
                with zipfile.ZipFile(payload, 'w') as archive:
                    for path, build in [('ARose.app/Contents/Info.plist', app_build),
                                        ('ARose.app/Contents/PlugIns/ARoseExtension.appex/Contents/Info.plist', extension_build)]:
                        archive.writestr(path, plistlib.dumps({'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': build}))
                if valid:
                    validate_payload(payload, 'macos', '1.2.3', '9')
                    with self.assertRaises(ValueError):
                        validate_payload(payload, 'macos', '1.2.4', '9')
                else:
                    with self.assertRaises(ValueError):
                        validate_payload(payload, 'macos', '1.2.3', '9')

    def test_windows_payload_reads_resources_not_incidental_signatures(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp)/'setup.exe'
            for pe64 in [False, True]:
                data = windows_fixture(pe64=pe64)
                # A decoy before .rsrc must not be mistaken for its version.
                struct.pack_into('<IIII', data, 448, 0xfeef04bd, 0x10000, 0, 0)
                payload.write_bytes(data)
                validate_payload(payload, 'windows', '1.2.3', '9')
                for version, build in [('1.2.3', '10'), ('1.2.4', '9')]:
                    with self.assertRaises(ValueError):
                        validate_payload(payload, 'windows', version, build)
            for data in [b'MZ', windows_fixture()[:700], bytes(1024)]:
                payload.write_bytes(data)
                with self.assertRaises(ValueError):
                    windows_version(payload)

    def test_stale_payload_is_rejected_before_keychain_or_feed_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            with (root/'Resources/Preview-Info.plist').open('rb') as f:
                version = plistlib.load(f)['CFBundleShortVersionString']
            payload = directory/f'ARose-ScreenSaver-v{version}-macOS-update.zip'
            with zipfile.ZipFile(payload, 'w') as archive:
                archive.writestr('ARose.app/Contents/Info.plist', plistlib.dumps({
                    'CFBundleShortVersionString': version, 'CFBundleVersion': '0'}))
            feed = directory/'appcast-macos.xml'
            feed.write_bytes(b'existing feed')
            with patch.object(sys, 'argv', ['create_appcasts.py', '--directory', tmp]), patch.object(module, 'prepare') as signer:
                with self.assertRaises(ValueError):
                    module.main()
                signer.assert_not_called()
            self.assertEqual(feed.read_bytes(), b'existing feed')

    def test_stale_windows_installer_cannot_partially_replace_mac_feed(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            with (root/'Resources/Preview-Info.plist').open('rb') as f:
                info = plistlib.load(f)
            version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
            with zipfile.ZipFile(directory/f'ARose-ScreenSaver-v{version}-macOS-update.zip', 'w') as archive:
                for path in ['ARose.app/Contents/Info.plist',
                             'ARose.app/Contents/PlugIns/ARoseExtension.appex/Contents/Info.plist']:
                    archive.writestr(path, plistlib.dumps(info))
            (directory/f'ARose-ScreenSaver-v{version}-Windows-x64-Setup.exe').write_bytes(
                windows_fixture(tuple(map(int, version.split('.'))) + (int(build) - 1,)))
            feed = directory/'appcast-macos.xml'
            feed.write_bytes(b'existing feed')
            with patch.object(sys, 'argv', ['create_appcasts.py', '--directory', tmp]), patch.object(module, 'prepare') as signer:
                with self.assertRaises(ValueError):
                    module.main()
                signer.assert_not_called()
            self.assertEqual(feed.read_bytes(), b'existing feed')

if __name__=='__main__':unittest.main()
