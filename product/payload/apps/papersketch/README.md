# Paper Sketch 4.2.3

A grayscale bitmap sketchbook for reMarkable 2 and XOVI AppLoad. Four pencil grades (2H, HB, 2B, 6B), charcoal, soft charcoal, Rapidograph, hard and kneaded erasing, and a smudge tool share one compact icon toolbar with the size slider. Finger blending is always enabled; stylus proximity cancels tentative palm marks. Materials settings are the first icon in the middle toolbar, before the 2H pencil. The full-screen mode leaves a small menu button to restore the controls.

Rapidograph draws a constant-width black ink line. Positive pressure and tilt do not change its width. Its separate ink layer survives smudging and both dry-material erasers; Clear or Delete page removes it. Saved ink pages use material cache v3; older v1/v2 sketches remain readable.

## Rear stylus eraser

Flip a supported stylus to use its rear end as a normal hard eraser. The selected
drawing tool and its settings stay unchanged; flip back to continue drawing.
The rear eraser uses the eraser tool's default width and full strength, then
restores the chosen hard/kneaded mode when lifted. Permanent ink is unaffected.

## Dry materials

Each paper pixel stores fixed and loose pigment separately. Multiscale grain controls contact and capacity, with plain, smooth and rough paper stocks. Pencil hardness changes deposition and binding; charcoal leaves more loose dust. Stylus pressure has separate width and deposition profiles for each medium. When hardware tilt is available, the tip becomes a directional ellipse and tilted charcoal gains a broader side with firmer shoulders. Without tilt, the tip remains upright.

Firm strokes gradually smooth the local paper surface and compact some loose pigment into the fixed fraction. Modest nib wear accumulates by traveled distance and broadens the tip; Sharpen resets the selected medium's wear. Changing paper stock changes future contact without rewriting drawn pigment. The hard eraser rubs along a stroke; the kneaded eraser gently lifts mainly loose pigment as pressure increases or the contact moves onto fresh paper. A per-contact cap prevents repeated samples at the same pressure from continuously erasing. Lift and dab again to remove another layer.

Finger transfer uses position-matched capacitive contact pressure, a pressure response that remains useful at light contact, and a stable minimum fingertip footprint. Fast movement does not apply an additional strength penalty. The final transfer response is 10 percent gentler than the stronger owner-tested blend.

A persistent fingertip map carries pigment from dark areas onto clean paper, including after a lift. The contact can be an oriented ellipse. Transfer and mixing conserve pigment exactly; erasing intentionally removes it. Zero pressure or strength leaves both surfaces unchanged. The spatial sampler retains even very small input distances, including the evolving surface and wear state. See [the 4.1 material audit](../../../../docs/papersketch-v4.1-material-audit.md) for the model, benchmarks and limitations.

This remains an uncalibrated dry-media approximation. Tilt, wear and surface smoothing are simulated responses, not measurements of real nib geometry or paper deformation. Graphite sheen, actual skin ridges, skin oils and a specific paper's fibers are not modeled. Unit tests and software timings cannot establish equivalence to physical paper or measure the panel's optical latency.

## Live drawing and display

The native material kernel updates the authoritative image while the pointer moves. A passive pen grab starts pen strokes on initial contact, including stationary dots, without waiting for a drag or a release. A bounded, non-grabbing Wacom reader matches position and pressure, and recovers intervening samples when Qt combines movements. Separate contacts are never joined. JavaScript retains only diagnostic endpoints rather than a growing stroke history.

Material pixels update at every raw sample. The first dab publishes its changed tiles immediately; subsequent disjoint damage notifications are collected in 16 ms windows and flushed immediately at pen-up. Reset, load and release discard pending notifications from the previous image. This bounds display notification work without changing the material sampler. A shared lookup stores the same double-precision paper-response values instead of repeating their arithmetic for each touched pixel, retaining the material equations and rendered image. Software pipeline timing remains separate from physical e-ink refresh. The display uses a fixed 8 by 8 black-and-white halftone for the fast e-ink waveform. Pigment, saved pages and PNG exports retain full grayscale. No drawing-time disk writes or automatic saves are performed.

