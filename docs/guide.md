# ARose user guide

**English** | [Česky](guide.cs.md) · [Back to the main page](../README.md)

## Requirements and release status

Version 1.0.3 is the first public release. Downloads and update feeds are published in GitHub Releases.

| Platform | Requirement | Testing status |
| --- | --- | --- |
| macOS | macOS 14+ for the app with the system screen saver; Apple Silicon or Intel | Manually tested on a Mac M2. Other macOS versions and Intel hardware still need runtime acceptance. |
| Windows | Windows 11 x64 | Native CI, installer checks and the maintainer’s final Windows test passed. |

Public Mac packages are Developer ID signed and notarized by Apple. Windows binaries are unsigned and Windows may display an unknown-publisher warning. A successful build does not mean every supported system has been tested.

## Installation

### Mac

1. Open the installation DMG and drag ARose to Applications.
2. Launch the installed app once from Applications.
3. Choose **ARose → Screen Saver Settings…**, select ARose and open **Options…**.

The location of screen savers in System Settings varies by macOS version; newer versions place them under Wallpaper. After replacement or an update, the app may refresh an open System Settings window to load the new saver. You can then close the app.

The classic `.saver` is not part of the planned public downloads. If you have one from earlier development tests, it is a separate installation; dragging in the new app does not remove it.

### Windows

Run `Setup.exe`, approve the administrator prompt and complete the wizard. The Start menu provides **ARose** for companion controls and **ARose Preview** for animation in a window. Select ARose in Windows Screen Saver Settings. Windows continues to manage passwords, locking and idle time.

### Standalone Windows screen saver

The standalone `ARose.scr` needs no companion app or additional frameworks. Save it in a permanent folder, right-click and choose **Install** (use **Show more options** first if needed). This opens Windows Screen Saver Settings, where you can select ARose.

Do not move the file while it is selected as your saver. Install a new version by replacing the file manually. Use the full installer for convenient updates.

## Where to change settings

**The app and system screen saver have separate settings and saved positions.**

- For the system screen saver, use **Options…** on macOS or **Settings** in the Windows screen saver dialog.
- In the macOS app, use **Settings…**. In the Windows animation preview, press **F1**.
- Confirm changes with **Save**. **Cancel** discards them.

## What the options do

| Option | Effect |
| --- | --- |
| Appearance | **Original Amiga** for retro points and palettes; **Modern** for fine points and a continuous rainbow. |
| Speed | Changes the pace of movement and transitions. |
| Trail | Controls how much point history stays visible. |
| Colors | Selects monochrome, ECS or AGA in Retro. Modern uses the continuous RGB rainbow. |
| Glow | Adjusts light around Modern points from 0–100%. Zero keeps fine points without glow. |
| Point light | Modern point-light intensity, 0–100%: 0% keeps the original point brightness, 50% matches luminous points, and 100% increases emitted light further. Glow is independent. Default: 0%. On older graphics using the Direct2D fallback, overlap brightening depends on device-context support. |
| Point size | Modern dot diameter from 0.75× to 2×. Default: 1×, preserving the classic appearance. Soft glow size is independent. |
| Scale retro figures to display resolution | Enlarges figures for current displays while keeping crisp dots. Disable it for a fixed pixel size as on the Amiga. The later WinRose introduced resolution-based enlargement. |
| Resume from last figure | Continues approximately from the previous position on the next run. Off by default. |
| Forget saved figure | Clears the position for the app or saver you are configuring when you click Save. Does not disable continuation. |
| Debug: show process CPU usage | An optional technical CPU readout; leave it off for ordinary use. |

Appearance settings preview immediately, including style, speed, trail, palette, glow, point light, point size and the CPU overlay. **Cancel** restores the saved configuration; **Save** keeps the changes. Forgetting a saved figure takes effect only after Save.

Continuation restores the figure, rotation and color phase rather than a saved image. Trails rebuild after launch. Disabling continuation does not delete the position; reset it with **Forget saved figure → Save**. Changing appearance may restart the animation.

## Playing with patterns in the app

| Action | macOS | Windows preview |
| --- | --- | --- |
| Settings | Settings… button or ⌘ , | F1 |
| Full screen | ⌘ F | F |
| Pause / resume | ⌘ P | Space |
| Start again | ⌘ R | R |
| Advance animation | ⌘ N | — |
| Quit | ⌘ Q | Esc; first leaves full screen if active |

### Experimental live wallpaper on Mac (development build)

Choose **Pattern → Live Wallpaper (Experimental)** to try the animation on the primary monitor beneath desktop icons. The window and Dock icon disappear; use the ARose menu bar icon for settings, pause, restart, **Return to Window**, or quit. Wallpaper shares the companion app's settings. Leave full screen and close settings before enabling it.

**Launch at Login** uses macOS login items. Enable it from a copy in Applications, and complete any approval in System Settings. The app remembers its last mode, including live wallpaper, on the next launch. Login launch is initially disabled and independent of weekly update checks.

Live wallpaper alone smoothly brakes over two seconds when paused and accelerates over two seconds when resumed. This also applies to automatic pauses for full screen, screen savers, and screen lock. Initial launch from black starts at normal speed. The regular app window and system screen saver keep immediate pause and resume. System sleep may interrupt braking; wake resumes with a gentle run-up without catching up time spent asleep.

**Pause for Full Screen Apps** is initially enabled. Full screen stops wallpaper rendering, which automatically resumes on return. Players such as Infuse may not report the system full-screen state, so ARose also checks once per second whether another app's window covers the entire wallpaper display. A manual pause remains in effect. Detection uses the active Space and window bounds, not window contents or titles, and needs no Screen Recording or Accessibility permission.

Quitting ARose reveals the original wallpaper. Modern desktop animation is capped at 30 frames/s while preserving the original simulation timing. Rendering automatically pauses during the system screen saver, screen lock, display sleep, or an inactive user session, even with the fullscreen option disabled. It resumes on return while preserving a manual pause. Screen saver detection uses notifications and an actual visible window rather than merely a running host process. This initial prototype has no monitor picker or detection of ordinary windows covering the desktop; Mission Control and Stage Manager need further operational testing.

## Updates

Choose **Check for Updates…** in the installed companion app. When a new version is available, the update window guides you through downloading and installing it. Windows may request administrator approval. A Mac app update includes the system screen saver.

**Check automatically every week** is optional and initially disabled. Checks do not wake the computer and may be deferred while the device is locked or asleep. The animation works offline, needs no account and sends no telemetry.

## Uninstalling

**Mac:** disable weekly checks if enabled, select another system screen saver, then move **ARose.app** from Applications to the Trash. The embedded saver is part of the app. An old standalone `.saver`, if installed, must be removed separately from `Library/Screen Savers`.

**Windows installer:** use Windows app uninstallation. On a shared computer, other users should select a different saver first as well.

**Standalone Windows file:** select another saver or None, then delete `ARose.scr`.

Saved preferences and figures remain available for a future installation.

## Troubleshooting

- After manually replacing the Mac app, launch the new copy from Applications once.
- App changes did not affect the saver? Their settings are intentionally separate; open the system saver options.
- Development update checks may fail until the public update channel is published.
- Report problems through [GitHub Issues](https://github.com/CooLajz/ARose-ScreenSaver/issues). Include your OS and its version, ARose version, appearance mode and steps to reproduce. Screenshots help; cover any personal information before submitting them.
