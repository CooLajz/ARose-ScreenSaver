#!/bin/bash
# Interactive A/B preview; does not register a saver or write user preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache
STAGING_DIR="$(mktemp -d /private/tmp/arose-light-preview.XXXXXX)"
APP="$STAGING_DIR/ARose Light Preview.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver \
    Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/LightComparison/main.swift \
    -o "$APP/Contents/MacOS/ARoseLightPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cz.coolajz.ARose.LightComparison</string><key>CFBundleExecutable</key><string>ARoseLightPreview</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$APP"
open -n "$APP"
printf 'Porovnání: %s\nPauza a pokračování: mezerník nebo tlačítko v záhlaví.\n' "$APP"
