#!/bin/bash
# CPU render benchmark in a bitmap test host; never launches or changes the installed saver.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:-.build/performance/current-images}"
mkdir -p .build/performance .build/ModuleCache
xcrun swiftc -O -module-cache-path .build/ModuleCache -framework ScreenSaver \
    Sources/Core/*.swift Sources/ScreenSaver/*.swift Tests/Performance/main.swift \
    -o .build/performance/benchmark
.build/performance/benchmark "$OUTPUT" "${3:-modern}"
if [[ -n "${2:-}" ]]; then
    xcrun swiftc -O -module-cache-path .build/ModuleCache Tests/ImageComparison/main.swift -o .build/performance/compare
    .build/performance/compare "$2" "$OUTPUT"
fi
