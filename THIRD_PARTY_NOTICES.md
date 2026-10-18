# Third-party notices and licensing scope

## Original ARose

Original authors: Wolfgang Breyha and Michael Matzl, 1994–1995.

Source archive: [ARoseBlitz1.1 on Aminet](https://aminet.net/package/util/blank/ARoseBlitz1.1), containing `BB.ARose020881` (internal version 1.2, 05 April 1995). Hashes and the reconstruction process are recorded in [docs/reconstruction.md](docs/reconstruction.md).

The archive’s `ARose.readme` labels the original software **GIFTWARE**. The documentation inspected does not establish explicit permission to relicense reconstructed control data or derived material under MIT. The related Garshneblanker documentation credits Rose from After Dark. This is provenance information, not a new license grant.

`Sources/Core/RoseTables.swift` contains transcribed control sequences; `Windows/RoseTables.h` is generated from that same data. `Sources/Core/RoseEngine.swift` and its C++ port `Windows/RoseEngine.h` reconstruct the original behavior; the reconstruction notes describe that relationship. Neither the MIT notice nor the absence of original binaries resolves third-party rights in those portions.

Before publishing the complete source or binaries, clarify the applicable redistribution and derivative-work permissions with the relevant rights holders, or establish and document another appropriate basis. Record the scope of any permission here. Do not describe the complete project as unconditionally MIT-licensed while this is unresolved.

Original executables and archives are not included in this repository or development packages. New contributions are offered under the root MIT license only to the extent of rights held by their contributors. No affiliation with or endorsement by the original authors is claimed.

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
