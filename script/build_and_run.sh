#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry) ;; *) echo 'Použití: script/build_and_run.sh [--build|--verify|--debug|--logs|--telemetry]' >&2; exit 2;; esac
if [[ "$MODE" != --build ]]; then pkill -x 'ARose' >/dev/null 2>&1 || true; fi
mkdir -p .build dist
python3 script/fetch_updaters.py macos
xcodebuild -project ARose.xcodeproj -scheme ARose -configuration Release \
    -derivedDataPath "$ROOT_DIR/.build" -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build > .build/build.log 2>&1 || {
    grep -n -C 3 "error:" .build/build.log || true
    tail -80 .build/build.log; exit 1;
}
# File Provider may later reattach FinderInfo inside Documents. Keep clean ZIPs
# assembled outside that directory as the durable installation artifacts.
STAGING_DIR="$(mktemp -d /private/tmp/arose-package.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
for name in 'ARose.saver' 'ARose.app'; do
    ditto --norsrc --noextattr ".build/Build/Products/Release/$name" "$STAGING_DIR/$name"
    if [[ "$name" == 'ARose.app' ]]; then
        mkdir -p "$STAGING_DIR/$name/Contents/Frameworks" "$STAGING_DIR/$name/Contents/Library/LaunchAgents"
        ditto --norsrc --noextattr .build/updaters/Sparkle.framework "$STAGING_DIR/$name/Contents/Frameworks/Sparkle.framework"
        cp Resources/LaunchAgents/*.plist "$STAGING_DIR/$name/Contents/Library/LaunchAgents/"
        codesign --force --sign - --timestamp=none --entitlements Resources/Extension.entitlements "$STAGING_DIR/$name/Contents/PlugIns/ARoseExtension.appex"
        codesign --verify --strict "$STAGING_DIR/$name/Contents/PlugIns/ARoseExtension.appex"
        cp .build/updaters/LICENSE "$STAGING_DIR/$name/Contents/Resources/Sparkle-LICENSE.txt"
    fi
    cp LICENSE THIRD_PARTY_NOTICES.md "$STAGING_DIR/$name/Contents/Resources/"
    codesign --force --sign - --timestamp=none "$STAGING_DIR/$name"
    codesign --verify --deep --strict "$STAGING_DIR/$name"
    ditto -c -k --norsrc --noextattr --keepParent "$STAGING_DIR/$name" "dist/$name.zip"
    ditto --norsrc --noextattr "$STAGING_DIR/$name" "dist/$name"
    xattr -dr com.apple.FinderInfo "dist/$name" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "dist/$name" 2>/dev/null || true
done
echo 'Sestaveny balíčky a instalační ZIP archivy ve složce dist/'
case "$MODE" in
    --build) ;;
    --debug) lldb -- 'dist/ARose.app/Contents/MacOS/ARose' ;;
    --logs|--telemetry) open -n 'dist/ARose.app'; /usr/bin/log stream --info --style compact --predicate 'process == "ARose"' ;;
    --verify) open -n 'dist/ARose.app'; sleep 2; pgrep -x 'ARose' >/dev/null; echo 'Aplikace běží.' ;;
    run) open -n 'dist/ARose.app' ;;
esac
