# Paper Sketch 4

A grayscale bitmap sketchbook for reMarkable 2 and XOVI AppLoad. Four pencil grades (2H, HB, 2B, 6B), charcoal, soft charcoal, an eraser and a smudge tool share one compact icon toolbar with the size slider. Finger blending is always enabled; stylus proximity cancels tentative palm marks. The full-screen mode leaves a small menu button to restore the controls.

## Dry materials

Each paper pixel stores fixed and loose pigment separately. Stable multiscale grain controls contact and capacity. Pencil hardness changes deposition and binding; charcoal leaves more loose dust. Stylus pressure affects footprint, deposition, pickup and erasing. Erasing lifts pigment. A persistent fingertip map carries pigment from dark areas onto clean paper, including after a lift. Transfer and mixing conserve pigment exactly; erasing intentionally removes it.

Version 4 makes zero contact a true no-op, scales fingertip friction with pressure and retains distances from very small input events. Constants and footprint coordinates are reused in the hot loop. The same path split into different event counts has matching material output in the regression fixtures. See [the material audit](../../../../docs/papersketch-v4-material-audit.md) for the model, benchmarks and limitations.

This remains a dry-media approximation. It does not simulate stylus tilt, sharpening, nib wear, paper deformation or graphite sheen. Unit tests and software timings cannot establish equivalence to physical paper or measure the panel's optical latency.

## Live drawing and display

The native material kernel updates the authoritative image while the pointer moves. A bounded, non-grabbing Wacom reader matches position and pressure, and recovers intervening samples when Qt combines movements. Separate contacts are never joined. JavaScript retains only diagnostic endpoints rather than a growing stroke history.

Damaged native tiles update immediately without replacing the image at pen-up. The display uses a fixed 8 by 8 black-and-white halftone for the fast e-ink waveform. Pigment, saved pages and PNG exports retain full grayscale. No drawing-time disk writes or automatic saves are performed.

## Saving and compatibility

Save commits the optical image, pigment and fingertip state together in an atomic material page from a background writer, then commits the compact notebook manifest. Close and page changes offer Save, Discard and Cancel. Stable cache slots keep page deletion from changing another page's identity. A matching newer page header can recover from an interrupted manifest commit; a missing or damaged page blocks saving instead of silently replacing artwork with white paper. Compressed material pages have a fixed decoded-size bound.

Legacy notebooks and matching bitmap caches are retained and imported without changing their optical pixels. New marks use material state, not a growing vector history. There is no Undo/Redo history.

Export PNG opens a file-name field and the system keyboard, writes grayscale atomically to Documents and confirms replacement of an existing file. Export does not implicitly save the notebook. Invalid names and file-system failures remain visible.

The v4 installer stages the native renderer alongside the AppLoad application, verifies package checksums before mutation, retains the prior module for rollback, and preserves sketchbooks and PNG exports. Its native ABI guard accepts the supported reMarkable 2 firmware versions listed in the package metadata; it does not enable XOVI boot autostart.

## Build and verify

The extracted toolchain/Qt SDK is selected by `PAPERDESK_TOOLCACHE`; its workstation default is shared with the other PaperDesk build scripts. No Qt libraries are installed on the tablet.

```sh
python3 scripts/build-sketch-raster.py
sh scripts/build-sketch.sh
python3 scripts/test-sketch-native.py
sh tests/run-ui-tests.sh
```

The native host suite checks material pressure/conservation/resampling, bounded input, tentative palm cancellation, exact cache reload, incremental tile damage, grayscale PNG export and cache corruption rejection. The QML suite checks toolbar geometry, tool selection, size changes, persistence and page/export dialogs. Real-device diagnostics use an isolated test notebook and restore the original settings:

```sh
python3 tests/run-sketch-native.py --host TABLET_IP --key KEY_PATH --known-hosts KNOWN_HOSTS_PATH --host-key-alias 10.11.99.1 --controls-probe --output docs/papersketch-v4-controls-device.json
```

The same runner offers `--input-probe`, `--shading-probe` and `--workflow-probe`. Do not run tablet input tests concurrently. Device and deployment evidence for this release is stored under `docs/papersketch-v4-*`.

The optional legacy `papersketch-ink` preview extension is separate from the material renderer and is not installed by the v4 package. It derives from David @ TheoryStudios' MIT-licensed RemarkableAnimator extension; retain `native/LICENSE`. Project licensing is described in the repository's `LICENSES.md`.
