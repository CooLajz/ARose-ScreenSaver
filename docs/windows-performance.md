# Windows rendering and local verification

Modern mode now uses hardware Direct3D 11 instancing. One draw submits all halos
and a second submits sharp points and bright cores in their original order.
With glow disabled there is one draw. Dynamic instance buffers use
`WRITE_DISCARD`; the driver manages reuse while the GPU consumes prior frames.
Simulation and interpolation remain on the CPU at the original PAL timing.

Direct2D generates native halo and point-coverage textures on the same GPU at
initialization or when physical point diameter changes. The point atlas has
128 × 128 subpixel phases per slice. The shader interpolates four phase samples;
there is no per-frame CPU ellipse rasterization or full-screen bitmap upload.
The optional label uses Direct2D/DirectWrite on the shared GPU back buffer.
Production does not read the frame or atlases back to CPU memory.

The overlay identifies `Direct3D 11 GPU`. Initialization or device failure falls
back to Direct2D hardware, then software if necessary. The old renderer remains
selectable for comparisons. Original Amiga rendering and macOS code are unchanged.

The Direct2D fallback draws soft halos from a device-dependent 16 × 16 color atlas. Each tile
is generated once with the original Direct2D radial brush at the current
physical-pixel radius. Animation reuses the texture with the original point
order, opacity, hue selection and source-over blending. The atlas is rebuilt
after a radius change or target loss. Allocation failures retain the original
radial-brush path. Sharp points retain their original ellipse rasterization.

## Build and test

Install Visual Studio 2022 Build Tools with the C++ desktop workload, Windows
SDK and CMake component, plus Python 3. From PowerShell in the repository:

```powershell
./script/build_windows.ps1
# If Python is not on PATH:
./script/build_windows.ps1 -Python 'C:\path\to\python.exe'
```

The script locates Visual Studio's CMake automatically, builds Release x64,
runs all six CTest tests and checks the 24 Swift/C++ parity checkpoints.
MSVC now uses the existing resource manifest rather than generating a duplicate.
The table generator explicitly reads and writes UTF-8 on Windows.

## Reproduce a comparison

```powershell
./script/benchmark_windows.ps1 -Seconds 30 -Backends hardware -Drawing reference -OutputDirectory build-windows/performance/reference
./script/benchmark_windows.ps1 -Seconds 30 -Backends hardware -Drawing cached-halo -OutputDirectory build-windows/performance/cached
./script/benchmark_windows.ps1 -Seconds 90 -Drawing direct3d -OutputDirectory build-windows/performance/direct3d
./script/benchmark_windows.ps1 -Seconds 60 -Drawing direct3d -CpuOverlay -OutputDirectory build-windows/performance/overlay
```

Each directory must be new. `/b <new-report.json> [seconds] [backend]` runs the
fixed Modern scene in a 1280 × 720 physical-pixel client area, normal speed,
tail 16, glow 80%, CPU overlay off unless requested, and resume disabled. It does not save
preferences or figure bookmarks. The report records actual size, DPI, frame
rate, process CPU time, drawing path, atlas use, GPU draw count, initialization
time and wall time spent in preparation, submission, presentation and simulation. It includes cold resource
preparation, so a 30-second run is not a pure steady-state benchmark.

`direct3d` requires the batched hardware renderer and the runner rejects an
unexpected fallback. For the retained Direct2D paths, `hardware` requires a
hardware target; `software` requires software; `default` leaves selection to
Direct2D. CPU percentages report both one logical core and all logical cores.
The timing sections measure wall time, not GPU execution time or battery use.
Run sequentially in the normal desktop session on the same machine and power
configuration. A sandbox desktop may give different results.

The runner starts the executable directly: Windows shell association for
`.scr` can replace diagnostic arguments with `/S`. To start an interactive
preview reliably from PowerShell:

```powershell
& ./build-windows/Release/ARose.scr /w
```

Set the process environment variable `AROSE_WINDOWS_RENDERER=reference` for the
original radial-brush path, `cached-halo` for the first Direct2D optimization,
or `direct3d` for batching. An unset variable uses Direct3D with fallback.
These overrides do not change saved settings.

## Batched Direct3D measurement, 17 October 2026

Final Release runs on the same Radeon laptop, 12 logical processors, 144 DPI,
1280 × 720 client, Modern, tail 16, speed 3 and glow 80%:

