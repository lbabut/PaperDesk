# Paper Sketch fine-pen preview trial

Baseline: local `1a40a25` tablet update on released 4.2.7. Target: a visible trace following rapid, small pen movements, rather than throughput of an 80px charcoal brush. Firmware/build was authenticated as reMarkable 2, IMG_VERSION 3.29.0.153; the existing native framebuffer extension recognized its exact ELF build ID and screen layout.

## Observation and selected path

In a 250 Hz, 24x24 drawing-pixel loop probe, native advance time averaged 0.064 ms for HB 3px and 0.120 ms for charcoal 8px, including nested damage dispatch. First Qt frames arrived about 30ms after evdev contact. The material computation is only a small part of this path. Optimizing its cache alone cannot remove GUI event/paint latency.

The prior 600x800 progressive material prototype added composition/transfer costs and failed its tablet comparison. This trial instead reuses the existing xochitl fast-pen display backend: a passive native pen reader sends a simple black silhouette without waiting for QML input delivery or Qt tile painting. It coalesces updates at 16ms and sends the first mark immediately. It does not allocate/copy a page-sized preview or move the physical model between threads.

The ordinary material engine still consumes every raw sample, including pressure, tilt and contact boundaries. Its bitmap, pigment and tool state remain authoritative. The provisional framebuffer is never read back into artwork, persistence or export. Pressure calibration anchors and selected nib size/tool are forwarded for approximate width; grain, tilt/wear appearance and final tone come from the exact material path. The provisional trace can be darker or differently shaped than the finished material.

Eligibility is limited to pencil/charcoal tools 0-5 and ink 8 at sizes 1-16, normal tone/strength, a visible and ready drawing surface, and a matching native preview capability. Smudge, erasers, wide tips and unsupported xochitl builds retain the ordinary path. No OS/kernel, CPU governor, waveform constants or private framebuffer offsets were changed. The previously verified build-ID/layout gate remains required.

## Handoff and lifecycle

At release, the GUI invalidates the exact stroke area, including a bounded margin covering provisional width, and repeats that repair after 40ms to cover mask-release ordering. Repair regions accumulate across quick contacts and reset on page replacement/release. This changes display invalidation only.

Dialog, visibility, layout and shutdown transitions write an off permit. Permit replacement uses QSaveFile atomically: the initial asynchronous file overwrite caused a reader race and interrupted HB preview three times during one physical contact. That first trial was rejected. The fixed trial submitted exactly one continuous native preview per injected contact. Active fine-preview permits are checked at a 16ms interval; a new contact also checks the latest permit. A dropped input stream releases its mask and suppresses preview until a release boundary. Background heartbeat activity is restricted to eligible tools.

The UI requires matching renderer helper methods before enabling this path. Missing/older helpers, stale readiness and unknown builds fall back to the original drawing path.

## Evidence

- All 21 native host test groups passed with the display-handoff changes. A subsequent focused publication test passed the final atomic permit writer against a concurrent reader, accumulated repair over disjoint contacts, no physical-pixel mutation during repair, and reset cleanup.
- Native C regressions passed permit validation, tool/pressure widths, clipping and binary framebuffer pixels, plus 1000 reports coalesced to 126 updates with a final tail flush.
- 58 Paper Sketch QML checks passed, 2 platform skips. Tablet-runner safety checks passed.
- Fixed native-preview micro probe: first submission began 1ms after evdev contact for both HB 3px and charcoal 8px. The native worker reported one continuous contact per case and released its mask. Each exact input path retained 225 changing-position samples, with zero overflow and an empty queue after release.
- A matching preview-off run produced identical full optical SHA-256 digests, burnish/finger digests, paper kind and tool wear for both cases. Its first submitted Qt frames were 32ms and 30ms after contact.
- These are different software pipeline milestones: native callback submission start versus a submitted Qt frame. They are not an optical latency measurement or a 30-to-1ms measured panel-speed claim.
- The fine fidelity probe preserved all 40 short contacts and all 1200 thin-charcoal samples, with no runtime errors, no queue drops, and unchanged saved-artwork hashes. Native stroke count was 40 after the short-contact sequence and 41 after the long stroke. The diagnostic deliberately blocks the GUI for 150ms; native status is sampled when that callback resumes, rather than observing the physical screen during the block.
- Wide-brush probes still passed sample/artwork integrity, but did not establish a responsiveness improvement: observed maximum GUI gaps were 242/247ms and release tails 2092/2112ms. Earlier local 32-event runs observed 200ms and 1239-1279ms. No broad-brush speedup or absence of regressions is claimed by this trial.
- A settled alternating standalone kernel recheck retained the earlier cache improvement: optimized 3.484/3.461s versus reference 4.253s, with identical core/physical validation hashes. An earlier overlapping run was variable; new user pen activity was subsequently observed, so no further interruption or clean app A/B was attempted without asking the user to save.

Raw device reports, source/resource hashes, backups and logs stay local in `work/`. Public release metadata and website deployment are unchanged. This remains a local tablet prototype pending the user's assessment of the visible trace and correction transition.


