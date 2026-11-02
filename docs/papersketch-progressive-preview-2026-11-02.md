# Progressive ink preview — tablet prototype

Scope: pencils and charcoal (tools 0–5), using the material bitmap engine.
Materials has a session-only Live preview switch, OFF by default; other tools keep the existing
path. An older native extension automatically falls back to synchronous drawing.
This is an experimental tablet build, not a new public download release.

## Pipeline and state ownership

The GUI paints provisional pigment into a transparent 600×800 layer. Native
tiles composite and dither it with the exact page in the same paint operation.
Stationary contacts use drawPoint explicitly. This layer is never serialized,
exported, or used as input to the material model.

The GUI transfers ownership of the exact material, fingertip and physical state
to one worker using moves. Every pressure/tilt sample from the existing raw-replay
path is processed in sequence with the same sampler, calibration and kernel.
The worker lazily initializes only touched optical tiles from the current page,
and publishes immutable 128-pixel tile snapshots with a completed sequence number.
The GUI applies those exact snapshots and removes only the matching preview
prefix. Later preview samples remain visible, including overlapping segments.

The page's owned pixel storage is pinned until the worker joins. The GUI uses
a separate writable QImage wrapper around that storage, so pinning it does not
force Qt to copy the full page on first write. The worker reads a tile only once,
before publishing that tile; GUI writes occur only after that publication, so
pixel accesses do not overlap. If a reader causes the GUI wrapper to detach,
the pinned source remains alive until join. Ownership is restored before save,
export or lifecycle operations. Worker optical pixels outside initialized tiles
are never inspected or exported; the GUI's complete image remains authoritative.

Worker input and provisional geometry are limited to 512 points each. Outstanding
exact output is coalesced by tile and bounded to one page. Under overload, input
is retained: the stroke drains and continues synchronously rather than dropping
samples or allowing unlimited memory growth. The worker runs at lower Linux
CPU priority than input/paint callbacks.

Cancel records original optical, material and burnish tiles lazily; retaining a shared whole-page undo
image caused a large GUI-thread copy on first delivery and was removed. Save,
export, page replacement, material mutations and release join outstanding work
before accessing exact state. Save also ends the active QML stroke so its
metadata matches the saved bitmap. After a drain, continued input uses the exact
last coordinates and sampler phase. Persisted material/cache formats are unchanged.

## Validation and interpretation

18 native test groups passed during development, including exact image, pigment,
fingertip, wear, burnish and ink equality over 18 loaded trajectories on three
paper stocks, calibrated pressure, 700-point bursts and bounded queues, cancel after delivery, saving
mid-stroke and continuing, reset and release. The actual native tile paint is
tested for provisional pixels before exact delivery, followed by exact optical
pixels and binary display pixels. 54 QML checks passed (2 platform skips).

The first iteration failed the latency comparison: initial state cloning plus
missing first-point preview and a GUI full-page detach delayed the first tile.
Those results are retained locally as trial evidence. Local device reports record all input samples, display checks and saved-art
checks. Raw device reports are not published. Software tile/frame timing does not measure optical panel latency.
Native advance timings measure GUI dispatch in progressive mode; exact worker
compute and initialization times are reported separately in progressive_stats.

Manual assessment of grain/width changes during replacement is still needed.

The initial full-state-copy implementations were rejected. Detailed machine-readable
reports remain local; this document contains the comparison needed for review.

## Decision: keep experimental, default OFF

The transfer variant passed correctness checks but failed the responsiveness
acceptance criterion on this tablet. Individual A/B observations:

| Case | Synchronous first tile | Preview first tile |
| --- | ---: | ---: |
| Fresh HB | 33 ms | 33 ms |
| Fresh charcoal | 30 ms | 40 ms |
| Layered HB | 25 ms | 29 ms |
| Layered charcoal | 23 ms | 36 ms |

In the 250 Hz long-shading probe, the maximum active-input observer gap changed
from 56 to 81 ms for graphite and from 116 to 195 ms for charcoal. All 1,259
points in each shading case were retained; no blank frames after a visible mark
were observed. Worker state initialization fell from roughly 60,000 us to 2–3 us,
but preview composition/display still added enough cost to lose the comparison.
These are single software-observer runs, not optical panel measurements or
statistical ceilings. They do not justify a claim of faster drawing.

The prototype remains available for manual comparison, with synchronous ink as
the default. The disabled path paints the exact tile directly and does not retain
a shared display copy that would add a Qt copy-on-write cost on the next paint.
No new public release package is published. A separate experimental GitHub branch
holds the code and trial evidence. The acceptance target is not met.

The final realism check finished successfully on the device, but the combined
host job hit its 300-second deadline before report/cleanup. Its passing result
was recovered from the device journal; the saved original configuration was
restored, the isolated diagnostic app was removed, and the user's sketchbook
was reopened. The recovery report records this limit and preserved document hash.
