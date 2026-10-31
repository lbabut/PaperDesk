# Paper Sketch (development)

A grayscale bitmap sketchbook for reMarkable 2 / XOVI AppLoad. Choose a pencil or charcoal and its size; pressure comes from the stylus. Finger contact smears pigment. Undo, Redo, the strength slider and shade swatches have been removed.

## Material model

Renderer 8 stores fixed and loose pigment as two 16-bit masses per pixel, with an optical bitmap and a persistent fingertip pigment map. Fixed paper grain controls contact and local pigment capacity. Pencil hardness changes deposition and binding; charcoal leaves much more loose dust. Pressure changes contact width, deposition and rubbing strength. The eraser lifts pigment rather than painting a white stroke.

A finger picks up loose pigment, lifts some bound pigment and deposits what it carries elsewhere. Neighbor exchange mixes material on the fingertip without creating or destroying pigment. Fixed distance sampling makes the result independent of how pointer events split the same motion, and prevents segment seams. The simulation is an approximation of dry media, not a claim of complete physical equivalence to real paper.

## Live drawing

The material kernel writes the authoritative bitmap as pointer events arrive. Scalar pointer calls retain only the first and current point; JavaScript does not grow a point history during long shading gestures. Dirty tiles publish during the gesture on a coalesced 16 ms timer. The bitmap is neither cleared nor replaced by a temporary stroke preview at pen-up. The older firmware pen-preview extension is kept off in bitmap mode.

There is no post-stroke undo history and no page snapshot at the start of a stylus stroke. Small temporary patches exist only during a finger gesture so that stylus proximity can cancel an accidental palm mark. They are discarded when the gesture finishes. Finger input pauses while the stylus is in range.

Pressure packets are read from Wacom evdev in a separate, non-grabbing reader and matched to the delivered screen position. This avoids applying a newer pressure to an older movement queued by Qt. The material response uses a curved pressure response and pressure-dependent pigment capacity, so light shading does not reach the same density as a hard stroke as quickly.

The size slider performs no legacy preview status reads or writes in bitmap mode. Its black handle uses the tablet's UFast display hint; the grayscale drawing surface retains Fast.

## Persistence and migration

New marks are flattened into bitmap state. Artwork stays in RAM until the user chooses Save or PNG export. Close and page changes offer Save, Discard and Cancel for unsaved changes. Full screen hides all controls except a small round menu button at the upper right. The notebook contains page metadata rather than the growing point history that previously blocked the tablet for about two seconds during JSON serialization.

Each atomic .material page stores its optical bitmap, fixed/loose pigment and fingertip state together. Save waits for an atomic commit from a worker; there is no automatic saving. Image references are released before compression so they do not remain shared throughout disk I/O. The compact .material-notebook.json manifest is committed after its page. A newer matching bitmap page can repair the page metadata after an interrupted manifest commit.

Legacy notebooks and PNG caches are retained. Existing artwork is loaded from its matching bitmap cache, or replayed once if necessary, and imported without modifying its optical pixels. Subsequent opening uses the material bitmap directly. Missing material pages block saving instead of silently replacing artwork with a blank page. PNG export remains available.

## Build and install

The tool cache defaults to /home/lukasz/Documents/Codex/2026-09-25/m-2/work and can be selected with PAPERDESK_TOOLCACHE.

```sh
python3 scripts/build-sketch-raster.py
bash scripts/build-sketch.sh
python3 scripts/install-sketch-dev.py --host TABLET_IP --key KEY_PATH --known-hosts KNOWN_HOSTS_PATH --host-key-alias 10.11.99.1 --native-raster --launch
```

The raster build uses the extracted Qt 6.8 SDK and ARM toolchain in the tool cache. No Qt libraries are installed on the tablet. The installer backs up the app, configuration, native drawing state and replaced modules. It does not enable XOVI boot autostart.

The optional legacy pen extension can be built with scripts/build-sketch-native.sh. It derives from David @ TheoryStudios' MIT-licensed RemarkableAnimator extension; its license remains in native/LICENSE. It is not the material renderer.

## Verification

- Desktop QtTest: 25 passed, no failures, one native-only skip; simplified controls and absence of Undo/Redo are checked.
- tests/test-sketch-material.cpp checks clean white paper, graphite/charcoal differences, a minimum-size nib, pigment conservation, pressure, erasing and motion resampling.
- tests/test-sketch-material-integration.cpp checks absence of post-stroke snapshots, tentative palm cancellation, and exact reload of optical pixels, pigment and fingertip state.
- tests/test-sketch-raster.cpp covers the legacy native import, tile, export and cache paths without undo.
- On-device evidence: docs/papersketch-material-arm-2026-10-31.json and docs/papersketch-material-manual-input-2026-10-31.json and docs/papersketch-material-shading-2026-10-31.json. The input probe exercises Linux evdev through the production pointer handlers and samples actual painted tiles during the gesture and after pen-up.
- Long shading tests inject 1,260 pen samples per gesture (21 traversals across the page in about 5.3 seconds). Both graphite and fullscreen charcoal remain visible before pen-up with no sampled blank frames. The current pressure-engine probe (docs/papersketch-pressure-shading-2026-10-31.json) observes maximum input timer gaps of 51 ms for graphite and 127 ms for the heavier charcoal case. This is still a material responsiveness limitation; a passing no-blank-frame test is not a guarantee of comfortable drawing. Only two diagnostic points are retained. The manual-save probe confirms no automatic save and no changes to disk state while drawing.
- Current pressure/control evidence: docs/papersketch-real-pressure-2026-10-31.json captures aggregate readings from real hand-drawn strokes; docs/papersketch-pressure-device-2026-10-31.json exercises the production handlers with 55/55 spatially matched pressure samples, finger smearing, live tile visibility and manual-only saving. tests/test-sketch-pen.cpp checks pressure matching against a newer sample at a different position.
- The slider probe (docs/papersketch-slider-device-2026-10-31.json) measures a maximum 42 ms input timer gap during a drag and 11 ms from the first sampled value change to a Qt frame. A separate 174 ms gap occurs before the drag. The initial probe included pre-contact time in the input metric; the harness now reports both values rather than hiding the startup gap.
- Software timing is distinct from the e-ink panel's optical latency. Physical drawing feel remains subject to user testing.

Earlier qimage, JS transport and native-preview reports describe previous architectures. Do not use them as measurements of the bitmap material engine.
