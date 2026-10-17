# macOS rendering measurements

The renderer keeps the original simulation, PAL timing, geometry, color values,
trail lengths and glow interpolation. Modern colors are cached for the lifetime
of their simulation frame. Retro images now expand palette indices through a
precomputed RGB lookup table, avoiding Core Graphics' general indexed-color
conversion on every image. Each image owns an immutable buffer so asynchronous
compositing cannot read pixels modified by a later frame.

CPU overlay font attributes and text measurements are reused until the displayed
value changes. Timer callbacks that do not advance the simulation no longer
request another identical redraw. Pending display invalidations remain intact.

## Reproduce

Capture reference images before changing the renderer, then compare decoded
pixel bytes after the change:

```sh
./script/benchmark_macos.sh .build/performance/baseline
./script/benchmark_macos.sh .build/performance/current .build/performance/baseline
```

For retro mode, use the third argument (an empty second argument skips comparison):

```sh
./script/benchmark_macos.sh .build/performance/retro-baseline '' --retro
./script/benchmark_macos.sh .build/performance/retro-current .build/performance/retro-baseline --retro
```

The benchmark draws into a 3840 × 2160 bitmap with 1920 × 1080 logical
coordinates, Long trail, normal speed, and glow at 0% and 80%. Retro ignores glow.
It advances to frame 1500, warms up for ten frames, then measures 90 simulation
steps and redraws separately using process CPU time. Image snapshots and PNG
encoding are outside the timed regions. Images represent simulation frames
1511, 1551 and 1600. Tests inject isolated UserDefaults; saved screen saver
preferences are neither read nor changed.

Use the same machine, macOS version and color environment for comparisons.
Offscreen CPU time is not a measurement of the system screen saver, GPU energy
or battery drain.

## Corrected measurement method (2026-10-17)

The previous benchmark's results are superseded. Its ScreenSaverDefaults
volatile domain was not reliably shared with views, its NSBitmapImageRep
context was scaled twice, and repeated PNG serialization could reuse a cached
image. The corrected test injects preferences into each view, applies scaling
once to a CGContext, and captures a fresh image at every checkpoint.
Consequently the earlier 17% / 2% optimization figures are not reliable estimates.

One before/after run of the corrected retro workload measured 17.567 → 15.954 ms
per redraw at glow 0%, and 17.253 → 15.670 ms at glow 80% (ignored in retro),
approximately 9% less CPU time in this bitmap host. These are preliminary local
measurements, not a claim of a corresponding whole-process or battery saving.
Modern drawing is unchanged by the palette optimization; timing variation there
must not be reported as a speedup.

Six retro and six modern checkpoint images matched exactly after decoding.
The independent regression test in Tests/RetroRendering also compares all three
palettes at seven simulation frames and three output sizes against the former
indexed renderer (63 exact comparisons), and checks that retained images remain
immutable. Other bundle, glow, localization, CPU overlay and engine tests run
through script/test.sh.

## Metal glow compositing (2026-10-17)

Modern mode with nonzero glow now uses a CAMetalLayer and a hybrid renderer.
Metal resamples and additively blends the original 256 halo sprites. Sharp dots,
bright cores and the CPU overlay still use the original Core Graphics rasterizer
in a transparent shared-memory foreground buffer, composited over the light by
Metal. A four-tap footprint filter reduces minification artifacts. Simulation,
coordinates, hue selection, opacity and halo size formulas are unchanged.

Three independently owned buffers protect CPU/GPU overlap. When all three are busy,
presentation skips a frame without blocking the simulation clock. No GPU readback
or synchronous GPU wait occurs in normal rendering. Device/pipeline creation or
command failures fall back to the CPU renderer. Retro and Modern with glow zero
retain their existing drawing path. Set AROSE_RENDERER=cpu when launching Preview
to force the reference renderer for diagnosis; this does not change saved settings.

Run on a Metal-capable Mac (the GPU may be unavailable in CI or a sandbox):

```sh
./script/test_metal.sh
./script/test_metal.sh --window
```

The window test uses isolated preferences and checks layer presentation, resizing,
glow toggling and reset. The image test captures actual Metal textures at
1920 × 1440 pixels (960 × 720 points, 2× backing), Long trail, speed 3, frame 1551.
Without glow, GPU composition of the sharp foreground matches the CPU reference
exactly. Glow is visually close but **not byte-identical**: at 80%, the largest
channel difference was 12/255 and total RGB intensity was 2.04% higher; at 100%,
10/255 and 1.04% higher. These differences include resampling and intermediate
8-bit blend rounding. They are not a geometry change or a reduced-resolution
render.

A warm 10-frame local benchmark at this size measured roughly 49 ms CPU drawing
versus 9–9.5 ms CPU preparation for Metal at glow 80%, with roughly 0.36 ms GPU
execution. At glow 100%, approximately 60 ms versus 9 ms, with 0.42 ms GPU time.
Preparation excludes synchronous test readback, PNG encoding and presentation;
this is not a whole-process CPU percentage or battery measurement. The foreground
rasterizer still consumes CPU, so this is not a fully GPU-rendered scene.

## Metal presentation pacing

