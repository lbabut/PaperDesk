# Paper Sketch: material contact cache and shorter input batches

Baseline: released 4.2.7, including fine/fast pen fidelity, rear eraser and tool preferences. Work is isolated from the older canonical checkout on `feature/sketch-material-latency`, based on its latest clean feature baseline. Installed tablet renderer and QML resource hashes matched 4.2.7 before measurement.

Wide pencil and charcoal dabs evaluate the same contact and pigment capacity for each unburnished tooth value many times. A 256-entry transient cache retains the exact double contact and integer capacity for a tool/pressure pair. The scalar path remains for polished pixels and footprints below the area of a 12px-radius circle. The area gate avoids unnecessary table construction for narrow tilted tips. Tool and exact pressure changes rebuild the table. Width, tilt, strength, paper and wear continue to affect their existing parts of the material model. Cache storage adds approximately 4 KiB per engine with no per-dab allocation.

The GUI receives up to 32 raw pen events per callback, down from 64. All remaining events stay queued in order, including short contacts and release boundaries. This allows Qt to paint between shorter chunks of exact material work. The 16ms damage publication timer remains unchanged.

Expression ordering, rounding, sample spacing, pigment deposition, saved formats and artwork semantics are preserved. No approximate preview, sample skipping, real-time prediction or physical-model simplification is introduced.

## Validation

- All 20 existing host native regression groups passed with the contact cache.
- The new differential test compares full state against the frozen 4.2.7 kernel across nine tools, three papers, seven widths, changing pressure, tilt, ink, finger transport, erasers and layered/polished surfaces. It passed on the host and tablet. It passed again on the host after changing the cache eligibility gate to area.
- The final 32-event input regression passed, including a complete 600-point curved path, 80 tiny contacts and subpixel reversals. It also checks the batch bound.
- The ARM extension builds with the existing compiler flags.
- Tablet application probes use isolated settings/pages, compare saved artwork hashes and restore the user's application after completion. Each reported passing probe retained all 40 tiny contacts and all 1200 shading samples, with zero queue drops and no runtime errors.

`tests/test-sketch-contact-cache.cpp --benchmark` alternates baseline and candidate over 1200-point shading paths and asserts full physical equality after each pair. The frozen fixture is intentional: results are compared against the previous model rather than a restatement of the optimized formula. Timing has no pass/fail threshold. Raw diagnostic reports remain local in `work/`.

## Device observations

Standalone 80px charcoal computation, alternating baseline/candidate/candidate/baseline: baseline 4.234/4.232 s, candidate 3.481/3.461 s, or 18.0% less computation time. Optical, pigment, fingertip, burnish, wear, ink and sampler hashes matched in all four runs.

Application stress probe with 1200 fast 80px charcoal samples:

| Variant | Native advance time | Largest GUI observer gap | Completion after release |
| --- | ---: | ---: | ---: |
| 4.2.7 baseline, 64 events | 3.787 s | 448 ms | 1824 ms |
| Contact cache, 64 events, trial 1 | 3.180 s | 394 ms | 1265 ms |
| Contact cache with area gate, 64 events | 3.126 s | 517 ms | 1021 ms |
| Contact cache with area gate, 32 events | 3.115 s | 200 ms | 1279 ms |
| Selected 32-event variant, repeat | 3.092 s | 200 ms | 1239 ms |

The 64-event cache-only variant reduced computation but did not reliably improve the worst pause. The selected 32-event variant combines reduced computation with shorter GUI bursts. A previous attempt using smaller batches without this computation improvement had increased the release tail and was rejected.

First-tile timing varied by a few milliseconds between runs; no onset improvement is claimed. These measurements describe software computation and event-loop/display callbacks, not optical e-ink latency or statistical ceilings. Significant lag remains in this deliberately heavy workload.


The repeated selected variant preserved all contacts/samples and saved-artwork hashes again. Final installed native/UI checksums match the local payload, and xochitl is active with the original sketchbook restored. This is a local tablet update, not a new public release. The original released module and artwork backup remain at `/home/root/.local/state/papersketch-install.iyUyl6` on the tablet.
