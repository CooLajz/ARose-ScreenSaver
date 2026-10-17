# ARose ScreenSaver

**English** | [Česky](README.cs.md)

A native recreation of the Amiga BlitzBlank ARose screen saver, with an optional modern rendering mode. Built with Swift/AppKit on macOS and C++/Win32/Direct2D on Windows; no emulator, network access, or account required.

<p align="center"><img src="Resources/ARose-icon.png" width="192" alt="ARose ScreenSaver icon"></p>

## Features

- **Original Amiga:** indexed colors, crisp bitmap points and the reconstructed animation sequence.
- **Modern:** smooth points at the display’s resolution, a continuous rainbow palette and adjustable glow.
- New installations default to **Modern, 80% glow and a long trail**. Updates preserve saved settings.
- English and Czech UI, selected from macOS language preferences; English fallback.
- Native `.saver` and a companion preview app with settings and full-screen playback.

## Availability

This repository is being prepared for its first public release. No public download is announced yet.

| Platform | Status | Intended download |
| --- | --- | --- |
| macOS | Implemented; public distribution preparation in progress | Universal ZIP with `.saver` and preview app |
| Windows | Initial x64 port; runtime acceptance pending | Native `.scr` in a ZIP with installation instructions |

The macOS deployment target is 13 or later. Both Apple Silicon and Intel architectures are built; manual validation has been performed on a Mac M2. Intel hardware and the full supported OS range have not been tested.

Future GitHub Releases can carry downloads for both platforms under one version. Development artifacts are **ad-hoc signed, not notarized** and are not a finished public installer. See the [release guide](docs/releases.md) for the outstanding distribution requirements.

## Build and run

Install Xcode and select its command-line tools, then run from the repository root:

```sh
./script/build_and_run.sh          # Build and launch the preview
./script/build_and_run.sh --build  # Build only
./script/test.sh                   # Run after building
./script/package_candidate.sh      # Package a local development candidate
```

Build logs are in `.build/build.log`. Clean installation archives are in `dist/`. Use the ZIPs rather than re-zipping loose bundles: managed Documents folders can add Finder metadata that invalidates signatures.

## Windows build and installation

See the [release guide](docs/releases.md) for Visual Studio/CMake build commands.
The Windows port includes `/s` full-screen mode, `/c` settings, `/p` embedded
system preview and `/w` an interactive window. The default style, glow and trail
match macOS. The Direct2D glow renderer is visually similar, not pixel-identical
to the Mac renderer. Settings follow Windows UI language preferences.

Extract the Windows ZIP into a permanent user folder, then right-click
`ARose.scr` → **Show more options** → **Install** to open Windows screen saver
settings. The current candidate is unsigned and has not yet passed manual
Windows acceptance. See [Windows installation notes](Windows/INSTALL.txt).

## Local macOS installation

1. Extract `dist/ARose.saver.zip` into Downloads.
2. Open `ARose.saver` in Finder and follow the macOS installation prompt. If no prompt appears, copy it into `~/Library/Screen Savers/` and reopen System Settings.
3. Select ARose in the screen saver settings. Their location varies by macOS version.
4. Extract `dist/ARose Preview.app.zip` to use the companion preview.

These locally signed builds may be blocked when transferred to another computer. A notarized public distribution is still pending; this project does not disable macOS security protections.

Preview shortcuts: **⌘ ,** settings, **⌘ F** full screen, **⌘ P** pause, **⌘ R** restart, **⌘ N** advance ten simulation seconds, **⌘ Q** quit.

## Known limitations

- The system **Options** button can stop displaying the configuration panel. Restarting System Settings may temporarily help. To configure through the companion app, keep the system’s animated ARose preview open, open the app’s settings, and save. A confirmation explicitly states whether the system host acknowledged the settings. Otherwise they are saved only in the preview app; retry while the system preview is running. This does not repair the macOS host bug.
  Local retesting on 17 October 2026 reproduced failure after closing and reopening the entire screen saver picker. ARose received the second request and returned fresh 460 × 450 content, but no dialog appeared. Explicit controller sizing and alternate modal-session dismissal did not resolve it and were reverted. The built-in Message saver passed the same sequence; this does not establish whether the remaining failure is in ARose integration or the legacy host. Configuration lifecycle tests do not cover that cross-process presentation.
- The system picker may display its generic thumbnail despite the bundled preview images; animated previews work.
- No frame-by-frame equivalence with physical or emulated Amiga hardware has been measured. Original saved-animation state is not implemented.

Tests exercise 600,000 simulation frames, settings validation, localization, actual saver-bundle loading, resizing and glow behavior. They do not replace manual testing inside System Settings or long-running performance checks.

## Origins and license

Original ARose by **Wolfgang Breyha and Michael Matzl, 1994–1995**. Its documentation credits Rose from After Dark as inspiration. The recreation uses control sequences transcribed from `BB.ARose020881`, internal version 1.2 (05 April 1995), distributed in `ARoseBlitz1.1`. Original binaries are not included. [Reconstruction notes (Czech)](docs/reconstruction.md) document the process and limitations.

New contributions are offered under [MIT](LICENSE), **only to the extent of rights held by their contributors**. This does not relicense the original control data or grant rights in derived material. See [third-party notices](THIRD_PARTY_NOTICES.md). Clarifying those rights remains a prerequisite for public distribution of the complete project.

## CPU debug overlay

Enable **Debug: show process CPU usage** in settings on either platform.
The bottom-right overlay samples once per second and is off by default.
Two values appear side by side: **1 core** uses 100% for one logical core and
can exceed 100%; **All cores** uses 100% for all logical cores combined.
For example, 300% and 75% represent the same process CPU time on four cores.
Performance and efficiency cores count equally: this measures CPU time, not
weighted computational throughput.
This measures process CPU time, not system load or GPU activity. On macOS it
includes the whole saver host process, potentially serving several views.
A dash is shown before the first measurement. Update both the Mac saver and
preview app, then reopen System Settings to load the new preference schema.

Modern mode renders both glow and sharp points through Metal on supported Macs, including when glow is off. A small precomputed coverage texture preserves Core Graphics antialiasing of fine points. Unavailable Metal falls back to CPU rendering. Image differences and benchmark limits are documented in [performance notes](docs/performance.md).

Windows preparation optimizations and remaining native runtime checks are recorded in the [Windows continuation guide](docs/windows-handoff.md). They do not establish a measured performance gain on Windows.

## Resume from last figure

Enable **Resume from last figure** to continue the pattern, rotation and color
phase on the next run, including after restarting the computer. This option is
off by default and works in both styles. State is saved on normal exit. macOS also checkpoints the first frame and every
second because its legacy host may omit the exit callback; Windows checkpoints
every 30 seconds. A forced termination can lose the latest interval.
Trails rebuild over the first 0.4 seconds rather than being stored as an image.
Previews reported as previews by the OS never update the saved position. Some
macOS versions run the System Settings thumbnail as a full saver; in that case
it shares the system saver bookmark. The standalone
macOS preview and Windows `/w` window keep their own separate position. Disabling
the option ignores the bookmark without deleting it. Invalid or unsupported
saved states are ignored. No files are sent over the network.

To start over, click **Forget saved figure**, then **Save**. This clears both
the saver and standalone preview bookmarks without changing the resume option.
**Cancel** preserves the original position.
