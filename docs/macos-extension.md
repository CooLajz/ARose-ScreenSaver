# macOS app and screen saver extension

`ARose.app` embeds `ARoseExtension.appex` in `Contents/PlugIns`. The classic
`ARose.saver` remains buildable in the source project but is not a planned public download. The app and classic saver
target macOS 13; the extension targets macOS 14. Those are build minimums,
not a claim that all supported OS versions have passed runtime acceptance.

All three targets compile `Sources/Core` and `Sources/ScreenSaver`. Rendering,
settings controls and simulation changes are implemented once. Only the small
extension lifecycle adapter and packaging differ. Preferences and figure
bookmarks are independent for the app, extension and classic saver.

## Private interface and configuration

The extension uses the private `com.apple.screensaver` extension point, version 1.0,
informed by [AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal).
The runtime was inspected on macOS 27.0.1 to verify the declarations actually
used by this implementation:

- `ScreenSaverViewController.loadView()` creates the `ScreenSaverView`.
  ViewBridge sets the actual size and preview flag before animation begins.
  The sample header's `representedView` and `loadViewForFrame:isPreview:` are
  not implemented by this system's controller and are not used.
- Configuration subclasses `ScreenSaverConfigurationViewController`. Its
  runtime superclass is `NSServiceViewController`. Plain `NSViewController`
  fails ViewBridge bootstrap with error 14, before `loadView` is called.
- Save and Cancel call `configureSheetDidEnd()`, completing the extension
  request. They do not close the service's local window as a normal app sheet.
- `RoseOptions` supplies shared content independently of an `NSWindow`.
  The classic saver and preview app create a window only when they need one.
- The small Settings thumbnail can request a new view followed by
  `stopAnimation`, without starting that view. Only that explicit controller
  stop request enables a bounded, cached still image while the real engine is
  at frame zero and inactive. A newly created full-screen view stays black until
  animation starts, so it cannot flash the thumbnail during the system fade.
  A detached instance of the shared renderer builds the still image from the
  current preferences and optional saved figure, without writing preferences
  or advancing the real simulation. The poster is invalidated by a size or
  configuration change and released when animation starts. Classic/app views
  keep their existing startup behavior.
- Modern animation waits for the first simulation tick before submitting a
  Metal frame with initially empty trails. Repeated start requests preserve
  the running presentation clock instead of resetting it.
- First app launch queries `pluginkit` before registering. Finder may have
  already registered the extension; repeating `pluginkit -a` while its Options
  sheet is open invalidates the host connection and leaves a blank sheet.
- Opening Installation and Updates completes the configuration request before
  launching the app. Launch Services can also re-register a newly copied app
  before its own code runs, so installation includes opening the app once before
  selecting the saver. Changed installations now refresh WallpaperAgent and any
  running System Settings instance automatically; Settings reopens at Wallpaper.
  The generation includes executable bytes, file identity and PlugInKit UUID,
  so even removing and reinstalling the same build is detected. Unchanged
  launches and copies outside Applications skip this refresh. Recovery waits
  for an active, unlocked console session and closed app configuration sheets.

No system binary is patched and no private entitlement is added. The extension
uses App Sandbox. Private APIs can change, so the classic target remains
available in source and each new macOS version needs actual host testing.

## Local acceptance

On Apple M2 with macOS 27.0.1, 18 October 2026: universal build, deep code-signature
verification, system discovery, custom thumbnail, animation and Save/Cancel
were checked. The Options panel reopened through multiple complete picker
close/reopen cycles without restarting System Settings. `script/test.sh` also
checks the runtime controller ancestry, loading overrides and completion selector, alongside
the existing engine, classic bundle, settings and rendering checks.
After the installed app's initial launch, two successive Options → Installation
and Updates → Options cycles also passed without a blank configuration sheet.

The automated controller test cannot reproduce the complete cross-process
system presentation. Repeat the manual picker test when changing this adapter.
macOS 14–26, Intel hardware, multiple displays, notarized installation and an
actual Sparkle upgrade remain separate acceptance work.

Same-build replacement, automatic host refresh, automatic Settings reopening
and unchanged-launch skipping were also exercised locally. Update-policy tests
cover file/registration identity, DMG isolation and locked/idle/session guards.
A complete signed Sparkle download/install from a test feed remains pending.
The previously black Settings thumbnail was also checked visually after Cancel,
whole-picker close/reopen and app replacement. Automated checks cover both
appearances, repeated still rendering, fresh preferences and preserved figure
bookmarks followed by a normal animation start.
After restricting the poster to explicit stop requests, the installed extension's
thumbnail and Options were checked again after Cancel and a whole-picker
close/reopen cycle. Regression checks cover cold full-screen drawing, both
stopped-thumbnail appearances, the first Metal submission and repeated starts.
The user also confirmed that actual activation from the desktop is now smooth,
without the previous double flash during the fade.

## Packaging

Run `script/build_and_run.sh --build`, then `script/package_macos_installer.sh`.
The DMG contains ARose.app and a symlink to /Applications, with a Finder icon
layout and bilingual drag instruction. The layout is written to `.DS_Store`
using pinned build dependencies in `.build/dmg-tools`; no Finder automation is
needed to build it. License and installation documents are stored in the hidden
`.documentation` folder and licenses also ship inside the app.

The app keeps bundle identifier `cz.coolajz.ARose.Preview` for existing app
preferences and update identity. The extension has its own child identifier.
Old manually installed classic savers are never silently replaced or removed.
