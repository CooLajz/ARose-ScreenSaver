# Windows continuation

## Baseline prepared on macOS, 17 October 2026

The Windows renderer remains Direct2D. No new graphics API, shader, external
runtime or elevation requirement has been introduced. The Windows
changes are independent of the Mac's full Metal renderer.

- `Windows/PreparedFrame.h` prepares interpolation, pixel positions, age opacity
  and halo indices once per window redraw, reused by the glow and point passes.
  Fixed storage covers all 20 × 96 points. Original order, float conversions,
  radial gradients, colors and ellipse calls remain unchanged.
- Glow brushes are prepared before starting the shared animation clock. Repeated
  paints reuse them; device-target recreation invalidates and rebuilds them.
- The animation clock is restarted after initial preparation, including reset or
  settings changes. Monitor presentation still uses one compositor wait after
  all windows. PAL simulation and display interpolation are unchanged.
- Retro palette lookup is cached until the palette setting changes.

## Evidence and limits

`script/test_windows_core.sh` passes on macOS: 600,000 original simulation frames,
50 Hz pacing/interpolation, 24 Swift/C++ parity checkpoints, and 2,699,520 prepared
points compared exactly to the former per-pass calculation. Cases include
startup/history growth, all selected interpolation phases, short/long trails,
landscape/portrait/4K sizes, and clearing an empty history.

Cross-compilation builds the Windows x64 `.scr`; this is build evidence, not
Direct2D pixel equality, successful Windows execution, improved CPU usage or
security certification. The new CMake `rendering-data` test is wired into the
existing Windows CI job, but that job has not been run on GitHub here.
CMake was unavailable on the macOS preparation host, so the CMake/CTest route
itself remains unverified there; portable tests were compiled directly with
Clang and the full Windows saver was cross-compiled with Zig.

## Continue on Windows

The private development repository is `CooLajz/ARose-ScreenSaver`. Authenticate
with an account that has access, then clone it:

```powershell
gh repo clone CooLajz/ARose-ScreenSaver
cd ARose-ScreenSaver
```

Build outputs and original Amiga binaries are excluded. GitHub Actions builds
are manual-only; cloning or pushing does not trigger a build.

Use Visual Studio 2022 C++ desktop tools, Windows SDK, CMake and Python 3:

```powershell
python script/generate_windows_tables.py --check
cmake -S Windows -B build-windows -A x64
cmake --build build-windows --config Release
ctest --test-dir build-windows -C Release --output-on-failure
python script/check_engine_parity.py --executable build-windows/Release/arose-engine-tests.exe
& ./build-windows/Release/ARose.scr /w
```

Compare the previous Windows candidate and this one at identical resolution,
DPI, style, speed, trail and glow. Measure cold startup and several minutes of
steady animation, with CPU overlay both off and on. Exercise glow 0/80/100,
Original palettes, F1 save/cancel, reset, mixed-DPI multi-monitor display,
`/s`, `/c`, `/c:<HWND>`, embedded `/p <HWND>`, resize and display sleep/recovery.
The smoke test is not sufficient for those acceptance checks.

If CPU remains significant, profile Direct2D submissions before replacing the
renderer. A future batched sprite/Direct3D implementation should retain this
renderer as its image reference. Match Windows' current blending and coverage;
do not silently substitute the Mac's additive glow or change interpolation.

## First public repository/release

The repository is private for continued development. No public Release is
being published. Contact with Wolfgang Breyha has been established; permission
for public distribution is still awaiting his substantive response. Resolve
and record the original-material licensing scope described in
[third-party notices](../THIRD_PARTY_NOTICES.md) before publishing the complete
project. New contributions alone have the selected MIT license. Follow
[release preparation](releases.md) for remote/upstream setup, signing, CI and
platform-specific download assets. Preserve the distinction between a locally
built candidate and a Windows-tested/publicly signed release.

## Saved-figure continuation

The optional `Resume from last figure` setting defaults to off. `FigureV1` in
`HKCU\Software\CooLajz\ARose` stores a versioned array of 24 signed 64-bit values
in a single registry value on exit and every 1,500 simulation steps. `/w` uses
`PreviewFigureV1`; `/p` and `/t` never read or write bookmarks. The shape and color
phase resume exactly, while the trail rebuilds over up to 20 steps.

Portable tests compare 1,000 subsequent steps after restoration in both modes,
including point/color identity, retro pixels after trail warm-up and invalid
state rejection. The updated Windows executable cross-compiles on macOS.
On Windows, additionally verify `/s` exit/restart, persistence across reboot,
checkbox save/cancel, `/p` isolation, the separate `/w` bookmark, and a forced
termination after 30 seconds. Registry persistence and the dialog still need
native Windows runtime verification.
