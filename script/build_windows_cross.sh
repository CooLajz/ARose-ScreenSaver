#!/bin/bash
# Optional cross-build on macOS/Linux with an already installed Zig 0.15.2.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
ZIG_BIN="$(command -v "${ZIG_BIN:-zig}")"
if [[ "$ZIG_BIN" == */* ]]; then ZIG_BIN="$(cd "$(dirname "$ZIG_BIN")" && pwd)/$(basename "$ZIG_BIN")"; fi
export ZIG_GLOBAL_CACHE_DIR="$ROOT_DIR/.build/zig-cache"
mkdir -p .build/windows dist/windows
python3 script/generate_windows_tables.py --check
if [[ "$(uname -s)" == Darwin ]]; then
    # Zig 0.15.2's auto-built resource compiler cannot link against some newer
    # macOS SDKs. Give this host-side helper an explicit deployment target.
    ZIG_LIB="${ZIG_LIB_DIR:-$(dirname "$ZIG_BIN")/lib}"
    HOST_ARCH="$(uname -m)"
    [[ "$HOST_ARCH" != arm64 ]] || HOST_ARCH=aarch64
    "$ZIG_BIN" build-exe -target "$HOST_ARCH-macos.15.0" -lc -O ReleaseFast --dep aro \
        -Mroot="$ZIG_LIB/compiler/resinator/main.zig" -Maro="$ZIG_LIB/compiler/aro/aro.zig" \
        -femit-bin="$ROOT_DIR/.build/windows/resinator" -L "$(xcrun --show-sdk-path)/usr/lib"
    (cd Windows && "$ROOT_DIR/.build/windows/resinator" "$ZIG_LIB" /fo "$ROOT_DIR/.build/windows/ARose.res" ARose.rc)
else
    (cd Windows && "$ZIG_BIN" rc /fo "$ROOT_DIR/.build/windows/ARose.res" ARose.rc)
fi
"$ZIG_BIN" c++ -target x86_64-windows-gnu -std=c++17 -O2 -Wall -Wextra -ffp-contract=off \
    -DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0a00 -municode -Wl,--subsystem,windows \
    Windows/main.cpp .build/windows/ARose.res -ld2d1 -ldwmapi -ldwrite -lcomctl32 -lshell32 -ladvapi32 -luser32 -lgdi32 \
    -ld3d11 -ldxgi -ld3dcompiler -lwindowscodecs -lole32 \
    -o dist/windows/ARose.scr
printf '%s\n' 'Built dist/windows/ARose.scr (Windows x64, unsigned; runtime testing still required).'
