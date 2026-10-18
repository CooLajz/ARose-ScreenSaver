# ARose ScreenSaver

**English** | [Česky](README.cs.md)

**A little piece of the Amiga on today's screens.** Colorful dots, evolving shapes and motion that makes it easy to lose track of time. ARose brings a beloved Amiga screen saver to macOS and Windows, preserving its character while adding a new glow for modern displays.

**Watch ARose in motion**

https://github.com/user-attachments/assets/b8c67746-8197-4f5f-9714-1877c5d0dc92

## The story behind the revival

Years ago, my Amiga 1200 ran BlitzBlank with a module called ARose. A handful of colorful dots rotated, mirrored and formed beautiful patterns. It was one of those small experiences that stay with you for decades.

Much later, I spent a long time looking for something that would bring the same feeling to my Mac. I could not find it, so this remake began. The aim was to preserve what made ARose special: its shapes, transitions, rotations and rhythm.

We managed to contact the original authors, **Wolfgang Breyha and Michael Matzl**. They welcomed the revival and gave permission to publish it. They also supplied the original source code to help us check and refine the behavior. That made it possible to compare the original mathematics and correct subtle differences in the rotations.

The result brings that experience back in two forms: the original character of crisp colored dots, or smooth points with a continuous rainbow and adjustable glow. For me, ARose is now more than a screen saver. It is a relaxing coffee break and a small journey back to the Amiga days.

## Amiga, Retro and Modern

The app offers two modes. Retro is called **Original Amiga** in settings; the original Amiga column below refers to the historical program that inspired this remake.

| | Original ARose on Amiga | Retro in this remake | Modern in this remake |
| --- | --- | --- | --- |
| Shapes and motion | Original calculations and sequences | Focus on preserving the original calculations and sequences | The same foundation of shapes and motion |
| Points | Crisp dots at Amiga resolution | Crisp single-pixel dots at display resolution | Fine, antialiased points, including on Retina displays |
| Colors | Palettes suited to Amiga hardware | Monochrome, ECS and AGA palettes | Continuous RGB rainbow |
| Figure size | Fixed pixel size | Optional resolution-based enlargement, enabled by default | Automatically fits the drawing area |
| Glow | No modern glow effect | No glow effect | Adjustable glow from 0–100% |

**Modern mode keeps the underlying pattern sequence.** It develops the appearance for current monitors and smooth playback. Retro preserves the character of the original drawing; it is not a full Amiga emulator or a promise of identical output in every frame.

## Download and install

**First public release: 1.0.3.** Choose the installer for your system:

- [Download for macOS — DMG](https://github.com/CooLajz/ARose-ScreenSaver/releases/download/v1.0.3/ARose-ScreenSaver-v1.0.3-macOS-universal.dmg)
- [Download for Windows — installer](https://github.com/CooLajz/ARose-ScreenSaver/releases/download/v1.0.3/ARose-ScreenSaver-v1.0.3-Windows-x64-Setup.exe)
- [All release files](https://github.com/CooLajz/ARose-ScreenSaver/releases/latest)

### macOS — macOS 14 or later

1. Download and open the **macOS `.dmg`** file.
2. Drag **ARose** onto **Applications**.
3. Launch ARose from Applications. Choose **ARose → Screen Saver Settings…**, then select ARose in System Settings.
4. Use **Options…** to configure the system screen saver.

The app does not need to stay open while the screen saver runs. The Mac download is a single installation DMG; the classic standalone `.saver` remains in the source project only. The package includes Apple Silicon and Intel builds; see the [user guide](docs/guide.md#requirements-and-release-status) for the scope of testing so far.

### Windows — Windows 11, 64-bit

1. Download and run the **Windows `Setup.exe` installer**.
2. Approve the administrator prompt and complete installation.
3. Select **ARose** in Windows Screen Saver Settings. The companion controls are available from the Start menu.

There is no separate .NET or Visual C++ Redistributable installation. A [standalone `.scr` file](docs/guide.md#standalone-windows-screen-saver) is also available for those who prefer it.

## Make it your own

The default combination is **Modern, 80% glow and a long trail**. Adjust the speed, trail length and glow, or switch to Retro. Enable **Resume from last figure** to continue approximately where the previous session ended.

The companion app also lets you enjoy the animation in a window or full screen. **Its settings are independent of the system screen saver.** Experimenting in the app will not change your saver.

The app offers manual update checks and optional weekly checks, initially disabled. The animation works offline and needs no account; an internet connection is used to check for and download updates.

[User guide: settings, controls, updates and uninstalling →](docs/guide.md)

## Thanks and license

The original Amiga ARose was created by **Wolfgang Breyha and Michael Matzl in 1994–1995**. Thank you for the beautiful original, your support for the revival and your help in preserving its behavior. The original documentation credits Rose from After Dark as an inspiration. [Original ARose on Aminet](https://aminet.net/package/util/blank/ARoseBlitz1.1).

This remake is developed with their permission and uses the [MIT license](LICENSE). The original source archives supplied by the authors and the original executables are not redistributed here. See [third-party notices](THIRD_PARTY_NOTICES.md) for permission scope and dependency licenses.

## For developers

[Building and project structure](docs/development.md) · [Reconstruction notes (Czech)](docs/reconstruction.md) · [Preparing a release](docs/releases.md)
