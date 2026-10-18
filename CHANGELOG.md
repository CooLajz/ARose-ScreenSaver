# Changelog

## Unreleased — public distribution preparation

- Restart reused macOS full-screen views when figure continuation is off; restore
  bookmarks when enabled without resetting active starts or thumbnail playback.
- Preserve custom Windows installation paths during silent updates. Clear only
  matching ARose selections in loaded user profiles during administrative uninstall,
  including when elevation uses another account; leave offline profiles untouched.

- Prevent the stopped-thumbnail poster from appearing during macOS full-screen
  startup. Wait for real geometry before the first Metal submission and preserve
  animation timing across repeated host start requests.
- Refresh paused macOS previews after manual advance, restart and saved settings.
- Preserve the Windows preview figure and pause state when cancelling settings;
  keep standard system keyboard shortcuts such as Alt+F4 working.
- Restore a missing Windows weekly update task when its saved opt-in survives
  reinstall, and report registration failures instead of showing a working opt-in.
- Verify app/extension and Windows installer versions and builds before signing
  update feeds; reject stale companion binaries when packaging Windows releases.

- Render an initial still image for stopped extension views requested by System
  Settings, preventing a black thumbnail after Options or app replacement.
  Keep the actual simulation and saved figure unchanged while generating it.
- Automatically refresh cached screen saver hosts once after app replacement,
  including same-build reinstall and Sparkle background relaunch; retry Settings
  reopening and defer recovery during locked/idle sessions.

- Package ARose.app with a native screen saver extension and a drag-to-Applications
  DMG. Keep the standalone .saver distribution and share rendering/settings code.
- Use the system ScreenSaverConfigurationViewController and its completion
  lifecycle for extension Options; verify repeated picker reopening on macOS 27.0.1.
- Update the companion menu, registration, packaging and documentation for app
  installation without copying a legacy saver into the user's Library.

- Cache the macOS Metal CPU overlay per in-flight slot; repaint only when
  displayed text, view size or backing scale changes. Update text once per second.
  Verify cached pixels and invalidation on value and size changes.

- Render macOS retro mode at native backing resolution with screen-centered
  coordinates and a screen-dependent initial radius, keeping table radii fixed.
  Preserve figure state and clear trails when the drawable size changes.

- Correct macOS and Windows rotation to render twice the stored global angle and
  advance point phase on the first step, matching the original implementation.
  Add Windows opening-phase checks at all five speeds and refresh parity snapshots.

- Move macOS Modern interpolation and sprite preparation to a Metal compute
  shader with a device-RGB rainbow lookup and reusable endpoint buffers.
  Compare 45 GPU readbacks against CPU interpolation and benchmark preparation.

- Synchronize macOS 14+ Modern presentation to the display, including 120 Hz,
  with position and wrapped-hue interpolation between unchanged PAL steps.
  Keep retro/older macOS timing and test 60/120/144 Hz simulation equivalence.

- Batch Windows Modern rendering through Direct3D 11 using native Direct2D
  coverage and halo textures. Preserve simulation timing and source-over draw
  order, retain Direct2D fallback, and identify the renderer in the CPU overlay.
- Add reproducible Windows build/benchmark scripts and document Radeon laptop
  measurements: approximately 60 fps at 0.47% all-core CPU without the debug
  overlay and 0.72% with it, down from about 5% for the Direct2D path. Record
  the hardware, settings, measurement duration and image differences in
  `docs/windows-performance.md`; these are local results, not battery estimates.
- Fix duplicate MSVC manifests and locale-dependent Windows table validation.
  Pass six native tests, including 72 Direct2D and 72 hardware GPU image
  comparisons, renderer transitions, resize, overlay and device recreation,
  plus the 24 Swift/C++ parity checkpoints. Full Windows acceptance is pending.

- Add a CS/EN saved-figure reset button on macOS and Windows, applied only on
  Save. Clear both bookmarks and prevent stale instances from restoring old
  progress. Test Save/Cancel and simulation at one trillion frames.

- Transfer macOS bookmark ownership when a retained legacy view stops receiving
  animation frames, and prevent its late stop from overwriting newer progress.

- Save macOS figure checkpoints after the first frame and every second so short
  legacy-host sessions survive missing stop callbacks. Document host-misreported
  previews and add a regression test that deliberately omits stopAnimation.

- Add optional saved-figure continuation on macOS and Windows, with CS/EN
  settings, versioned validated state and 30-second checkpoints. Isolate
  standalone preview bookmarks and exclude embedded previews. Test exact
  simulation continuation and macOS saver lifecycle without changing rendering.

- Prepare Windows interpolated point data once for both rendering passes with
  fixed-capacity storage; cache retro palettes and initialize glow brushes before
  starting the animation clock. Keep Direct2D drawing and blending unchanged.
  Add portable draw-data equivalence tests and a Windows continuation guide.

- Exclude initial GPU setup from animation elapsed time and reserve trail buffers
  at full capacity to avoid repeated allocations during startup. Exercise cold
  starts in the window test and write its results outside File Provider folders.

- Render Modern points, cores and glow with Metal on macOS, including glow off.
  Preserve tiny-circle coverage with a Core Graphics subpixel atlas; reuse GPU
  instance buffers and restrict CPU debug drawing to a small corner texture.
  Keep the original simulation and CPU fallback. Add image, empty-scene and
  cropped-label regression checks against the previous hybrid renderer.

- Reduce macOS Modern renderer color allocations using a bounded trail cache
  and context opacity. Add an offscreen CPU benchmark and exact pixel comparison
  utility; keep geometry, rendering order, glow quality and simulation unchanged.

- Add an opt-in process CPU overlay to macOS and Windows settings, refreshed
  once per second, with 100% representing all available logical cores combined.

- Improve Windows frame pacing: present all windows before one compositor wait,
  retain the 50 Hz simulation and interpolate Modern mode between simulation
  frames. Glow intensity is unchanged. A new laptop comparison is pending.

- Add the initial Windows x64 screen saver port: original and modern renderers,
  adjustable glow, native configuration and preview integration, multi-monitor
  windows, and English/Czech settings.
- Compare C++ and Swift engines using pixel hashes, palette data and modern
  coordinates; generate Windows control tables from the Swift source.
- Add English and Czech project documentation, new-code MIT licensing scope,
  third-party notices, development packaging and macOS/Windows CI.
- Public releases, signing/notarization and Windows runtime acceptance are pending.

## Local macOS baseline 1.0.3 (not a public release)

- Default new installations to Modern, 80% glow and Long trail.
- Localize settings and preview UI into English and Czech.
- Provide a companion-app settings bridge for the intermittent system Options
  dialog problem; preserve saved user preferences.

### Installation and updates (unreleased)

- Add per-user macOS installation, Windows Inno Setup packaging, and independent
  standalone screen saver downloads.
- Add companion update controls with Sparkle / WinSparkle, signed payloads,
  manual checking, and opt-in weekly background checks outside the saver.
- Preserve preferences and saved figures across updates; document signing,
  release assets, and native upgrade acceptance requirements.
