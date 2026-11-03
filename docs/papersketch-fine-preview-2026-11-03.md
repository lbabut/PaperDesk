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


Deployment status: the atomic-permit preview renderer and first UI prototype are installed. The final UI disarm guards for layout/visibility/shutdown are built and ready locally. Installation of that final RCC is pending the user's saved-work confirmation after new pen activity was detected. The first pre-preview backup is `/home/root/.local/state/papersketch-install.xtsyK1` on the tablet. No further tablet restarts or input injection should run while that confirmation is pending.
