#!/usr/bin/env python3
"""Sign the staged Mac app for Developer ID distribution. Never uploads anything."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', required=True, help='Developer ID Application certificate name or SHA-1')
    args = parser.parse_args()
    # Reject an absent/incorrect identity before modifying any output.
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    if not any(args.identity in line and 'Developer ID Application:' in line for line in identities.splitlines()):
        raise SystemExit('A valid Developer ID Application identity is required')
    with tempfile.TemporaryDirectory(prefix='arose-sign-', dir='/private/tmp') as tmp:
        app = Path(tmp)/'ARose.app'
        run('ditto', '-x', '-k', ROOT/'dist/ARose.app.zip', tmp)
        # Sign nested executables and bundles inside out. Preserve Sparkle helper
        # sandbox entitlements, then explicitly apply the extension entitlements.
        targets = []
        for path in app.rglob('*'):
            if path.is_symlink():
                continue
            if path.is_dir() and path.suffix in {'.app', '.appex', '.xpc', '.framework'}:
                targets.append(path)
            elif path.is_file():
                with path.open('rb') as file:
                    magic = file.read(4)
                if magic in {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce'}:
                    targets.append(path)
        for target in sorted(targets, key=lambda path: len(path.parts), reverse=True) + [app]:
            command = ['codesign', '--force', '--sign', args.identity, '--options', 'runtime', '--timestamp']
            if target.suffix == '.appex':
                command += ['--entitlements', str(ROOT/'Resources/Extension.entitlements')]
            else:
                command += ['--preserve-metadata=entitlements']
            run(*command, target)
        run('codesign', '--verify', '--deep', '--strict', app)
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', app, ROOT/'dist/ARose.app.zip')
    print('Developer ID app archive prepared. Notarize and staple before packaging the DMG.')


if __name__ == '__main__':
    main()
