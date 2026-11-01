# Paper Sketch 4: dry-media material audit

Audit date: 2026-11-01. Scope: `sketch-material.h` and its native material regression test. Device input, live framebuffer timing, release packaging and the QML controls have separate verification.

The renderer approximates dry pigment on a textured surface. Each pixel stores fixed and loose pigment separately. Pencil grades differ in dose, capacity and the fraction that bonds to the surface; charcoal leaves a much larger loose fraction. Stable multiscale paper grain affects contact and capacity. Pressure affects the footprint, deposited mass, pickup and erasing. The optical lookup maps pigment mass to grayscale with a saturating exponential curve.

A persistent fingertip map picks pigment up, carries it and deposits it later, including after a lift. Pickup favors loose pigment; fixed pigment transfers more slowly. Mixing and transfer conserve the combined paper and fingertip mass exactly as integers. Erasing intentionally removes pigment. Clean paper and a clean fingertip cannot produce a mark.

## Defects corrected

- Zero pressure was clamped to a nonzero minimum. The material now leaves both page and fingertip unchanged at zero or negative pressure; zero strength also leaves both unchanged.
- Finger-cell mixing previously used the same friction at every pressure and strength. It now scales with contact, so light rubbing mixes the carried pigment less than a firm rub.
- Segments shorter than .001 pixels discarded all their traveled distance. The sampler now consumes every positive finite distance. The same path delivered as thousands of tiny segments produces the same stored masses as its unsplit counterpart in the regression fixture.
- Nonfinite material parameters are rejected before arithmetic or coordinate conversion; finite distant dabs are rejected before integer conversion.
- Tool constants and radius division moved outside the inner pixel loop. Footprint column coordinates and fingertip row indices are reused instead of recomputing two rounded finger coordinates at every covered pixel.

The pigment layout, optical import mapping and native cache format are unchanged. Existing pigment and fingertip caches do not require migration.

## Verification

Run the standalone suite from the repository root:

```sh
c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/test-sketch-material.cpp -o /tmp/test-sketch-material
/tmp/test-sketch-material
```

The optimized build and a separate AddressSanitizer/UndefinedBehaviorSanitizer build passed. The suite verifies pressure response, light/dark tone, repeated layers and bounded capacity; charcoal versus graphite mobility; pigment transfer and retained fingertip pigment; exact conservation even with fully loaded paper and fingertip; pressure-dependent finger friction; no mutation for zero contact or malformed values; event splitting with a pressure ramp and sub-.001 pixel events; page edges and maximum fractional footprints; and consistency between stored pigment and displayed grayscale. The sanitizer run detected no memory errors, undefined behavior or leaks.

The regression executable also prints timing for 500 smudge segments. For a before/after comparison, an identical microbenchmark was compiled against the pre-audit and final headers using `-std=c++17 -O2`. Nine alternating runs each warmed up 500 segments and measured 2,000 1.5-pixel segments per tool. Median per-run percentile results on the x86-64 host were:

| Metric | Before (microseconds) | After (microseconds) | Change |
| --- | ---: | ---: | ---: |
| Smudge p50, size 64, pressure .7 | 81.463 | 62.668 | -23.1% |
| Smudge p95, size 64, pressure .7 | 139.953 | 134.207 | -4.1% |
| Pencil p50, size 24, pressure .7 | 6.647 | 6.187 | -6.9% |
| Pencil p95, size 24, pressure .7 | 9.778 | 10.009 | +2.4% |

These are host material-loop measurements with scheduling noise, not reMarkable input/display latency. Pencil tail latency did not show an improvement. Raw runs and source hashes are recorded in `papersketch-v4-material-benchmark.json`.

## Physical limits

This is a deterministic grayscale approximation, not a measured simulation of a particular pencil, charcoal stick or paper stock. It does not model stylus tilt, edge-versus-point contact, wear and sharpening, graphite sheen, paper deformation, skin oils or detailed finger ridges. Imported bitmap pigment has an inferred 70% fixed fraction because an image cannot recover the original material. The fingertip grid approximates transport and mixing; touch comfort and perceived realism still require drawing on the actual tablet. No hardware-feel claim follows from these unit tests or the host benchmark.

## Tablet CPU benchmark

After the input and display probes completed, nine alternating before/after runs of `tests/bench-sketch-material.cpp` executed on the reMarkable 2 ARMv7 CPU. Median smudge p50 changed from 1028.094 to 650.982 microseconds (-36.68%); smudge p95 from 1095.094 to 699.854 (-36.09%). Pencil p50 changed from 74.498 to 63.873 (-14.26%) and p95 from 84.498 to 73.248 (-13.31%). These measure the material loop only. Raw runs and summary are in `papersketch-v4-material-arm.jsonl` and `papersketch-v4-material-arm-summary.json`. The temporary executables were removed after the benchmark. No input, screen, settings or user artwork was changed by this CPU test.
