# Building and releasing ARose ScreenSaver

Suggested repository name: **ARose-ScreenSaver**. Product name: **ARose ScreenSaver**.
One GitHub release can contain independent macOS and Windows downloads. Do not
advertise a platform as tested based solely on successful cross-compilation.

## Current status

- Native macOS saver and preview app; universal arm64/x86_64.
- Native Windows C++/Win32 port with Direct3D 11 Modern rendering and Direct2D
  fallback, native `.scr`, embedded preview,
  settings, multi-monitor windows, and English/Czech UI. Primary target: Windows
  11 x64. Native MSVC builds, six tests and local GPU/CPU measurements have passed.
  Full Windows acceptance remains pending; see [Windows continuation](windows-handoff.md)
  and [performance measurements](windows-performance.md).
- New-code MIT license selected. Original data and derivative rights remain
  excluded and unresolved; see [third-party notices](../THIRD_PARTY_NOTICES.md).
- macOS local packages use ad-hoc signing. Windows candidates are unsigned.
- CI builds development candidates only. It neither creates nor publishes a
  GitHub Release and has no write permission. The workflow must be verified on
  GitHub after repository creation; a local test is not a completed CI run.

## Local builds

macOS (Xcode required):

```sh
./script/build_and_run.sh --build
./script/test.sh
./script/test_windows_core.sh
./script/package_candidate.sh
```

Windows (Visual Studio 2022 C++ desktop tools, Windows SDK, CMake and Python 3):

```powershell
python script/generate_windows_tables.py --check
cmake -S Windows -B build-windows -A x64
cmake --build build-windows --config Release
ctest --test-dir build-windows -C Release --output-on-failure
python script/check_engine_parity.py --executable build-windows/Release/arose-engine-tests.exe
./script/package_windows.ps1
```

The MSVC runtime is linked statically; the saver uses built-in Windows APIs.
No .NET runtime is required. An optional `script/build_windows_cross.sh` accepts
`ZIG_BIN` pointing to an installed Zig 0.15.2 for a Windows x64 cross-build (macOS 15+ for the host-side resource compiler).
Cross-compilation does not execute Windows tests.

Candidate ZIPs contain their installation instructions and license notices;
SHA-256 sidecar files support download-integrity checks. Candidate filenames
include `development` to distinguish them from future public releases.

## Before the first public publication

1. Resolve and document permission for the transcribed original control data
   and reconstructed portions. MIT for new contributions does not settle this.
2. Inspect the source tree for personal paths, private files and credentials.
   Build output, local Codex state and signing materials are ignored.
3. Complete Windows acceptance tests below, and macOS checks on Apple Silicon
   and Intel if claiming both have been tested.
4. Obtain the appropriate distribution identities. The existing Apple
   Development identity is not a Developer ID Application certificate.
5. Create the authorized public GitHub repository, configure `origin`, push the
   intended branch with `-u`, and verify both `git remote -v` and `git branch -vv`.
   Merely running `git init` does not complete repository setup.

## macOS public distribution

Use Developer ID Application signing, a secure timestamp and an appropriate
hardened-runtime configuration for the preview app; verify the screen saver
bundle in its actual system host. Submit the intended distribution archive to
Apple with `notarytool`, inspect the result, staple tickets where supported,
and validate on a clean Mac after downloading the final artifact. Test the
`.saver` installation and companion app independently. If a `.pkg` is added,
it requires its own suitable installer signature and testing.

No public signing automation is enabled yet: it needs the proper certificate,
notarization credentials and successful host validation. Keep credentials in
the signing machine's Keychain or appropriately scoped CI secrets, never in
this repository. Do not turn off Gatekeeper to make the release appear ready.

## Windows acceptance and distribution

- Test `/s`, `/c`, `/c:<HWND>`, `/p <HWND>` and the screen saver dialog's small
  preview, including resizing/closing its parent. `/w` is an interactive preview;
  `/t` is a short windowed smoke run for CI.
- Confirm Original/Modern, all palettes, trail lengths and speeds, glow 0/80/100,
  save/cancel, persistence after restart, Czech and English UI and fallback.
- Test one and multiple displays, mixed DPI, portrait screens and monitor changes.
- Check smooth animation, GPU/CPU load, memory over a long session, and recovery
  after display sleep. Modern mode batches Direct2D-generated textures through
  Direct3D 11 with source-over alpha blending. Its Direct2D fallback is retained;
  neither path is pixel-identical to the Mac's additive renderer.
- Verify keyboard/mouse exit from full screen. Verify Windows still enforces
  the configured lock/password policy; the saver never implements passwords.
- Install from an extracted ZIP in a stable user folder via the native `.scr`
  Install command. Change to another saver before deleting it to uninstall.
- For public distribution, arrange Authenticode signing and timestamping and
  test the downloaded signed file. Signing does not guarantee SmartScreen
  reputation; do not claim it removes every warning. Corporate policies may
  disallow third-party savers.

## Release process

Use a single version tag, e.g. `v1.0.4`, after matching versions in both macOS
Info.plists and Windows resource, manifest, and CMake files. Packaging reads the macOS version and rejects a mismatched Windows binary. Current
`1.0.3` describes the local development baseline, not an already published release.

Create a **draft** GitHub Release at a tested commit. Attach final signed and
validated packages, checksums and bilingual installation notes. Suggested names:

- `ARose-ScreenSaver-v1.0.4-macOS-universal.zip`
- `ARose-ScreenSaver-v1.0.4-Windows-x64.zip`

Review the exact assets and notes before publishing the draft. GitHub-generated
source archives are not installers. Once published, link README downloads to
the real release URL. Do not create a download badge for an unavailable release.

References: [GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Windows screen saver installation](https://learn.microsoft.com/en-us/windows/win32/devnotes/scrnsave-exe).

## Installer and updater additions

See [the current installation/update workflow](updates.md) for DMG/EXE packaging,
standalone assets, Ed25519 signing, appcast generation and required native upgrade
acceptance. These supersede the ZIP-only asset suggestions above. Public release
publication remains a separate explicit operation.
