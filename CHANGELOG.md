# Changelog

## Unreleased — public distribution preparation

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