Deployment status: superseded by the [follow-up latency audit](papersketch-latency-audit-2026-11-03.md). The final UI disarm guards, passive artwork layer and scoped native pointer filter are installed in the local tablet trial. The first pre-preview backup remains `/home/root/.local/state/papersketch-install.xtsyK1`. See the follow-up audit for the inspection incident, saved-state verification and final acceptance measurements. Public release metadata and website deployment remain unchanged.

## Tool-matched provisional shade (follow-up)

The leading trace now approximates the selected material's gray instead of
painting every tool solid black. Six 17-entry pressure tables are sampled from
upright size-3 material lines on fresh plain paper; calibrated pressure selects
and interpolates the shade. Rapidograph remains opaque black. This is a cheap
appearance estimate: paper kind, accumulated pigment, wear and tilt still come
from the authoritative material renderer.

The existing DU/pen waveform remains binary. A stable screen-anchored 8x8 Bayer
pattern, with the same thresholds as the final fast display conversion,
represents the provisional gray. Only black dots are written; skipped pixels
and masks remain untouched, preserving existing artwork under a light stroke.
Repeated samples do not progressively darken the pattern. Very light pressures
retain a minimum 1/8-density guide, then the ordinary release repair restores
the exact pixels. No page buffer, allocation, file write or material calculation
was added per pen sample.

Host calibration regressions compare all 102 table anchors with actual material
output and check every Bayer threshold. Native C regressions run on both host
and tablet ARM, checking density, stable repeated coverage, clipping, unchanged
pigment/masks at skipped pixels, opaque ink, legacy white erasure and update
batching. The test framebuffer is private RAM and never touches the real panel.

Deployed SHA-256 was verified against the local ARM module. The on-tablet
500 Hz detail regression passed 500 contacts / 3700 down samples for each of
HB and charcoal. Mean queue age was 4.23 / 4.46ms; release tails were 6 / 10ms.
Each tool recorded all 500 native preview contacts. Full optical digests and
physical state matched the preceding final acceptance run; all 14 saved files
were preserved. These are software queue timings, not optical panel latency.
The physical appearance still needs the user's assessment during ordinary
hand drawing. Sanitized evidence: [shade results](papersketch-preview-shade-results-2026-11-03.json).

## Thin-tip visibility correction (subsequent user feedback)

The shaded guide could submit an update containing no black pixel at the actual
nib. At gray 223, a sweep of 1024 subpixel positions produced 920 empty first
marks at width 1, 632 at width 2 and 168 at width 3. This is a demonstrated
visibility defect, separate from queue age or physical panel response time.

The preview now pins one black physical pixel at the latest in-canvas tip,
independently of the body raster. This deliberately prioritizes a visible
location cue; the one-pixel tip can be darker than its selected material.
Shading across the rest of the footprint and exact release repair remain.
The same sweep now has zero empty marks at all three widths. Regression coverage
also asserts each tip lies within the submitted repair box. The endpoint pixel
never writes outside the canvas or into saved artwork.

The provisional update interval is reduced from 16 to 8ms. Polling a pending
update uses the remaining deadline instead of restarting a full wait after the
last input report. Permit checks retain their 16ms rate. For a deterministic
500 Hz stream, 1000 reports now generate 250 regular updates plus one tail.
Status adds a monotonic-input-clock capability, maximum event-to-submit age and
maximum update-call duration, allowing future device runs to distinguish native
input backlog from framebuffer submission cost. These measurements do not
measure physical pixel visibility.

Private-framebuffer regressions passed on host and tablet ARM, including all
3072 thin-tip positions, clipping, mask preservation, legacy erasure, pending
flush deadlines and update batching. The standard native suite now includes
this C test automatically. Installation and live panel regression for this
follow-up require saved-work confirmation; the previously deployed shade-only
module is retained until that confirmation arrives.


### Saved settings could disable the entire fast path

Read-only inspection found saved tool 2, size 8, strength 0.8 and legacy tone 51;
the running preview permit was `off`. The old eligibility predicate required
strength exactly 1 and tone exactly 0. Thus the full-strength diagnostics did
not exercise the configuration used in this saved session. This is a separate,
more direct cause than sparse-tip visibility: that configuration never armed
the native preview at all.

Eligibility now accepts valid material strengths from .05 to 1, with an explicit
`shade_strength` native capability for fractional strengths. The fine permit
accepts an optional final strength argument (old nine-field permits default to
1); invalid and trailing arguments are rejected. The estimated optical density
scales with strength, and the latest one-pixel position cue remains visible.
Rapidograph remains opaque, consistent with its exact material path. Legacy
tone no longer disables preview: the native bitmap renderer already passes
zero tone to the material engine, so that old vector preference does not change
its authoritative output. Saved user settings themselves are not rewritten.

The QML regression covers the observed 2B/8px/.8/51 configuration and capability
fallback. A new `--detail-user-settings` tablet mode uses it and charcoal 8px
at the same strength/tone, requiring native arming before input injection. Host
validation passed all 23 native groups plus C preview/workload checks, and
63 QML checks with 2 platform skips. No live restart or new module installation
has occurred without the pending saved-work confirmation.
