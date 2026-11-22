# Ten independent end-to-end painting pipeline experiments

Base: installed rowspan802925a, raster29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7.
All experiments are independent, not cumulative. No material kernel changes,
point dropping or pressure simplification. Canonical343 dirty entries untouched.

Each variant was built as a native module, passed targeted input-fidelity and
material-integration host tests, then underwent one guarded actual Sketch GUI
probe with approximately500Hz Linux evdev input. This is not calibrated pen
hardware or physical panel latency. Each temporary installation had a unique
backup and was rolled back to the verified baseline before the next probe.
These are research trials, not new accepted user UAT or production releases.

| Independent variant | Charcoal GUI gap ms | Queue p95 upper ms | Release tail ms |
| --- | --- | --- | --- |
| Control before |161|2755|2797|
|1:12 samples per GUI turn|119|3989|4062|
|2:20 samples per turn|150|2949|3000|
|3:28 samples per turn|165|2585|2640|
|4:8ms publication timer|180|3005|3047|
|5:12ms publication timer|152|2883|2943|
|6:20ms publication timer|140|2637|2684|
|7:Bounding rectangle for accumulated display damage|150|2644|2689|
|8:Explicitly reserve each QVariant event row|153|2631|2666|
|9:Ready-material fast path|147|2748|2792|
|10:Conservative43px damage radius instead of two footprint evaluations|168|2764|2797|
|Control after|165|2641|2691|

Decision: no candidate admitted to new UAT. All heavy probes fail unchanged
queue100ms/tail150ms gates. The small apparent gains of variants3/6/7/8 are
not convincingly separated from the change between controls. Variant1 trades
shorter GUI stalls for substantially worse painting backlog. Variant10 also
increases graphite GUI gap to157ms vs controls47/52ms, with more tile paint
work. Do not infer a universal slowdown or statistical significance from these
single pilots. No full regression cohort or additional ordinary candidate
tests are claimed for unpromising probes.

All12 GUI reports preserve the original setting and17 checked cache files;
1260 input samples/tool, no overflow/pending input. This is not a full-library
audit. Actual input rate range and complete stage counters are in the attached
sanitized `sketch-pipeline-ten-20261122/summary.json`.

Two harness setup issues were corrected without weakening correctness gates:
the performance wrapper requires an absent output directory, and the input
test had a fixed26-batch assertion for601 events at batch24. For variants1..3,
that expectation is now ceil(601/batch); all600 path points, final bitmap/mass,
short contacts and subpixel reversals remain required. Those initial counter
failures occurred before installing those variants; all three were rerun with
the corrected expectation. Original failed logs are retained locally.

Seven fault-injected installer tests and six report-validation tests also
passed. Final xochitl active, baseline raster/ink hashes restored and verified,
owned runtime monitor mask absent. No production/main/site change.

Reproduction in a fresh isolated checkout (explicit owner-approved disposable scratch only):
`python3 scripts/build-sketch-pipeline-ten.py`, then
`python3 scripts/run-sketch-pipeline-ten.py --safe-state-confirmed`.
The run script restarts UI, uses strict host verification, checks saved-state
preservation and restores each native-module backup. Never run it on unsaved
personal work or from an unrelated current baseline. Full local artifacts are
retained in Plan400 `sketch-pipeline-ten-study-20261122`.

Next useful investigation: measure whole input-handler/render-loop cost and
consider an isolated bulk/native processing design; these results do not prove
that the processor has reached an absolute limit.
