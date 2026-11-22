# Earlier parallel charcoal rows — rejected after GUI testing

Base 802925a, installed rowspan raster29d4827. One material change: lower
parallel row dispatch footprint area threshold from 200 to100; retain
minimum16-row span, per-dab synchronization, ordered dabs and disjoint rows.
Pressure, pigment, points, sampling and publication remain unchanged.

Selected from ten independent ARM CPU probes. Six opposite-order timing
pairs show lower charcoal trace cost, but these are not GUI/panel latency
measurements. Do not describe this as a demonstrated responsiveness fix.

Built raster SHA256 e5cec0157c2c0b58bed9c099a433bf5df919e92654060233413052c1a518f314.
Material SHA256 1b5ae45231f5ea8b3c2b978c71af0ec62715b646d0c58a2197c0c63ea642a756.
Installer explicitly accepts frozen `--baseline rowspan-20261121` only with
matching actual hashes; a new fault-injected test covers that baseline.

Full host regression suite passed: 33 C++ and2 C executables. Seven installer
fault-injection tests and six report-validation tests passed. Product checksum
verification and git diff whitespace checks passed. ARM exact-state checks
passed in three independent executions of the standalone probe.

Owner subsequently confirmed current scratch could be discarded. On 22
November the candidate was temporarily installed for guarded comparisons.
The existing rowspan baseline was remeasured first; all high-rate cases actually
delivered approximately 500 Hz and retained1260 samples per tool.

| Soft tilted charcoal, approximately500Hz | Baseline | Candidate1 | Candidate2 |
| --- | --- | --- | --- |
| GUI gap ms |157|189|174|
| Queue p95 ms |2711|2814|2807|
| Release tail ms |2752|2860|2848|

No useful interaction improvement was established; both candidate attempts
still fail the100ms queue and150ms tail limits. These few runs are not a
statistical proof of universal regression. An ordinary baseline pilot also
had a209ms GUI-gap outlier (queue52/tail83), illustrating runtime variability.
No ordinary candidate cohort was needed after failure of the targeted heavy
case. Physical sensor/e-ink latency was not measured.

All four reports preserve the original setting and17 checked cache files,
not a full-library audit. No input overflow/pending remained. The candidate
was rolled back with the owned backup. Final actual modules were verified as
rowspan29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7
and ink5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7.
xochitl was active and the owned runtime monitor mask was removed.

Decision: reject; no new accepted UAT or production release. Product binary
on this experimental branch is the rejected candidate, NOT current installed
state. Full raw reports remain in Plan400 `sketch-parallel100-gui-20261122`.
