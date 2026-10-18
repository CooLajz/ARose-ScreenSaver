# Third-party notices and licensing scope

## Original ARose

Original authors: Wolfgang Breyha and Michael Matzl, 1994–1995.

Source archive: [ARoseBlitz1.1 on Aminet](https://aminet.net/package/util/blank/ARoseBlitz1.1), containing `BB.ARose020881` (internal version 1.2, 05 April 1995). Hashes and the reconstruction process are recorded in [docs/reconstruction.md](docs/reconstruction.md).

The historical archive labels the original software **GIFTWARE**. During private correspondence for this revival, Wolfgang Breyha permitted publication of the remake under a license of our choice, explicitly including MIT. After consulting Michael Matzl, he confirmed that the project could be published and supplied the original BlitzBlank sources to improve its accuracy.

The permission to use those supplied sources came with a separate restriction: the original source archives must not be shared further without the authors' approval. They remain outside this repository and are not part of release packages. The correspondence is summarized here; private emails, contact details and attachments are not published.

This remake is distributed under the root [MIT license](LICENSE), relying on that permission for the reconstructed behavior and transcribed control sequences. This does not relicense or redistribute the historical source archives or original executables. Credit to Wolfgang Breyha and Michael Matzl is retained. Permission to publish the remake does not imply that the original authors maintain or certify it.

The control sequences are in `Sources/Core/RoseTables.swift`; `Windows/RoseTables.h` is generated from the same data. The Swift and C++ engines preserve the original mathematical foundation. [Reconstruction notes](docs/reconstruction.md) record the initial binary analysis; subsequent comparison with the privately supplied sources allowed rotation behavior to be refined. The original documentation credits Rose from After Dark as inspiration.

## Companion updater libraries

The companion applications bundle Sparkle 2.10.0 (macOS) and WinSparkle 0.9.4
(Windows), both under the MIT license. Their upstream license notices are
included with the distributed binaries (including bundled dependency notices).
They are not linked into the standalone screen savers.
Sources: https://github.com/sparkle-project/Sparkle and
https://github.com/vslavik/winsparkle .

## Screen saver extension reference

The private ScreenSaver declarations and extension integration were informed by
[AppexSaverMinimal](https://github.com/AerialScreensaver/AppexSaverMinimal),
with runtime corrections for the configuration controller and lifecycle.
Its MIT notice follows:

MIT License

Copyright (c) 2026 Guillaume Louel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## DMG build tools

Packaging uses `ds-store` 1.3.1 and `mac-alias` 2.2.2 (Alastair Houghton, MIT),
installed into a local build virtual environment. They are build dependencies,
not bundled application runtime libraries.
Sources: https://github.com/al45tair/ds_store and https://github.com/al45tair/mac_alias .