| Metric | Overlay off, 90 seconds | CPU overlay on, 60 seconds |
| --- | ---: | ---: |
| Frames per second | 59.72 | 59.61 |
| Process CPU, all-core scale | 0.473% | 0.723% |
| Process CPU, one-core scale | 5.677% | 8.671% |
| Scene submission wall time per frame | 0.126 ms | 0.549 ms including label |
| Initial preparation | 0.368 s | 0.421 s |
| Instanced scene draws | 2 | 2 plus Direct2D label |

Against the first cached-halo result below, total process CPU fell by about
90% with the overlay off while frame rate increased from 50.93 to 59.72 fps.
The user confirmed that the Mac's cited 1.2% was also the all-core overlay
value. These runs meet that percentage target on this Windows laptop; they
are not a cross-machine energy or battery comparison.

Raw reports are in ignored local directories
`build-windows/performance/direct3d-final-90s` and
`build-windows/performance/direct3d-overlay-60s`. Both record the active
`direct3d11` path and two scene draw calls; the runner rejects a fallback,
resized window or interrupted measurement.

## Initial Direct2D measurement, 17 October 2026

One sequential 30-second pair on the development laptop (AMD Radeon graphics,
12 logical processors, Windows 11, 144 DPI, hardware target, 1280 × 720 client):

| Metric | Reference | Cached halo |
| --- | ---: | ---: |
| Frames per second | 29.66 | 50.93 |
| Submission wall time per frame | 18.86 ms | 10.29 ms |
| Process CPU, one-core scale | 60.29% | 59.37% |
| Process CPU, all-core scale | 5.02% | 4.95% |

This pair shows about 45% shorter submission time and 72% more rendered frames.
It does **not** show a material reduction in total process CPU usage: the
optimized renderer spends the saving on additional frames. The measured
initial workload fell short of 60 fps. This led to the batched renderer above;
the Direct2D-only result does not demonstrate reduced process CPU or battery
use. Earlier exploratory runs are not the canonical comparison.

Reports are in the ignored local directories
`build-windows/performance/final-reference` and
`build-windows/performance/final-cached`.

The first Direct2D `/w` preview was visually checked with the user's existing settings.
The overlay reported `Direct2D GPU`; F1 opened the Czech settings dialog and
Escape canceled it and resumed animation. Embedded preview, full-screen lock
behavior, mixed monitors and display sleep remain unverified here.

## Image regression coverage

`rendering-images` compares the shared drawing code with the retained reference
using Direct2D/WIC offscreen surfaces. Its 72 comparisons cover 800 × 600,
1280 × 720, 1080 × 1920 and 3840 × 2160, DPI factors 1 and 1.5, glow 0/80/100%,
and three interpolation phases at simulation frame 1551. It also exercises
cache invalidation and recreation.

Without glow the decoded images are byte-identical. With glow the worst
observed channel difference was 9/255 and the largest total RGB energy change
was 2.293%. The explicit acceptance limits are 12/255 and 3%; cached halos are
visually close, not byte-identical. These are software-reference image checks,
not hardware readback or equality to the macOS additive glow renderer.

Native tests and short measurements do not replace the multi-monitor,
mixed-DPI, embedded system preview, display sleep and long-session acceptance
checks in [Windows continuation](windows-handoff.md).

## Direct3D hardware image checks

`rendering-gpu` compares actual Direct3D readback against the retained native
Direct2D drawing code on the same hardware surface. Its 72 cases use the same
resolution/DPI/glow/interpolation matrix as above. It verifies one or two scene
draw calls, overlay interoperability after resize, empty-frame clearing and
complete device recreation. Machines without hardware Direct3D 11 report a
CTest skip (77), which is not a passed GPU test.

On the development Radeon, the maximum total RGB energy difference was
0.333%, and the maximum whole-image RGB RMS error was 0.308/255. Native
antialiasing has discrete jumps at tiny subpixel positions; a few individual
channel differences reached 37/255. The explicit bounds are 40/255 per channel,
RMS 0.45/255, and total RGB energy change of 1% without glow or 3% with glow.

On 18 October 2026, the `windows-2025` runner in
[CI run 39130654333](https://github.com/CooLajz/ARose-ScreenSaver/actions/runs/39130654333)
measured a maximum channel difference of 40/255, RGB energy change of 2.57898%,
and RMS error of 0.423565/255 across 72 images. This result was explicitly
accepted by the project owner. The RMS bound was raised from 0.35 to 0.45/255
to cover that accepted baseline; the channel and energy bounds remain unchanged.

These limits cover numerical coverage interpolation, not a different geometry,
color sequence, draw order or additive blending. The independent stricter
Direct2D-only checks above remain unchanged. The GPU image is not byte-identical.
