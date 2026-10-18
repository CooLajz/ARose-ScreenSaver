#!/bin/bash
# Build a DMG with a per-user installer inside the companion app.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(python3 script/release_version.py --format version)"
STAGING="$(mktemp -d /private/tmp/arose-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/content" dist/releases
ditto -x -k 'dist/ARose Preview.app.zip' "$STAGING/content"
codesign --verify --deep --strict "$STAGING/content/ARose Preview.app"
cp docs/INSTALL-macOS.txt "$STAGING/content/INSTALL.txt"
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGING/content/"
hdiutil create -ov -format UDZO -volname 'ARose ScreenSaver' -srcfolder "$STAGING/content" "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-universal.dmg"
cp 'dist/ARose Preview.app.zip' "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-update.zip"
cp dist/ARose.saver.zip "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-standalone.saver.zip"
echo 'macOS installer, update archive and standalone saver prepared in dist/releases/'

for asset in "ARose-ScreenSaver-v${VERSION}-macOS-universal.dmg" "ARose-ScreenSaver-v${VERSION}-macOS-update.zip" "ARose-ScreenSaver-v${VERSION}-macOS-standalone.saver.zip"; do
    (cd dist/releases && shasum -a 256 "$asset" > "$asset.sha256")
done
