# Rejected responsiveness experiments — 2026-11-21

EXPERIMENT ONLY. Not accepted for UAT or production. The tablet was restored
to the original charcoal UAT: raster 227dd2ff..., ink 5fb519b9..., RCC 3207f8fb....
The owner allowed sacrificing the current drawing, but no original drawing
had to be deleted; diagnostic runs used isolated Settings/cache namespaces.
The original document setting and 17 checked cache files remained unchanged.

## Controlled tablet measurements

One run per variant, same 1260-sample evdev shading pattern, normal charcoal
size 38, full screen, varying pressure. Not a camera/optical panel measurement.
GUI gap is the longest active-input timer gap. Tail is diagnostic completion
minus injected pen release, including its final checks.

| Variant | GUI gap ms | Tail ms | Decision |
| --- | ---: | ---: | --- |
| Original 32 samples/turn | 205 | 85 | Reference; responsiveness issue remains |
| 4 samples/turn | 114 | not recorded | Reject: queue age reached 4180ms |
| 8 samples/turn | 100 | 883 | Reject: insufficient throughput |
| 16 samples/turn | 139 | 290 | Reject: tradeoff, not a clean improvement |
| Native motion batching, 32 samples/turn | 220 | 81 | Reject: no GUI-gap improvement |

The native batching API preserves each sample, tool, pressure, tilt and contact
boundary. It does not decimate geometry. Host regression compares complete
pixels/material/finger/burnish/wear/sampler state for 600 curved points with
HB and both charcoals, and tests end/mismatched-contact boundaries. It is
retained here for reproducible research, NOT as a shipped fix.

The shading harness previously required legacy pressure-match counters even
in raw-input mode, where those counters correctly remain zero. It now checks
exactly 1260 raw samples, zero overflow and empty pending input in that mode;
the existing geometry, optical/display and <200ms gap checks remain. Per-case
queue reset and completion timestamps make queue/tail comparisons possible.

Next dependency: the owner must identify whether perceived slowness is the
live tip, pigment catching up after release, smudge/eraser, menu interaction,
or physical e-ink refresh. These isolated software timings cannot distinguish
physical panel perception. Do not install these prototypes as a proven fix.
