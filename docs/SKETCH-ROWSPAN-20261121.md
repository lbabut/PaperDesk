# Conservative charcoal row spans (isolated UAT)

Baseline: input24 commit `6c41e2a`, 24 raw samples per GUI turn and 16 ms
publication. Canonical dirty sources and public releases are untouched.

The material kernel narrows X iteration separately for each ellipse row,
with a one-pixel guard and conservative near-tangent fallback. Original
coverage rejection and pigment arithmetic remain unchanged. Tools other
than charcoal, small footprints and nearly circular footprints retain the
original iteration. No points, pressure, tilt, wear or layers are dropped.

`tests/bench-sketch-rowspan.cpp` compares the entire material state against a
frozen baseline after 8100 cross-tool dabs and 2000 varied charcoal dabs,
plus timed stroke traces. Host and ARM checks pass. ARM trace timings are
microbenchmarks, not proof of interactive latency.

The device injector now uses absolute monotonic deadlines for the requested
500 Hz mode. Reports retain achieved rate and deadline lateness: catching
up may produce bursts and is not calibrated physical sensor emulation.
Relative sleeps previously achieved only 381 Hz in the loaded soft-charcoal
case; those measurements must not be described as a 500 Hz baseline.

At approximately 500 Hz, one contemporary baseline/candidate pilot measured
soft tilted charcoal queue p95 3570/2985 ms and release tail 3640/3028 ms.
Graphite GUI gap was 48/52 ms. All 1260 input points were retained. This is
an improvement in one heavy pilot, **not a performance pass**: charcoal
still fails the 100 ms queue and 150 ms tail limits. It does not measure
physical e-ink latency. Original settings and 17 checked cache files were
preserved; this is not a complete library audit.

Device reports and the final UAT decision are retained under Plan 400's
`sketch-rowspan-study-20261121` evidence directory. There is no production
release or claim that painting responsiveness is solved.
