# Developing ARose ScreenSaver

**English** | [Česky](development.cs.md) · [User documentation](../README.md)

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/Core/` | Swift simulation, original control tables and shared math. |
| `Sources/ScreenSaver/` | Shared Mac view, settings, CPU readout and Metal rendering. |
| `Sources/Extension/` | Embedded macOS screen saver extension adapter. |
| `Sources/Preview/` | Companion app entry point. |
| `Sources/Updates/` | Installation lifecycle and update integration. |
| `Windows/` | Native C++ engine, Win32 UI, Direct3D 11 renderer, Direct2D fallback and installer. |
| `Tests/`, `script/` | Regression checks, parity checks, build and packaging tools. |

The Mac app, extension and classic `.saver` share rendering and configuration code. They use independent preferences and figure bookmarks. The extension uses the private ScreenSaver extension interface; review [the adapter and runtime acceptance notes](macos-extension.md) before changing its lifecycle.

The classic `.saver` remains buildable for development, but is not a planned public release download. Public Mac installation uses the app DMG; its update ZIP and appcast remain necessary. Windows installer and standalone `.scr` distribution are retained. Some existing packaging scripts still produce legacy Mac artifacts: the release asset selection needs to be aligned before publication.

## Build on macOS

Install Xcode with the macOS SDK and select its command-line tools. Run from the repository root:

```sh
./script/build_and_run.sh          # Build and launch ARose
./script/build_and_run.sh --build  # Build without launching
./script/build_and_run.sh --verify # Build, launch and check the process
./script/test.sh                   # Run after building
./script/test_windows_core.sh      # Compare Swift and C++ engine behavior
./script/package_macos_installer.sh # Create the DMG and update archive
```

`ARose.xcodeproj`, scheme `ARose`, builds the app, embedded extension and classic saver. The app and classic saver build minimum is macOS 13; the extension requires macOS 14. Outputs include arm64 and x86_64. Build minimums are not evidence of runtime acceptance on every OS or Intel hardware.

Logs are in `.build/build.log`; clean archives are in `dist/` and release payloads in `dist/releases/`. Packaging removes problematic Finder metadata from staged outputs and currently uses ad-hoc signing. Transfer the generated archives rather than re-zipping loose bundles inside managed Documents folders, which can add metadata and invalidate signatures.

The DMG layout uses pinned Python build dependencies installed into `.build/dmg-tools`. Updater dependencies are fetched with pinned hashes. The original private Amiga source archive must stay outside the repository.

## Build on Windows

Install Visual Studio 2022 C++ desktop tools, Windows SDK, CMake and Python 3. From the repository root:

```powershell
./script/build_windows.ps1
./script/package_windows.ps1
```

The first script builds, runs CTest and checks engine parity. Packaging also needs **Inno Setup 6.3+ on the build machine**. None of these development tools are required by end users. The MSVC runtime is linked statically; the updater library ships with the companion app.

For individual steps:

```powershell
python script/generate_windows_tables.py --check
cmake -S Windows -B build-windows -A x64
cmake --build build-windows --config Release
ctest --test-dir build-windows -C Release --output-on-failure
python script/check_engine_parity.py --executable build-windows/Release/arose-engine-tests.exe
```

Optional Mac/Linux cross-compilation uses `script/build_windows_cross.sh` with `ZIG_BIN` pointing to Zig 0.15.2. It produces binaries, but does not execute native Windows acceptance tests. The host-side resource compiler on Mac requires macOS 15+.

## Preserve behavior when contributing

The simulation follows the original 50 Hz timing. Modern rendering can interpolate between simulation states for smoother display refresh; it must not change the underlying figure sequence. Retro keeps integer quantization, palettes and trail erasure. Resolution scaling changes presentation, not the simulation tables.

Keep mathematical and non-rendering behavior aligned on both platforms. Generated Windows tables come from the Swift data; use `script/generate_windows_tables.py` rather than editing them independently. Preserve Czech and English UI, user documentation and the separation of app/saver preferences.

Automated checks cover long simulations, engine parity, saved figures, rendering, settings, localization, actual bundle loading and extension controllers. They do not replace manual testing of full-screen playback, multiple displays, high refresh rates, installation or system-host lifecycle. Hardware-dependent image differences must be examined before changing the appearance to satisfy a tolerance.

For CPU diagnostics, enable the process CPU overlay. “1 core” assigns 100% to one logical core and can exceed 100%; “All cores” divides by the logical processor count. This is CPU time, not weighted core performance or GPU load. A system host may serve multiple views.

## Technical references

- [Original reconstruction and provenance (Czech)](reconstruction.md)
- [macOS extension and lifecycle acceptance](macos-extension.md)
- [macOS rendering and performance](performance.md)
- [Windows rendering and performance](windows-performance.md)
- [Windows native testing handoff](windows-handoff.md)
- [Updater architecture and signing](updates.md)
- [Release preparation](releases.md)
- [Third-party notices and permission scope](../THIRD_PARTY_NOTICES.md)

Public distribution requires final signing, macOS notarization and native acceptance. Apple Developer ID signing and the Sparkle/WinSparkle update signatures serve different purposes. Keep private keys and credentials outside the repository. Building or packaging never constitutes authorization to publish a release.
