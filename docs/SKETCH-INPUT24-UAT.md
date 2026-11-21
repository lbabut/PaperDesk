# Input scheduling candidate: 24 samples per GUI turn

Experimental UAT candidate, not a release or a proven global responsiveness fix.
Based on charcoal UAT, using the original portable compiler profile and the
unchanged 16ms display-publication period. Only `takeInput(32)` becomes
`takeInput(24)`. Every sample, contact boundary, pressure/tilt and material
operation is retained; no downsampling or simplified brush is introduced.

Earlier 4/8/16-sample batches had excessive queue/tail penalties. This study
tests the previously unmeasured intermediate size, not a reinstallation of
those rejected variants or the rejected Cortex-A7 profile.

Three actual tablet runs per column, same graphite/charcoal shading workload:

| Charcoal software timing, ms | Original 32 | Candidate 24 |
| --- | ---: | ---: |
| GUI timer gap median / worst | 130 / 136 | 96 / 149 |
| Queue p95 upper median / worst | 40 / 42 | 45 / 47 |
| Release-to-drained median / worst | 100 / 117 | 77 / 104 |

The candidate improves median gap and release tail in this small sample,
but has a higher worst gap and queue p95. Both variants pass the same absolute
200/100/150ms engineering budgets. No statistical significance or universal
speedup is claimed. The benchmark bypasses physical input sensing and does
not measure optical e-ink response or idle menu latency.

Graphite gap median/worst is 53/54ms vs original 50/50ms; release tail39/77ms
vs30/74ms. These small regressions are retained in evidence, not hidden.
Human UAT is needed before accepting this tradeoff.

Regression coverage adds 600-point normal and soft charcoal paths checked
against unbatched processing (exact image, pigment, finger, burnish and wear;
no missing or pending input). Existing graphite/contact/overlay tests remain.
Expected batching count changes from 19 to 26 for 601 events; the assertion
continues to verify complete ordered delivery rather than being removed.

31 C++ +2 C host regressions and five installer fault tests passed. Three
tablet runs passed correctness, sample count, preservation and speed budgets.
Original document setting and checked material caches preserved in each run;
this is not a full-library backup.

Raster SHA256:
`be89afb13593bdb2fbcf193d22fc972c3208ae776e878fb7739561f5035e4858`.
Ink stays `5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7`.
Installed RCC/QML were not changed. Public downloads/main remain unchanged.

Raw results retained locally in Plan400's on-device scheduling study. The
candidate was temporarily rolled back after its three runs so a separate
publication-period variant could be tested without mixing variables.

After comparison, this input24 candidate was selected for HUMAN UAT only.
The separate24ms publication variant had median/worst GUI gap118/175ms,
queue47/57ms and tail92/135ms, and was removed. Original16ms publication is
retained here. This is a measured tradeoff, not a claim all apps/menus are
faster or that the reported global slowness has been fixed. Physical display
and real stylus usability still need owner evaluation before acceptance.

Final control-slider probe passed: active GUI gap29ms, detected value to
submitted frame1ms, no QML runtime errors. Contact to detected value/frame
114/115ms includes slider travel until size>5, not pure dispatch latency.
The whole probe included a139ms gap before active dragging. No baseline
controls A/B is claimed. Original document setting and17 checked caches
were preserved, native/app hashes verified, xochitl/XOVI active, failure
monitor restored to static and diagnostics launcher removed.

Final device recovery to original32-sample UAT:
`/home/root/.local/state/sketch-charcoal-uat.6yu1aS/rollback.sh`.
Use guarded restart/mask handling when invoking recovery, not blind reinstall.
