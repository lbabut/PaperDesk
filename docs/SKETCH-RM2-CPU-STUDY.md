# reMarkable 2 CPU profile study, 21 November 2026

Status: experiment, NOT an accepted responsiveness improvement. Do not promote
this branch's native module to a release. No material algorithm, footprint,
input sample count, pressure rule or saved format is changed. Canonical dirty
PaperDesk tree and public releases are untouched.

Opt-in build:
`PAPERDESK_SKETCH_CPU_PROFILE=rm2-cortex-a7 python3 scripts/build-sketch-raster.py`

Portable remains the default build profile. The experiment uses `-O3
-mcpu=cortex-a7 -mfpu=neon-vfpv4 -ffp-contract=off` instead of `-O2`.
No fast-math, clock/governor modification or overclocking. Target hardware
was checked as two ARM Cortex-A7 cores (part 0xc07) with NEON/VFPv4.
This is NOT a compatibility claim for other devices.

## CPU-only A/B

`tests/bench-sketch-cpu-profile.cpp` was built twice from identical material
source and run on tablet in portable/profile/profile/portable order. Raw
output: `sketch-rm2-cpu-ab-20261121.jsonl`. Means in microseconds:

| Tool | Portable | Profile |
| --- | ---: | ---: |
| Graphite | 63758 | 62586 |
| Normal charcoal | 322452 | 299188 |
| Soft charcoal | 428596 | 399206 |
| Eraser | 121528 | 119050 |
| Finger | 495870 | 498886 |
| Ink | 628490 | 620227 |

All four runs produced identical per-tool state digests of pigment, optical
image, finger, burnish, ink and wear. This covers these traces, not every
possible drawing. Charcoal computation is about 7% faster; other changes
are small, and finger was slightly slower. Two runs per variant is a small
sample, not a universal speed claim.

## Actual application timings

Three identical synthetic shading runs per build, same RCC/QML and input:

| Charcoal software timing | Portable UAT | Profile |
| --- | ---: | ---: |
| GUI gap median / worst, ms | 130 / 136 | 99 / 168 |
| Queue p95 median / worst, ms | 40 / 42 | 52 / 76 |
| Release tail median / worst, ms | 100 / 117 | 94 / 120 |

Both pass initial absolute budgets, but the profile is not a clean improvement:
median GUI gap improves while worst gap and queue age worsen. No statistical
significance is claimed from three runs. Passing an absolute test is not
evidence of a faster version. Keep original UAT as installed comparison state.

Host regression runner: 31 C++ executables and 2 C executables passed.
Installer: five fault-injected tests passed, including current-UAT hash pin.
Two standalone ARM regression executables (material realism and charcoal
deposit/compatibility) also passed with the profile's exact compiler flags.
Hardware shading: exact expected input samples, no overflow/pending input,
display correctness, original document setting and checked caches preserved
in all three runs. Preservation is scoped, not a full-library backup.

Candidate raster SHA256:
`c0eb7d92639285bc3d7a7b7d01284467d2d5797bb872fb5c03a6e3c41e7f7662`.
Original UAT raster:
`227dd2ffedc7c1f867080d08ace59c40f545c09c333efd60537b4c8120f3e975`.
Unchanged ink:
`5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7`.

The controls probe now records injected finger-contact to first observed value
and submitted-frame upper bounds. It bypasses the physical touch sensor and
does NOT measure optical e-ink latency. A software-only test cannot prove why
the owner perceives global slowness or establish physical panel speed.
The observed value threshold is brushSize>5, so contact-to-value includes slider
travel and polling; do not label it pure input dispatch latency. One profile
controls run passed: active GUI gap 36ms, first detected value to submitted frame
1ms. Contact-to-detected-value/frame was 115/116ms; whole probe had a 131ms
gap before active dragging. No baseline controls A/B was performed.

Final device state was restored and verified: original UAT raster/ink hashes
above, unchanged installed RCC `3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1`,
XOVI preload present, xochitl active, temporary failure-monitor mask removed,
diagnostics app no longer in the launcher. Device recovery backup for this
trial: `/home/root/.local/state/sketch-charcoal-uat.0Myc8X/rollback.sh`.
