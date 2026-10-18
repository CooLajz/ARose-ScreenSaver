import base64
import plistlib
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root/'script'))
spec = importlib.util.spec_from_file_location('appcasts', root/'script/create_appcasts.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AppcastTests(unittest.TestCase):
    def test_both_platforms_keep_signature_length_build_and_fixed_url(self):
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp)/'ARose-update.zip'
            payload.write_bytes(b'fixture')
            signature = base64.b64encode(bytes(range(64))).decode()
            for platform in ['macos', 'windows']:
                xml = ET.fromstring(module.appcast('1.2.3', '9', platform, payload, signature))
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

if __name__=='__main__':unittest.main()
