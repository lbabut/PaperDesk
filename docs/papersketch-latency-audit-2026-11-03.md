# Paper Sketch latency audit — 2026-11-03

Device: authenticated reMarkable 2, IMG_VERSION 3.29.0.153, Qt 6.10.3,
exact-build native preview backend. Source baseline: `346a58f` (4.2.7 plus
local latency/preview work). This is a local tablet trial, not a public release.

Follow-up user feedback exposed a coverage gap: the saved 2B/8px/strength-0.8/
legacy-tone-51 configuration disabled native preview, while the earlier detail
probes forced strength 1 / tone 0. The shaded preview also had empty first-tip
pixels at some subpixel phases. Fixes and a settings-specific regression are
prepared, with installation/live acceptance pending saved-work confirmation.
See [the preview follow-up](papersketch-fine-preview-2026-11-03.md#saved-settings-could-disable-the-entire-fast-path).
The earlier queue measurements do not establish optical responsiveness for the
user's actual settings.

## Finding and retained change

The small-nib material kernel is inexpensive. A standalone alternating ARM
comparison of 2500 contacts / 18500 samples per case measured 105693–106747 us
for HB 3px and 115082–115879 us for charcoal 3px: about 5.7–6.3 us per sample.
All optical, pigment, fingertip, burnish, wear and ink comparisons against the
frozen 4.2.7 kernel were exact. The earlier wide-contact cache does not provide
a material speedup for these tiny tips; more cache work cannot explain seconds
of queue age.

A separate, intrusive sampling pass took 150 main-thread PC/LR observations
at 20ms intervals during the diagnostic HB workload. 87 PCs were in Qt Quick,
36 in Qt Gui, 12 in Qt Qml and 10 in Qt Core. Exported symbols on PC/LR paths
included item/window transforms, event-target traversal and hover delivery.
This supports scene-wide input hit testing as the main cause in that window.
The sampling pass is excluded from before/after timing comparisons. The tracer
was detached and the target's TracerPid verified as zero.

The retained UI change places the 130 artwork tiles under a disabled **input**
parent. Offscreen paint, guides and provisional vector canvases are passive too.
They continue painting at full resolution. Pen/finger handlers remain on the
enabled sheet. A transparent native-mode event receiver consumes the duplicate
Qt stylus/synthesized-mouse stream over the canvas; the native reader still
owns all drawing samples. It does not cover toolbars or accept touchscreen
input. Its hover blocker is optional when supported by the runtime.

No paper resolution, material equations, pressure response, framebuffer offsets,
waveform constants, CPU governor or kernel settings were changed by this audit.
A window-scoped C++ event filter now consumes duplicate mouse/tablet events in
the canvas before Qt Quick delivery. It retains first entry/exit hover, forwards
complete first gestures without preceding hover, preserves toolbar drags crossing
the canvas, and recovers from lost releases. Touch, keys and other windows are
not filtered. Release/modal shutdown disables it.

In full screen the window filter is detached so the overlaid exit button remains
clickable. The passive/QML receiver remains in use. The native reader excludes
that button at contact start, preventing a delayed UI tap from becoming artwork
after the layout changes. An additional GUI guard supports older native modules.
A physical pen tap on Exit is checked against both stroke count and optical hash.

The size slider also suspends preview status polling/permit refresh while pressed,
and its preference debounce defers disk writes until the drag ends. The final
preview permit is refreshed on release. An earlier slider probe reached the
correct size but failed its 100ms interaction-gap budget (143ms); the resulting
I/O deferral is included in acceptance testing.

The native renderer also adds bounded queue-age histograms and reserves batch
storage. Queue age uses the existing native monotonic sample timestamp and one
clock read per dequeue batch. Counters reset independently of drawing state.
Percentiles above the histogram's 1000ms ceiling are conservative upper bounds
using the observed maximum, not precise quantiles.

Coalescing exact notifications across contacts, native rendering chunks and
holding UI busy across bursts were tried, correctness-checked and discarded:
they did not reliably resolve the large queue delays. Their trial sources and
measurements stay in ignored `work/`; they are not part of the installed change.

## Workload and comparisons

The dedicated probe draws 100 circles and 400 surrounding hatch strokes per
tool at a target 500 Hz: 1000 contacts and 7400 down samples overall. Diameters
are 4/6/8 drawing pixels. It checks each stroke's sample count, circle closure,
material marks, queue overflows and native preview contact continuity. Reports
also contain full optical and physical-state digests.

The original generator fully left pen proximity on every lift. That is a useful
stress case, but differs from normal small marks with the pen hovering between
contacts. The default now lifts the nib while retaining proximity. The original
case remains available as `--detail-proximity-exits`. Before/after comparisons
must use the same generator; do not compare the old full-exit results directly
to the new default.

The final alternating series uses the same installed native modules and the
same corrected generator. A runs the saved baseline UI using `--baseline-qml`;
B runs the passive-artwork/window-filter UI. In the paired filter cohort, mean
queue age was 2395–2571ms for A and 4.1–7.7ms for repeated B cases; release tails
were 1410–1465ms versus 4–11ms. All optical and physical-state digests matched.
Final acceptance is separately fingerprinted after the release-recovery and
fullscreen-control safety additions.

A preliminary passive-artwork/QML-receiver-only variant was much better than A,
but was variable. Its optional 100ms mean/tail budget failed once (119ms mean,
146ms tail). Those results remain in the local evidence. The window filter was
added rather than raising the latency budget. A trial of a separately versioned
hover handler was discarded: a host revision probe showed that the original
JavaScript property guard already had access to `blocking` on the tested runtime.

The 100ms checks are software material-queue/release regression budgets, not an
optical tracking promise. Single GUI timer gaps can still be larger.

## Final acceptance

The [machine-readable results](papersketch-latency-audit-results-2026-11-03.json)
retain per-run source/module fingerprints and exact synthetic output digests.

| Case | Mean queue age | Release tail | Result |
| --- | ---: | ---: | --- |
| Windowed, 500 Hz HB 3px | 10.2ms | 7ms | 500/500 strokes, 3700/3700 down samples |
| Windowed, 500 Hz charcoal 3px | 4.5ms | 8ms | 500/500 strokes, 3700/3700 down samples |
| Full screen, 500 Hz HB 3px | 24.6ms | 14ms | Complete input; 100ms budget met |
| Full screen, 500 Hz charcoal 3px | 12.7ms | 22ms | Complete input; 100ms budget met |

The full-screen pen tap returned to the normal view with zero added strokes and
an unchanged optical digest. The final size-slider probe reached size 79 with
35ms maximum active timer gap. Calibration/material/finger and rear-eraser probes
passed without runtime errors. All acceptance runs preserved the saved namespace.

The final 80px charcoal stress preserved all 1200 samples and matched baseline
wear, paper, burnish and fingertip state, but its optical digest differed. It had
a 2296ms release tail and a 242ms maximum GUI gap. The corresponding baseline run had 2671ms / 243ms. A single pair does not
establish a broad-brush speedup; large material contacts remain expensive. The
earlier wide baseline/final pair did match optically. The fidelity driver had
not fixed pen tilt, and fresh user pen activity occurred between sessions. The
driver now forces upright tilt and restores the original values, but a controlled
hardware rerun is pending saved-work confirmation. The differing latest optical
hash is not presented as verified equivalence or attributed conclusively to tilt.
The matched filter-cohort micro probe recorded 0–1ms native submission starts
and 16–33ms first submitted Qt frames. Those initial-frame timings are variable;
this audit's large, repeatable win is the queued-input reduction.

## Verification and limits

Host validation includes 22 native groups plus workload geometry, a disabled
native tile still painting in a real Qt frame, exact input/material fidelity,
queue timing/reset/tail bins, 61 QML passes (2 platform skips), and runner safety. The new native policy test covers actual mouse/tablet event
objects, touch/foreign-window pass-through, toolbar drags, direct taps, independent
button releases, lost-release recovery and disable/release cleanup.
Device result summaries and artifact fingerprints are generated after the final
series; raw journals, reports and ELF sampling files remain local in `work/`.

The runner restores original configuration and compares both the sketchbook
settings and all files in the production drawing/cache namespace. It records
installed native module hashes and harness/driver fingerprints. These checks
protect saved state during each run; they cannot preserve an unsaved in-memory
sketch. Production saves between runs were confirmed in the real app's journal
at 11:03:47, 11:06:55 and 11:07:03 UTC. The namespace grew from 12 to 14 files.
This newer user work was retained; the initial snapshot was never restored over
it. A separate read-only backup of the latest stable saved files was made.

Queue age, GUI timer gaps, native submission start, Qt tile/frame times and
release-to-drained tails measure different software stages. They are not optical
panel latency. Visible tracking and material handoff still need the user's
assessment; physical photon timing requires an external recording.

## Incident during inspection

At 09:40:49 UTC, invoking the firmware's `/usr/bin/screenshot --help` actually
sent SIGUSR2. Its handler was absent, so xochitl exited with signal 12 and systemd
restarted it. This was an operator error, not a drawing-test or optimization
failure. No screenshot was created. Unsaved pen activity had been present in that session; no drawing save was
found between its last pen activity and termination, and no recoverable copy
of those in-memory marks was found afterward. The saved sketch directory and configuration were copied locally into
`work/audit-preserved-state/` (directory 0700, files 0600) and retained. No saved
sketch was overwritten in an attempt to recover the unsaved marks.

Do not invoke that screenshot wrapper on this setup. The performance series does
not use screen capture or signals. Safe capture would require a separately
verified read-only method and must be outside timing measurements.
