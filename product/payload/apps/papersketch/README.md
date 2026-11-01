# Paper Sketch (development)

A grayscale bitmap sketchbook for reMarkable 2 / XOVI AppLoad. Choose a pencil or charcoal and its size; pressure comes from the stylus. Finger smearing is always enabled; there is no on/off button. The app keeps one sketchbook, with page creation and deletion. Undo, Redo, the strength slider and shade swatches have been removed.

## Material model

Renderer 8 stores fixed and loose pigment as two 16-bit masses per pixel, with an optical bitmap and a persistent fingertip pigment map. Fixed paper grain controls contact and local pigment capacity. Pencil hardness changes deposition and binding; charcoal leaves much more loose dust. Pressure changes contact width, deposition and rubbing strength. The eraser lifts pigment rather than painting a white stroke.

A finger picks up loose pigment, lifts some bound pigment and deposits what it carries elsewhere. Neighbor exchange mixes material on the fingertip without creating or destroying pigment. Fixed distance sampling makes the result independent of how pointer events split the same motion, and prevents segment seams. The simulation is an approximation of dry media, not a claim of complete physical equivalence to real paper.

## Live drawing

The material kernel writes the authoritative bitmap as pointer events arrive. Scalar pointer calls retain only the first and current point; JavaScript does not grow a point history during long shading gestures. Dirty rectangles notify the tiles immediately during the gesture; Qt coalesces the actual frame updates, with no additional 16 ms application timer. The bitmap is neither cleared nor replaced by a temporary stroke preview at pen-up. The older firmware pen-preview extension is kept off in bitmap mode.

There is no post-stroke undo history and no page snapshot at the start of a stylus stroke. Small temporary patches exist only during a finger gesture so that stylus proximity can cancel an accidental palm mark. They are discarded when the gesture finishes. Finger input pauses while the stylus is in range.

Pressure and position packets are read from Wacom evdev in a separate, non-grabbing reader and matched to the delivered screen position. When Qt combines movement events, the renderer consumes up to 64 recent intervening sensor samples from the same pen contact, retaining the captured curve and pressure changes. It adds no look-ahead delay. Contact boundaries and evdev resynchronization prevent joining separate gestures. A missing raw match falls back to the delivered point without replaying an already-painted fallback segment. This avoids applying a newer pressure to an older movement queued by Qt. The material response uses a curved pressure response and pressure-dependent pigment capacity, so light shading does not reach the same density as a hard stroke as quickly.

The size slider performs no legacy preview status reads or writes in bitmap mode. Its black handle uses the tablet's UFast display hint; the grayscale drawing surface retains Fast.

## Fast live display

The authoritative image, pigment simulation, saved material page and PNG export retain grayscale. Native tiles convert their display copy to a fixed 8×8 ordered halftone, allowing the drawing surface to use UFast rather than a grayscale waveform. This trades smooth screen tones for fine black-and-white grain. The pattern stays in place during and after a stroke; there is no black preview replaced by a different final image at pen-up.

Tile invalidation supplies the intersecting local rectangle. Each tile reuses its optical and display buffers and converts only its accumulated damaged regions. A repaint with no new damage simply reuses the existing pixels; changing page, display mode, tile size or source origin refreshes the full tile. Drawing no longer changes button availability colors or the footer's drawing/idle text on every pen contact; input actions remain blocked while a stroke is active. Page changes and requested saves retain their existing behavior.

On-device reports are docs/papersketch-live-shading-2026-10-31.json and docs/papersketch-live-input-2026-10-31.json. Both long shading gestures match all 1,259 delivered pressure samples, retain grayscale RAM pixels, and paint only black/white display pixels whose regional mean differs by less than 3/255 in the sampled patches. An 8×8 mean of the actual binary tile display pixels stays visible throughout each gesture and does not go blank after pen-up. Input probes read the painted optical snapshot before halftoning for exact pigment comparisons; the shading probe separately checks the actual native tile display palette.

The earlier live-display probe's timer maxima are 43 ms for graphite and 132 ms for charcoal. Those numbers include time before injected contact and are not optical pen-to-panel timings. This change does not establish a measured improvement in physical drawing comfort.

## Incremental display optimization

The display conversion benchmark runs on the tablet's ARM CPU without changing the screen or user artwork. For 2,000 narrow 8×64 patches, whole-tile conversion takes 474.256 ms versus 21.0615 ms for incremental updates (22.52×). For 48×48 wide-tool patches it takes 487.683 ms versus 79.1804 ms (6.16×). Final optical and display buffers are byte-identical. These ratios cover the measured copy/halftone operation, not total app speed or optical panel latency. See docs/papersketch-incremental-display-arm-2026-10-31.json and tests/bench-sketch-display.cpp.

Native regression tests compare full rendered output after separate one-pixel updates, source-origin changes, exposure repaints and display-mode changes. A live update is emitted before returning to the event loop. Current tablet integration reports are docs/papersketch-incremental-{shading,input,deployment}-2026-10-31.json. Instrumented long shading records active-contact timer maxima of 47 ms for graphite and 97 ms for charcoal; an earlier run recorded an unclassified 190 ms probe-wide peak before active/contact logging was added. The short pen/finger probe records 46 ms. These values are not optical panel measurements and do not establish an overall app speedup.

