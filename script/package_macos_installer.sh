#!/bin/bash
# Build a drag-to-Applications DMG with a persistent Finder layout.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(python3 script/release_version.py --format version)"
STAGING="$(mktemp -d /private/tmp/arose-dmg.XXXXXX)"
MOUNT="$STAGING/mount"
cleanup() {
    if mount | grep -Fq " on $MOUNT "; then hdiutil detach "$MOUNT" >/dev/null || true; fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
mkdir -p "$STAGING/content/.background" "$STAGING/content/.documentation" dist/releases
if [[ ! -x .build/dmg-tools/bin/python3 ]]; then python3 -m venv .build/dmg-tools; fi
.build/dmg-tools/bin/python3 -m pip --disable-pip-version-check -q install 'ds-store==1.3.1' 'mac-alias==2.2.2'
ditto -x -k 'dist/ARose.app.zip' "$STAGING/content"
codesign --verify --deep --strict "$STAGING/content/ARose.app"
ln -s /Applications "$STAGING/content/Applications"
cp docs/INSTALL-macOS.txt LICENSE THIRD_PARTY_NOTICES.md "$STAGING/content/.documentation/"
xcrun swift -module-cache-path .build/ModuleCache script/dmg/background.swift "$STAGING/content/.background/background.png"
hdiutil create -ov -fs HFS+ -format UDRW -volname 'ARose' -srcfolder "$STAGING/content" "$STAGING/layout.dmg" >/dev/null
hdiutil attach -nobrowse -mountpoint "$MOUNT" "$STAGING/layout.dmg" >/dev/null
.build/dmg-tools/bin/python3 script/dmg/layout.py "$MOUNT"
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$STAGING/layout.dmg" -format UDZO -ov -o "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-universal.dmg" >/dev/null
hdiutil verify "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-universal.dmg" >/dev/null
cp 'dist/ARose.app.zip' "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-update.zip"
cp dist/ARose.saver.zip "dist/releases/ARose-ScreenSaver-v${VERSION}-macOS-standalone.saver.zip"
echo 'macOS installer, update archive and standalone saver prepared in dist/releases/'

for asset in "ARose-ScreenSaver-v${VERSION}-macOS-universal.dmg" "ARose-ScreenSaver-v${VERSION}-macOS-update.zip" "ARose-ScreenSaver-v${VERSION}-macOS-standalone.saver.zip"; do
    (cd dist/releases && shasum -a 256 "$asset" > "$asset.sha256")
done
