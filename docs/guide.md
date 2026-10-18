# ARose user guide

**English** | [Česky](guide.cs.md) · [Back to the main page](../README.md)

## Requirements and release status

The first public release is being prepared. Public update checks will become usable once the release and its update files are published.

| Platform | Requirement | Testing status |
| --- | --- | --- |
| macOS | macOS 14+ for the app with the system screen saver; Apple Silicon or Intel | Manually tested on a Mac M2. Other macOS versions and Intel hardware still need runtime acceptance. |
| Windows | Windows 11 x64 | Native builds and individual tests have run; final user acceptance before the first release remains pending. |

Current Mac development packages use local ad-hoc signing, and Windows builds do not have a distribution signature. Developer ID signing and macOS notarization are part of public release preparation. A successful build does not mean every supported system has been tested.

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
| Scale retro figures to display resolution | Enlarges figures for current displays while keeping crisp dots. Disable it for a fixed pixel size as on the Amiga. The later WinRose introduced resolution-based enlargement. |
| Resume from last figure | Continues approximately from the previous position on the next run. Off by default. |
| Forget saved figure | Clears the position for the app or saver you are configuring when you click Save. Does not disable continuation. |
| Debug: show process CPU usage | An optional technical CPU readout; leave it off for ordinary use. |

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
