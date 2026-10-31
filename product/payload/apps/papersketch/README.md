# Paper Sketch (development)

Offline grayscale sketchbook for reMarkable 2 / XOVI AppLoad: four graphite pencils, charcoal, eraser, finger smudging, undo/redo, up to twelve pages, autosave and PNG export. Stroke history and PNG exports remain on the tablet.

## Current status

The previous deployed frontend is not usable enough according to physical user testing. The current source introduces a native QImage engine and remains a draft. It compiles for ARM and passes host integration checks, but has NOT been installed or validated on the tablet: the tablet stopped responding on Wi-Fi, has no connected USB network, and its Tailscale peer is offline. Do not treat earlier benchmark passes as proof of acceptable drawing feel.

## Native image engine

`native/papersketch-raster.cpp` registers the optional `PaperSketch.Native` QML module. A native QImage owns the current page. QPainter renders new graphite/charcoal/eraser segments, and the native pixel kernel in `native/sketch-smudge.h` transports and blurs graphite with a smooth brush falloff. There are no shifted-image rings. New pencil grain uses one offset per stroke instead of a random offset for each segment.

128-pixel QQuickPaintedItem tiles present the image. Pen raster work happens during input; the selected shade is published when the pen lifts. The separate guarded pen extension supplies the immediate black preview. Finger changes publish only their affected tiles, without serializing pixels through JavaScript or temporary PNG files.

Saved renderer versions 1–5 retain their original JS replay paths. Renderer 6 uses the new smooth smudge and stable grain. On the first load of an older page, its existing Qt raster is imported without changing its stroke history. Later loads can use an atomic PNG cache keyed to the complete page JSON and isolated by settings namespace. Eight native image snapshots accelerate undo/redo; older history remains available through replay. Closing releases native image/snapshot memory. PNG export uses the native image when active.

The app loads the optional module dynamically. The Canvas fallback remains available, but its smudge path is too slow on the tested tablet and must not be presented as a performance fix.

## Build

The existing tool cache is selected by PAPERDESK_TOOLCACHE (default: /home/lukasz/Documents/Codex/2026-09-25/m-2/work).

```sh
bash scripts/build-sketch.sh
bash scripts/build-sketch-native.sh
python3 scripts/build-sketch-raster.py
```

The raster build expects an extracted Qt 6.8 SDK at `$PAPERDESK_TOOLCACHE/papersketch-qt-sdk/root` and the existing ARM cross toolchain at `$PAPERDESK_TOOLCACHE/arm-toolchain/root`. The SDK used here comes from Debian packages qt6-base-dev, qt6-base-dev-tools and qt6-declarative-dev, extracted with dpkg-deb; it is not installed on the tablet. No Qt libraries are bundled into the extension.

The native pen preview is derived from dav01d/RemarkableAnimator's MIT-licensed extension (David @ TheoryStudios, 2026); its license is retained in native/LICENSE. It checks reMarkable 2 OS 3.29.0.153's exact ELF build ID c1a6698ec0512ddd88c2ba5ca713390988978056 and framebuffer layout before calling firmware functions. Updates are coalesced every 16 ms. The QImage engine uses Qt APIs and does not call firmware addresses.

## Development install (after device validation)

```sh
python3 scripts/install-sketch-dev.py --host TABLET_IP --key /path/to/tablet-key --known-hosts /path/to/known_hosts --native-ink --native-raster --launch
```

Add --host-key-alias 10.11.99.1 when reusing the verified USB host key over Wi-Fi. The installer backs up the app, settings and each replaced extension. It restarts Xochitl and uses the existing one-shot launch hook. It does not enable XOVI boot autostart.

## Validation

- Desktop fallback QtTest: 21 passed, one native-only test skipped.
- Native C++ host integration: QML type registration, image import, graphite/smudge pixels, actual tile painting, undo/redo, PNG export and cache-key rejection pass.
- The core C smudge kernel ran on the tablet's ARM processor at about 11 ms for the 248 x 128 fixture, with white-paper preservation checked. This is NOT full application latency.
- The complete new ARM extension compiles. Its on-tablet QML, rendering, import, cache, performance and physical-input checks remain blocked by device connectivity.
- Native device diagnostics: tests/run-sketch-native.py, with --smoke for the two pixel/replay probes. Diagnostics isolate settings and cache namespaces, restore the original config, and verify the artwork document hash.
- tests/test-sketch-raster.cpp exercises the new native engine on the host; tests/test-sketch-native-smudge.c tests the pixel kernel.

The rejected JS pixel-transport experiment is recorded in docs/papersketch-pixel-transport-2026-10-31.json: roughly 0.4 seconds per smudge step on the tablet. The temporary file-bridge experiments also failed the responsiveness goal and are not the final architecture. Earlier reports describe previous frontends; they are not measurements of the new QImage engine.