## Saving and compatibility

Save commits the optical image, pigment and fingertip state together in an atomic material page from a background writer, then commits the compact notebook manifest. Close and page changes offer Save, Discard and Cancel. Stable cache slots keep page deletion from changing another page's identity. A matching newer page header can recover from an interrupted manifest commit; a missing or damaged page blocks saving instead of silently replacing artwork with white paper. Compressed material pages have a fixed decoded-size bound.

Paper and eraser choices stay in memory until explicit Save. The native notebook manifest includes those preferences; the legacy renderer writes its Settings fields only through the explicit save path. Changing a material or restoring a page does not schedule an additional Settings store. Pen calibration is separate: the wizard's Save response explicitly commits its pressure profile, while Cancel keeps the previous profile and does not save the drawing.

Legacy notebooks and matching bitmap caches are retained and imported without changing their optical pixels. New marks use material state, not a growing vector history. There is no Undo/Redo history.

Export PDF asks for a document name, writes a one-page lossless grayscale PDF atomically in a private export job, and adds it to My files through the native reMarkable DocumentImporter. After normal cloud synchronization, it can be shared from the reMarkable companion app. Each export creates an independent copy. Success requires the matching source-completion signal and a new, non-trashed library entry with the expected name; staging is removed only after confirmation. Pending imports block repeat clicks, and failures or timeouts retain the PDF and explain their status. Export does not save or change the sketchbook. Existing Documents PNG exports are retained.

The v4 installer stages the native renderer alongside the AppLoad application, verifies package checksums before mutation, retains the prior module for rollback, and preserves sketchbooks and PNG exports. Its native ABI guard accepts the supported reMarkable 2 firmware versions listed in the package metadata; it does not enable XOVI boot autostart.

## Build and verify

The extracted toolchain/Qt SDK is selected by `PAPERDESK_TOOLCACHE`; its workstation default is shared with the other PaperDesk build scripts. No Qt libraries are installed on the tablet.

```sh
python3 scripts/build-sketch-raster.py
sh scripts/build-sketch.sh
python3 scripts/test-sketch-native.py
sh tests/run-ui-tests.sh
```

The PDF host test uses Poppler tools pdfimages and pdfinfo to verify the embedded grayscale image.

The native host suite checks material pressure/conservation/resampling, bounded input, tentative palm cancellation, exact cache reload, incremental tile damage, grayscale PNG export and cache corruption rejection. The QML suite checks toolbar geometry, tool selection, size changes, persistence and page/export dialogs. Real-device diagnostics use an isolated test notebook and restore the original settings:

```sh
python3 tests/run-sketch-native.py --host TABLET_IP --key KEY_PATH --known-hosts KNOWN_HOSTS_PATH --host-key-alias 10.11.99.1 --controls-probe --output docs/papersketch-v4-controls-device.json
```

The same runner offers `--pdf-probe`, `--input-probe`, `--shading-probe`, `--workflow-probe`, `--realism-probe` and `--latency-probe`. The latency probe compares HB and charcoal on fresh and layered in-memory pages, records input-to-raster/tile/frame software timestamps and event-loop gaps, and reads optional native advance/publication/tile timing counters. `--baseline-qml` accepts a preserved UI source for comparison; install the corresponding native renderer deliberately before each run. The realism probe records emission coordinates and canvas scale, per-stroke UI timer gaps, pressure match/fallback counts, replay statistics and first/last endpoints. Native miss diagnostics report stale-position matches and retained-sample ages. Upright and tilted strokes must satisfy the same strict pressure-matching checks before their optical footprints can be compared. These software diagnostics do not measure physical panel latency or prove the cause of an input delay. Do not run tablet input tests concurrently. Earlier 4.1 device and deployment evidence is stored under `docs/papersketch-v4.1-*`; keep new latency comparisons in separate versioned reports.

The optional legacy `papersketch-ink` preview extension is separate from the material renderer and is not installed by the v4 package. It derives from David @ TheoryStudios' MIT-licensed RemarkableAnimator extension; retain `native/LICENSE`. Project licensing is described in the repository's `LICENSES.md`.
