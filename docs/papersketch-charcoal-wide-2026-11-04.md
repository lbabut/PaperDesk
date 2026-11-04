# Wide charcoal calculation — 2026-11-04

Status: installed and verified on the owner tablet. Nine final ARM suites and the extended UI/input probe passed; saved artwork and settings were preserved.

Wide normal and soft charcoal dabs now divide their scanlines between the caller and one persistent worker. Each dab joins before the next dab, so every pixel receives exactly the original sequence of deposits and burnishing. The tooth, pressure, tilt, wear, spacing and pigment formulas are unchanged. The two charcoal kernels are specialized at compile time.

The second thread is started lazily and used only on multicore systems for footprints with area at least 200 and at least 17 scanlines. Smaller footprints and other media keep the serial path. One shared worker serializes concurrent independent callers. Footprint columns and prepared fresh-contact responses are read-only during parallel painting; pigment, optical image and burnishing writes have disjoint scanlines.

No additional grain/contact lookup cache is shipped. Native tests compare the entire optical image, pigment, finger, burnish, ink, wear and sampling state against the frozen header from commit 031fd0235e679dc030c9e9d1f0c1e9e6502711ab. They cover all nine tools, three papers, pressure ramps, tilt, sizes 1–80, reused engines, mixed polished/tooth pairs, erasers and a shared-worker concurrency case.

## Reproduce

Run scripts/test-sketch-native.py for host coverage. The focused new test is tests/test-sketch-charcoal-speed.cpp; it requires C++17 and pthread support, with no Qt dependency.

Run scripts/run-sketch-tablet-regressions.py with --host, --host-key-alias, --key, --known-hosts and --output for nine ARM suites directly on the tablet CPU. Add --charcoal-benchmark for paired old/current normal and soft charcoal workloads at 48 and 80 px with constant and varying pressure. Benchmark cases verify complete physical-state equality after timing. No UI restart or input grab is needed; saved artwork hashes must remain unchanged.

After installation, use tests/run-sketch-native.py --extended-fidelity-probe --fidelity-brush-size 80 with the same SSH arguments for full input/rendering, charcoal layering, kneaded erasing, Clear and Care foreground regressions in an isolated namespace. This test temporarily restarts the tablet UI and restores the owner's files.

Timing results measure software computation, not optical panel latency. The initial paired tablet benchmark is reported below.

## Host validation

Focused host regressions passed for full-state charcoal equivalence, shared-worker concurrency, charcoal layers, kneaded strength, material, material realism, pressure, contact-cache compatibility, realism integration, blank-pigment migration, rapidograph integration and rear stylus erasure. The final worker test and both eraser/ink integrations passed after caching the multicore capability check. The ARM module build completed successfully.

These host results alone do not establish tablet speed or installation.

## Tablet CPU benchmark

The tablet reports two online Cortex-A7 processors. Each paired case processes the same 1200-sample zigzag stroke and asserts complete state equality. Both constant pressure 0.65 and varying pressure 0.10–0.95 are covered. The original kernel runs before the candidate in this initial paired measurement. These are single paired runs per case, not statistical latency bounds.

| Tool | Size | Pressure | Before ms | After ms | Time reduction |
|---|---:|---|---:|---:|---:|
| Normal charcoal | 48 | Constant | 1366.7 | 943.7 | 31.0% |
| Normal charcoal | 48 | Varying | 1260.0 | 938.1 | 25.5% |
| Normal charcoal | 80 | Constant | 3723.1 | 2354.9 | 36.7% |
| Normal charcoal | 80 | Varying | 3356.2 | 2145.6 | 36.1% |
| Soft charcoal | 48 | Constant | 1788.4 | 1268.0 | 29.1% |
| Soft charcoal | 48 | Varying | 1644.8 | 1162.7 | 29.3% |
| Soft charcoal | 80 | Constant | 4924.1 | 3200.5 | 35.0% |
| Soft charcoal | 80 | Varying | 4416.2 | 2912.3 | 34.1% |

At 80 px, computation time fell by 34–37%; at 48 px, by 26–31%. The result is identical per the full-state comparison. Owner artwork hashes were unchanged. [Raw paired report](papersketch-charcoal-benchmark-device-2026-11-04.json).

## Final shared-library and application verification

The final charcoal loop names its compile-time tool inside the row callback. This matters in the shared native module: the initial callback still read a captured runtime tool, retaining generic inner-loop branches. ARM symbol sizes confirmed the specialized charcoal row loops shrinking from 2608 to 1104 bytes. The generic path and all pigment formulas remain unchanged. The tablet benchmark now loads a PIC shared library with a small dlopen runner to exercise the same compilation boundary as the real native module.

| Tool | Size | Pressure | Before ms | After ms | Time reduction |
|---|---:|---|---:|---:|---:|
| Normal charcoal | 48 | Constant | 1348.3 | 864.1 | 35.9% |
| Normal charcoal | 48 | Varying | 1246.9 | 866.6 | 30.5% |
| Normal charcoal | 80 | Constant | 3671.8 | 2159.9 | 41.2% |
| Normal charcoal | 80 | Varying | 3320.9 | 1998.4 | 39.8% |
| Soft charcoal | 48 | Constant | 1759.1 | 1132.2 | 35.6% |
| Soft charcoal | 48 | Varying | 1607.2 | 1037.7 | 35.4% |
| Soft charcoal | 80 | Constant | 4859.2 | 2976.8 | 38.7% |
| Soft charcoal | 80 | Varying | 4362.9 | 2550.7 | 41.5% |

[Final shared-library benchmark](papersketch-charcoal-final-shared-benchmark-device-2026-11-04.json). At 80 px the isolated kernel takes 39–42% less time.

The complete raw-input application workload shows a smaller gain: 1200 shading advances fell from 4264.5 to 3736.9 ms (12.4%); release-to-drained tail fell from 2680 to 2232 ms (16.7%). The optical digest and full physical state match exactly. These are individual software runs, not statistical bounds or optical panel measurements. The native preview remains active during drawing.

[Final nine ARM suites](papersketch-charcoal-final-native-device-2026-11-04.json) and [final extended UI/input report](papersketch-charcoal-final-ui-device-2026-11-04.json). The UI report covers 1200 input samples without loss, charcoal layering, nine kneaded eraser cases, physical pressure ramp, actual Clear confirmation, Care background exclusion and foreground resumption. No QML runtime errors; owner artwork and saved files are unchanged.

The installed renderer, preview module and RCC hashes match this source payload. Manual XOVI startup and public release metadata are unchanged.