Metal submission now runs directly from the animation callback. AppKit draw
invalidation is retained for the CPU renderer, not inserted between the PAL
clock and GPU submission. Three resource/drawable slots absorb transient overlap;
display synchronization is explicitly enabled. Drawable size only changes on
resize. Temporary drawable unavailability keeps the previous GPU image rather
than switching renderers. Layout/backing-scale changes refresh even a paused view.
The GPU window test checks submission counts and starvation during steady motion.
These checks do not establish perceptual smoothness in every screen saver host
or display refresh configuration; simulation remains at the original 50 Hz.

## Full Metal points (2026-10-17)

Modern rendering now sends point rectangles, device-RGB colors and opacity to
Metal, with or without glow. The mathematical engine and 50 Hz pacing are
unchanged. Retro still uses the reference CPU renderer. CPU rendering remains
available automatically on Metal failure, or via `AROSE_RENDERER=cpu`.

A true-circle GPU shader was rejected: tiny 1-pixel points differed noticeably in
energy from Core Graphics. Instead, a small two-slice R8 coverage atlas is built
with the original Core Graphics ellipse rasterizer when the pixel diameter
changes. Each slice contains a 33 × 33 grid of subpixel phases (dot and bright
core). Metal interpolates the neighboring phase coverage, keeps the original
per-point draw order, and applies the same color and opacity. This is not a
scaled bitmap of the rose: positions remain subpixel and the atlas is regenerated
for the current pixel diameter. The full-screen CPU foreground is removed from
normal rendering. Only the optional CPU label uses a cropped buffer, at most
512 × 64 logical points. Halo and point instance buffers are reused per in-flight
slot. The old full-size foreground remains accessible only for reference tests.

In the original 1920 × 1440, Long-trail checkpoint, the new renderer differs from
the previous hybrid renderer by at most 3/255 per channel. With glow at 80%, RGB
energy changed by -0.0018%; with glow off, +0.0305%. These are small differences,
not byte-identical rendering. Initial additional 1× and portrait checkpoints
showed at most 3/255 and up to +1.11% energy change (the sparse 1-pixel/no-glow case).
The broader tests also expose pre-existing halo differences against pure CPU
rendering at small sizes; those must not be attributed to this point migration.
Tests therefore compare new points against the previous hybrid and also retain
the original CPU comparison. New point thresholds are max 4/255 and 2% RGB energy.

A local warm run at the original checkpoint measured about 0.09 ms preparation
CPU and 0.38 ms GPU at glow 80%, versus the previously recorded 9–9.5 ms CPU
preparation for the hybrid. At glow zero, preparation was about 0.40 ms versus
5.0 ms pure CPU drawing. These narrow measurements exclude simulation, host
work, presentation, readback and PNG writing; they are not whole-process CPU or
battery measurements. Atlas construction is a one-time cost per diameter.
The window test passed paused resizing, glow off/on and reset, with 190 submitted
steady-state frames and no busy-slot or unavailable-drawable skips.

Final coverage includes 15 cases: 1920 × 1440, 640 × 480 (1×), portrait
800 × 1600, 3840 × 2160 and the small 400 × 250 preview, each at glow 0/80/100%.
All passed the new-point thresholds (observed maximum 3/255). Cropped debug-label
pixels matched the full-screen reference exactly, and empty histories produced
black frames in every case. The standard engine, localization, bundle and all
63 retro reference comparisons also passed. Installed system-host CPU and battery
acceptance remain to be measured by the user with the same scene/settings.

## Startup pacing follow-up

The first animation callback previously stamped its clock before creating Metal
pipelines, coverage atlases and the first drawable. The following callback could
therefore advance several simulation steps to catch up with initialization time.
The clock now starts after the first submission. Subsequent 50 Hz accumulation
is unchanged. Each in-flight instance buffer reserves the maximum supported
20-frame trail on first use, avoiding repeated growth allocations during the
opening motion. This does not precompute or skip any simulation frames.

The window test now starts with an empty history rather than advancing 1,500
frames before displaying the window. It checks that immediately calling the
second callback does not catch up initialization time and that filling the trail
uses at most six instance-buffer allocations across three slots, with no further
growth in steady animation. Perceptual acceptance in the system saver remains a
separate check; these changes do not establish that every visible hitch is fixed.

## Display-paced Modern animation (17 October 2026)

On macOS 14+, an NSView CADisplayLink drives Modern presentation at the current
screen's preferred maximum rate. The host's 50 Hz callbacks do not also advance
the simulation while that link is active. Simulation remains 50 Hz; positions
and circular hue interpolate between consecutive histories, adding up to one
PAL step of presentation latency. Trail warm-up uses the current history until
both histories have matching lengths. Retro and older macOS keep host timing.

Deterministic 60/120/144 Hz tests preserve the exact saved simulation state after
ten seconds and check pause, bounded sleep catch-up and hue wrapping. A local
window run on a screen reporting 120 Hz measured 110.63 Metal submissions/s over
the initial approximately four seconds, with 423 submissions and zero busy or
unavailable-drawable skips at the steady-animation check. This is submission
cadence, not proof of a locked 120 displayed frames/s. Window resize while paused,
glow changes and reset passed. System-saver full-screen smoothness still needs
visual acceptance; refresh can vary with system scheduling and power policy.
