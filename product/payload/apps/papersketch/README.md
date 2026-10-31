# Paper Sketch (development)

Offline grayscale sketchbook for reMarkable 2 / XOVI AppLoad: four graphite pencils, charcoal, eraser, finger smudging, undo/redo, up to twelve pages, autosave and PNG export. Stroke history and PNG exports remain on the tablet.

## Current status

The native QImage candidate passes on-tablet pixel/replay, Linux evdev input and persistence checks. It remains a development build pending the user's physical drawing assessment. Software timing measurements do not measure the e-ink panel's optical response.

## Native image engine

`native/papersketch-raster.cpp` registers the optional `PaperSketch.Native` QML module. A native QImage owns the current page. QPainter renders new graphite/charcoal/eraser segments, and the native pixel kernel in `native/sketch-smudge.h` transports and blurs graphite with a smooth brush falloff. There are no shifted-image rings. New pencil grain uses one offset per stroke instead of a random offset for each segment.

128-pixel QQuickPaintedItem tiles present the image. Pen raster work happens during input; the selected shade is published when the pen lifts. The separate guarded pen extension supplies the immediate black preview. Finger changes publish only their affected tiles, without serializing pixels through JavaScript or temporary PNG files.

Saved renderer versions 1–6 retain their original replay behavior. Renderer 7 adds pressure-sensitive smudge strength; stronger stylus pressure softens and transports more graphite. The native backend reads the digitizer pressure directly because this firmware forwards constant pressure in the promoted Qt pointer events. The immediate pen preview also varies its width with pressure. Finger smudging uses its fixed touch strength. On the first load of an older page, its existing Qt raster is imported without changing its stroke history. Later loads can use an atomic PNG cache keyed to the complete page JSON and isolated by settings namespace. Eight native image snapshots accelerate undo/redo; older history remains available through replay. Closing releases native image/snapshot memory. PNG export uses the native image when active. Stroke documents and image caches are committed atomically by a background writer. The complete notebook and tool preferences live in a namespace-specific native JSON file alongside the caches; the original Settings document is retained as the migration fallback. A cache is accepted only when its page hash matches. Native redraws retain existing tile objects instead of rebuilding all their loaders.

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

- Desktop fallback QtTest: 22 passed, one native-only test skipped. This includes pressure-dependent smudging and preservation of renderer 6.
- Native C++ host integration passes: QML registration, pixel import, pressure-dependent smudge pixels, tile painting, undo/redo, PNG export, asynchronous document/cache persistence and cache-key rejection.
- On-tablet native pixel/replay probes pass: smudging softens the original line, transports graphite, remains visible after another stroke and matches saved-history replay.
- Final Linux evdev trace passes through the production pointer handlers. Recorded stylus pressure varies from 0.21 to 0.88. Finger smudging changes the original line from gray 76 to 181 and adjacent paper from 255 to 173; the presented native tiles match those pixels.
- In the final trace the pen's tile appears 59 ms after evdev release, sampled every 16 ms. The maximum idle timer gap is 227 ms, and the saved document plus image cache reload identically. This is software observation, not physical pen-to-glass latency.
- Earlier full native benchmarks measured roughly 19 ms median smudge steps and 35–50 ms pen commits. See the dated reports in docs; do not mix those measurements with earlier rejected JS frontends.
- Diagnostics isolate both Settings and native persistence namespaces per run, restore configuration using the tablet-local backup, and verify the original artwork document hash.
- Run tests/run-sketch-native.py with --smoke for pixel/replay probes or --input-probe for touch, stylus pressure and persistence. The input driver primes both MT axes because Linux suppresses unchanged ABS values left by a previous run.

Reports: docs/papersketch-qimage-device-smoke-2026-10-31.json, docs/papersketch-qimage-idle-save-2026-10-31.json and docs/papersketch-qimage-input-verified-2026-10-31.json.

The rejected JS pixel-transport and temporary file-bridge experiments remain documented in earlier reports. They are not the current native image architecture.
