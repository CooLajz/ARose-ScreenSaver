#!/bin/bash
# Assemble a local development candidate, never publish it automatically.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Saver-Info.plist)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
STAGING_DIR="$(mktemp -d /private/tmp/arose-candidate.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
LABEL="${1:-development}"
[[ "$LABEL" =~ ^[a-z0-9-]+$ ]] || { echo 'Invalid package label' >&2; exit 1; }
NAME="ARose-ScreenSaver-v${VERSION}-macOS-universal-${LABEL}"
mkdir -p "$STAGING_DIR/$NAME" dist/releases
for bundle in 'ARose.saver' 'ARose Preview.app'; do
    ditto -x -k "dist/$bundle.zip" "$STAGING_DIR/$NAME"
    codesign --verify --strict "$STAGING_DIR/$NAME/$bundle"
    INFO="$STAGING_DIR/$NAME/$bundle/Contents/Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" == "$VERSION" ]] || { echo 'Rebuild: bundle version mismatch' >&2; exit 1; }
    EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")"
    ARCHS="$(lipo -archs "$STAGING_DIR/$NAME/$bundle/Contents/MacOS/$EXECUTABLE")"
    [[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo 'Expected universal bundle' >&2; exit 1; }
done
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGING_DIR/$NAME/"
cp docs/INSTALL-macOS.txt "$STAGING_DIR/$NAME/INSTALL.txt"
ditto -c -k --norsrc --noextattr --keepParent "$STAGING_DIR/$NAME" "dist/releases/$NAME.zip"
(cd dist/releases && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
printf 'Development candidate: dist/releases/%s.zip\n' "$NAME"
