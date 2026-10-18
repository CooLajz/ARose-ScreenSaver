#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/test-images .build/ModuleCache
xcrun swiftc -O -module-cache-path .build/ModuleCache Sources/Core/*.swift Tests/main.swift -o .build/engine-tests
.build/engine-tests "$PWD/.build/test-images"
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/SettingsBridge/main.swift -o .build/settings-tests
.build/settings-tests
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/RetroRendering/main.swift -o .build/retro-render-tests
.build/retro-render-tests
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver \
    -import-objc-header Sources/Extension/ScreenSaverPrivate.h \
    Sources/Core/*.swift Sources/ScreenSaver/*.swift Sources/Extension/ARoseExtension.swift \
    Tests/Extension/main.swift -o .build/extension-tests
.build/extension-tests
xcrun clang -fobjc-arc -framework Cocoa -framework ScreenSaver Tests/BundleSmoke.m -o .build/bundle-smoke
TEST_BUNDLE_DIR="$(mktemp -d /private/tmp/arose-bundle-test.XXXXXX)"
trap 'rm -rf "$TEST_BUNDLE_DIR"' EXIT
ditto -x -k dist/ARose.saver.zip "$TEST_BUNDLE_DIR"
codesign --verify --strict "$TEST_BUNDLE_DIR/ARose.saver"
.build/bundle-smoke "$TEST_BUNDLE_DIR/ARose.saver" --localization cs -AppleLanguages '(cs)'
.build/bundle-smoke "$TEST_BUNDLE_DIR/ARose.saver" --localization en -AppleLanguages '(en)'
.build/bundle-smoke "$TEST_BUNDLE_DIR/ARose.saver" --localization en -AppleLanguages '(de)'
.build/bundle-smoke "$TEST_BUNDLE_DIR/ARose.saver" "$PWD/.build/test-images"
