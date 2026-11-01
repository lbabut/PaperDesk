# Paper Sketch 4.1.2 drawing latency audit

Baseline: released 4.1.1, commit `202fc75`. Device: reMarkable 2, firmware 3.29.0.153. These are software observations of input, image and tile submission, not camera measurements of the e-ink panel.

## Final changes

The pen's passive grab now starts the stroke using the current event's coordinates. Drag updates continue that stroke, and release finishes it once. This removes waiting for drag activation or pen release. The event copy is necessary on this device: the handler-owned point remained `(0, 0)` for tablet-synthesized mouse events. Short movements below the tap threshold no longer create a second release dab. Stationary and 1/3/6/12-pixel input regressions pass.

The material kernel shares an exact double-precision lookup of all 65,536 tooth/burnish responses. Pressure, pigment and sampling equations are retained. The tradeoff is 1 MiB per process, with no per-page or persisted-format increase. [CPU evidence](papersketch-drawing-cpu-20261101.md) records 17.96% less time for HB, 26.42% for fresh charcoal and 25.35% for loaded charcoal in nine alternating host runs. Finger transport is unchanged.

The existing first-dab-immediate / 16 ms damage coalescer is retained. Frame-aligned publication was tested and rejected: its fresh-HB probe gaps reached 144–184 ms, whereas the selected 16 ms variant measured 36 ms in the focused comparison and 22 ms in the final full run. No whole-window update or frame hook remains. The material sampler still processes every raw point.

## Tablet results

First changed display-tile snapshot from evdev contact, sampled with millisecond timestamps and a 16 ms observer:

| Case | 4.1.1 | 4.1.2 |
| --- | ---: | ---: |
| latency-fresh-hb | 56 ms | 30 ms |
| latency-fresh-charcoal | 55 ms | 27 ms |
| latency-layered-hb | 58 ms | 38 ms |
| latency-layered-charcoal | 55 ms | 23 ms |

The median across these four cases changed from 55.5 to 28.5 ms. The full current run observed normal-stroke timer gaps of 22/30/26/28 ms for the cases in table order. These are individual baseline/current runs on one tablet, not a statistical latency ceiling. Focused repeats are variable.

In the longer 250 Hz shading test, the maximum active-input timer gap changed from 54 to 52 ms for graphite and from 316 to 138 ms for charcoal. Both final cases retain all 1,259 delivered pressure matches, zero pressure fallbacks, maximum raw batch 2 and no disappearance after a visible mark. The original charcoal performance gate failed, which reproduces the reported stutter; the final shading gate passes.

[Baseline onset](papersketch-v4.1.1-first-paint-baseline.json), [final onset](papersketch-v4.1.2-first-paint-device.json), [baseline shading](papersketch-v4.1.1-latency-baseline.json), [final shading](papersketch-v4.1.2-shading-device.json).

## Correctness and release checks

- 140 Python tests (2 skipped), 217 QML checks (2 skipped), and 13 native suites pass.
- The material lookup is bitwise equivalent over 48 complete trajectories and 1,179,648 exhaustive pixel cases; ASan/UBSan and leak detection pass.
- Real-tablet Materials, calibration, upright/tilted pen and finger-contact workflow: 18 evdev actions, no QML runtime errors. See [the device report](papersketch-v4.1.2-realism-device.json).
- Saved files and the notebook document are compared against the pre-update backup, and installed RCC/native hashes and the opened production app are checked in [the deployment report](papersketch-v4.1.2-tablet-deployment.json).
- Native counters use monotonic duration measurements and epoch entry timestamps. Advance time includes nested publication time; those totals must not be added as independent CPU stages.

The [machine-readable comparison](papersketch-v4.1.2-latency-audit.json) records source hashes and every per-case value. No optical panel latency or equivalence to physical paper is claimed.
