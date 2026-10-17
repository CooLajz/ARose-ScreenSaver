#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET_DIR="$PWD/.build/ARose.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/ARose-icon.png --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/ARose-icon.png --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o Resources/ARose.icns
