#!/bin/bash
# Requires a local Metal-capable Mac and permission to access the GPU/window server.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver \
    Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/MetalRendering/main.swift -o .build/metal-tests
.build/metal-tests .build/metal-images
if [[ "${1:-}" == --window ]]; then
    APP="$PWD/.build/Metal Window.app"
    mkdir -p "$APP/Contents/MacOS"
    xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver \
        Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/MetalWindow/main.swift -o "$APP/Contents/MacOS/MetalWindow"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cz.coolajz.ARose.MetalWindowTest</string><key>CFBundleExecutable</key><string>MetalWindow</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
    STAGING="$(mktemp -d /private/tmp/arose-metal-window.XXXXXX)"
    trap 'rm -rf "$STAGING"' EXIT
    ditto --norsrc --noextattr "$APP" "$STAGING/Metal Window.app"
    APP="$STAGING/Metal Window.app"
    codesign --force --sign - "$APP"
    # Keep atomic writes by the GUI test outside File Provider-managed Documents.
    RESULT="$STAGING/result.txt"
    printf "Test window: %s\n" "$APP"
    open -n -W "$APP" --args "$RESULT"
    rg -q '^OK:' "$RESULT"
    cat "$RESULT"
fi