## Persistence and migration

New marks are flattened into bitmap state. Artwork stays in RAM until the user chooses Save or PNG export. Close and page changes offer Save, Discard and Cancel for unsaved changes. Full screen hides all controls except a small round menu button at the upper right. The notebook contains page metadata rather than the growing point history that previously blocked the tablet for about two seconds during JSON serialization.

Each atomic .material page stores its optical bitmap, fixed/loose pigment and fingertip state together. Save waits for an atomic commit from a worker; there is no automatic saving. Image references are released before compression so they do not remain shared throughout disk I/O. The compact .material-notebook.json manifest is committed after its page. A newer matching bitmap page can repair the page metadata after an interrupted manifest commit.

Legacy notebooks and PNG caches are retained. Existing artwork is loaded from its matching bitmap cache, or replayed once if necessary, and imported without modifying its optical pixels. Subsequent opening uses the material bitmap directly. Missing material pages block saving instead of silently replacing artwork with a blank page. PNG export remains available.

## Pages and named PNG export

Page bitmaps have stable cache slots independent of their position in the notebook. Deleting a middle page therefore does not rename or accidentally load another page's image. Deletion remains in RAM until Save. Discard restores the last saved notebook structure. Deleting the last page leaves a blank replacement. After an atomic manifest commit, the writer removes caches that were referenced by the previous saved notebook and are now deleted; unrelated older orphan caches and PNG exports are retained.

Export PNG opens a file-name field and the tablet keyboard. PNGs are written atomically to the current user's Documents folder, normally /home/root/Documents on the tablet, with an explicit replacement confirmation for an existing name. Exports retain the full grayscale RAM image. Export does not implicitly save the notebook. File-system errors remain visible in the export dialog.

Legacy notebooks acquire cache-slot identities in memory while preserving existing bitmap filenames and metadata compatibility. The cache-slot field is excluded from page-cache signatures. Recovery from a newer bitmap header updates the live page object and notebook together. No user bitmap is rewritten simply by opening the app.

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

- Desktop QtTest: 30 passed, no failures, one native-only skip; simplified controls and absence of Undo/Redo are checked.
- tests/test-sketch-material.cpp checks clean white paper, graphite/charcoal differences, a minimum-size nib, pigment conservation, pressure, erasing and motion resampling.
- tests/test-sketch-material-integration.cpp checks absence of post-stroke snapshots, tentative palm cancellation, and exact reload of optical pixels, pigment and fingertip state.
- tests/test-sketch-workflow.cpp verifies named Documents PNGs, collision/path handling, raw curved motion across coalesced events, fallback/contact boundaries, and removal of deleted caches only after a successful saved manifest. tests/test-sketch-pen.cpp checks ordered contact samples and the bounded FIFO.
- Latest real-device UI evidence: docs/papersketch-workflow-device-2026-11-01.json, docs/papersketch-workflow-files-2026-11-01.json, docs/papersketch-raw-shading-2026-11-01.json and docs/papersketch-raw-input-2026-11-01.json. The workflow taps the production export and delete buttons, checks keyboard focus/visibility, confirms duplicate-name handling, deletes a middle page, reloads surviving art, tests last-page deletion/discard and recovers a newer bitmap header. The exported 1200×1600 PNG is independently decoded and compared byte-for-byte with the grayscale RAM digest. Private fixture exports are removed after validation.
- tests/test-sketch-raster.cpp covers the legacy native import, tile, export and cache paths without undo.
- On-device evidence: docs/papersketch-material-arm-2026-10-31.json and docs/papersketch-material-manual-input-2026-10-31.json and docs/papersketch-material-shading-2026-10-31.json. The input probe exercises Linux evdev through the production pointer handlers and samples actual painted tiles during the gesture and after pen-up.
- Long shading tests inject 1,260 pen samples per gesture (21 traversals across the page in about 5.3 seconds). Both graphite and fullscreen charcoal remain visible before pen-up with no sampled blank frames. The current pressure-engine probe (docs/papersketch-pressure-shading-2026-10-31.json) observes maximum input timer gaps of 51 ms for graphite and 127 ms for the heavier charcoal case. This is still a material responsiveness limitation; a passing no-blank-frame test is not a guarantee of comfortable drawing. Only two diagnostic points are retained. The manual-save probe confirms no automatic save and no changes to disk state while drawing.
- Current pressure/control evidence: docs/papersketch-real-pressure-2026-10-31.json captures aggregate readings from real hand-drawn strokes; docs/papersketch-pressure-device-2026-10-31.json exercises the production handlers with 55/55 spatially matched pressure samples, finger smearing, live tile visibility and manual-only saving. tests/test-sketch-pen.cpp checks pressure matching against a newer sample at a different position.
- The slider probe (docs/papersketch-slider-device-2026-10-31.json) measures a maximum 42 ms input timer gap during a drag and 11 ms from the first sampled value change to a Qt frame. A separate 174 ms gap occurs before the drag. The initial probe included pre-contact time in the input metric; the harness now reports both values rather than hiding the startup gap.
- Software timing is distinct from the e-ink panel's optical latency. Physical drawing feel remains subject to user testing.

Earlier qimage, JS transport and native-preview reports describe previous architectures. Do not use them as measurements of the bitmap material engine.
