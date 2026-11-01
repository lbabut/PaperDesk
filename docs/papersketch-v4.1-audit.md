# Paper Sketch 4.1 audit

Date: 2026-11-01. Status: prepublication validation complete. The final source snapshot is ready for release. Publication and production checks are recorded afterward in the separate [deployment report](https://github.com/lbabut/PaperDesk/releases/download/v4.1.0/paperdesk-4.1.0-deployment.json), avoiding a source-archive checksum self-reference.

## Six changes

1. **Input response.** Live updates publish regions of changed pixels, avoiding unnecessary large redraws. Material pixels still update for every raw sample; the first dab publishes immediately, later disjoint damage notifications are collected in 16 ms windows, and pen-up flushes them immediately. Reset, load and release discard stale pending notifications. Calibration preview history is bounded. Material preferences stay in memory until explicit Save, avoiding an eager delayed Qt Settings store while changing paper or restoring a page. Native saves already include those preferences in the atomic notebook manifest; legacy saves retain their explicit Settings save path. The fast-charcoal shading report must establish the actual effect on the tablet; a CPU benchmark alone does not do that.
2. **Tilt and contact shape.** Native input reads normalized pen tilt. Pencil and charcoal footprints become oriented ellipses, with distinct side contact and an upright fallback when tilt is absent.
3. **Pressure response.** Each grade has separate width and pigment-dose curves. An isolated three-stage light/normal/firm wizard collects raw pen input, validates separated pressure anchors and atomically saves the profile. Cancel preserves the previous response. Failed steps and failed resets do not announce success.
4. **Paper and wear.** Plain, smooth and rough stock have different grain. Firm drawing accumulates persistent surface burnish; six nibs wear independently. Sharpen affects only the selected tool. Texture is remembered per page, while the current tool kit persists across pages.
5. **Finger.** The existing loaded fingertip continues picking up and depositing pigment conservatively. Geometry, orientation, a capacitance proxy and motion speed change contact. Clean finger removes its carried pigment. Pen proximity suppresses finger input.
6. **Erasers.** Hard rubber removes pigment while rubbing. Kneaded rubber gently selects loose pigment once per contact: lift and dab again for further removal. It does not keep erasing while held down.

The Materials icon opens these controls from the first screen. The middle tool strip remains 84 pixels high with its integrated size slider. Material changes mark the drawing dirty. A failed bitmap load blocks material actions and saving; the original files remain available for recovery.

The Settings change removes a known source of unrequested persistence. Qt 6.8 schedules a 500 ms timer when a Settings property changes and caches the object's full property set, including its legacy document and checkpoint fields. The material apply/restore path no longer assigns those Settings properties. This mechanism is visible in [Qt's Settings source](https://raw.githubusercontent.com/qt/qtdeclarative/6.8/src/labs/settings/qqmlsettings.cpp). It does not establish that Settings caused the first-upright-stroke discrepancy observed during device investigation. The pressure profile has its own explicit Save response operation; applying materials and saving a notebook do not replace that calibration step.

## Verification

- Full host checks: 140 Python tests (2 skips), 211 QML passes (2 native-only skips), zero failures; 12 native suites pass. Focused material, integration and publication AddressSanitizer/UndefinedBehaviorSanitizer checks pass, with leak detection.
- The publication test compares an entire 1,260-sample charcoal path with immediate-notification rendering. Optical pixels, fixed/loose mass, fingertip, burnish, wear and the total damaged region match exactly. First-dab visibility and timer/finish/cancel/reset/release/load lifecycle checks pass.
- Five real-tablet probes pass on reMarkable 2 / OS 3.29.0.153: controls, raw pen/finger input, long fast shading, calibration/materials and save/export/page deletion. The realism probe requires all 18 evdev actions, exact state reload and no QML runtime errors.
- Upright and tilted strokes both match all 60 raw-pressure samples without fallbacks. At equal pressure, the measured optical footprint expands from 28 to 42 rows. Probe-loop gaps are 41/40 ms. The combined Settings/display changes resolve the observed first-stroke failure in this run; this does not isolate the causal contribution of either change.
- Final long-shading software input gaps: graphite 54 ms, charcoal 190 ms. The first tile appears before pen release, remains visible, and its binary halftone mean tracks the optical grayscale image. These are software observations, not physical panel latency.
- The final kernel additionally skips zero-result saturated-pixel calculations. A fixed pre-optimization reference matches every stored value over 48 complete trajectories (all eight tools, three papers, empty/loaded surfaces). The final ARM module repeats the realism and shading probes; input, controls and workflow coverage precede this bit-identical kernel optimization.
- The exported 1200-by-1600 PNG is independently decoded and matches the exact optical RAM digest. Deleted fixture-page caches are removed only after Save. Original saved files and the notebook document remain unchanged; installed RCC/native hashes match the release payload.
- Detailed reports and final source/ZIP hashes are in `papersketch-v4.1-audit.json`. The material and isolated host fan-out benchmarks are in their separate audit/benchmark files. A host-loop result does not establish that all tools are faster.

## Limits

Touch area and capacitance do not measure finger force. Pen-proximity gating is observed by the realism harness, while simultaneous physical palm contact remains untested there. Fast e-ink mode uses binary halftone; optical grayscale values cannot establish the panel's final appearance or latency.

Material and nib parameters approximate dry media; they are not measurements of a particular pencil, charcoal or paper stock. Graphite sheen, skin oils, finger ridges and full paper deformation remain outside the model. A bitmap cannot recover its original medium, so legacy imports retain the existing inferred fixed/loose pigment split. Physical friction and the feel of the tablet surface cannot be reproduced by this software model alone.
