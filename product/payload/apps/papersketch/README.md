# Paper Sketch

Offline grayscale sketchbook for reMarkable 2 and XOVI AppLoad.

Choose 2H, HB, 2B or 6B graphite, two charcoal tools, an eraser or a blending stump. The engine accepts pressure; Marker-as-mouse firmware uses a fallback pressure value. Adjust size, strength and graphite shade. Drag a finger to blend existing graphite or charcoal; the pen keeps the selected tool. Finger blending can be disabled. Active pen input suppresses finger blending; hovering the pen does not prevent an intentional finger gesture. Touch movement must exceed a small threshold before blending starts. This reduces accidental palm marks but is not a guarantee of palm rejection on every firmware.

Undo and Redo work stroke by stroke, including smudges and erasing. A cleared page can be restored with Undo until another stroke is made. New book replaces the sketchbook after confirmation. There are up to twelve pages and 64,000 sampled points per sketchbook. Export important work before starting a new book.

Plain, dot and grid guides are available. Guides stay separate from the artwork, so erasing and blending do not damage them. PNG exports contain the artwork on white without guides, at 1200 × 1600 pixels. Exports go to /home/root/.local/share/paperdesk/sketch/. Status shows the export filename.

The versioned stroke history is autosaved in the PaperDeskSketch QSettings group after a short idle delay and on Close. A previous checkpoint supports recovery. User artwork and PNG exports are not removed by this development installer. No network connection is used by the app.

Build from the repository root:

```sh
bash scripts/build-sketch.sh
```

The build uses the existing verified Qt resource compiler cache. Override PAPERDESK_TOOLCACHE if the cache is elsewhere. icon.png is included alongside its editable icon.svg source.

Install only this app over an existing PaperDesk / XOVI installation:

```sh
python3 scripts/install-sketch-dev.py --key /path/to/tablet-key --known-hosts /path/to/known_hosts --launch
```

The installer keeps a rollback copy, briefly restarts Xochitl and leaves the existing XOVI boot policy unchanged. Launch uses the existing one-shot PaperDesk test hook and resets its autostart flag when consumed. It does not enable XOVI autostart. No existing app is replaced.

Tests: tests/qml/tst_papersketch.qml uses the existing QtTest environment. Covers drawing input, touch blending, suppression while drawing, pixel-level pigment transfer, white-paper preservation, history, page navigation, save serialization, validation and PNG output. The repository's desktop QSettings import is a stub; actual persisted reopening must also be checked on the tablet. The reMarkable build uses 64 px bitmap preview tiles and 400 px committed-art tiles, with one constant Fast waveform. Rotated Qt Quick rectangles are unsuitable for libqsgepaper on the tested firmware. The full raster is a clipped off-screen backing store; the screen only sees the changed bitmap tiles. Bitmap commits wait until pen-up, and autosave is deferred until three seconds of inactivity. Existing version-1 and version-2 strokes retain their original renderers. Tests cover sparse touch events crossing a pencil stroke and immediate blending after pen-up. The canvas paints incrementally and replays in batches. An optional exact-build native extension supplies the live pen preview described below.

## Native device measurements

Run tests/run-sketch-native.py with --host, --key, --known-hosts and optional --host-key-alias. An optional --baseline-qml compares another frontend revision with the current code. The runner creates an isolated AppLoad diagnostics app, uses separate QSettings groups, backs up the tablet configuration, restores the original configuration, removes the diagnostics app and checks the artwork document hash. It does not replace the physical input devices or enable XOVI autostart.

The diagnostics execute synthetic stroke-function calls inside Xochitl on the reMarkable, collecting event-loop gaps, Qt frameSwapped delays, raster commit times and sampled process CPU time. These are not physical pen-to-glass measurements and do not replace a video check. reports: docs/papersketch-native-2026-10-31.json and docs/papersketch-native-tiled-2026-10-31.json.

The tiled native run recorded a maximum charcoal input-loop gap of 43 ms versus 2127 ms in the preceding frontend; median smudge scheduling fell from 147 ms to 86 ms in that run, with a 216 ms p95. Bitmap commits still took 743–926 ms for the tested pen strokes. The first case after switching frontend variants had a roughly two-second outlier, so these results do not establish a universal latency bound.

Platform constraints were cross-checked against https://github.com/dav01d/RemarkableAnimator/blob/main/docs/ARCHITECTURE.md for the same reMarkable 2 firmware (3.29.0.153). The optional native preview is derived from its MIT-licensed extension/animator-ink.c (David @ TheoryStudios, 2026); the license is retained in native/LICENSE.

## Native pen preview and smudge revision 4

Build with `bash scripts/build-sketch-native.sh`, then pass `--native-ink` to the development installer. The shared object goes to XOVI extensions.d with a rollback copy. It reads Wacom evdev without grabbing the device and uses the existing framebuffer pen mask and FastDraw update function. This relies on private firmware offsets and is restricted to reMarkable 2 OS 3.29.0.153 with ELF build ID c1a6698ec0512ddd88c2ba5ca713390988978056. Unknown builds stay disabled. The framebuffer image/mask layout and required Qt symbols are checked before the backend announces readiness.

The app sends a fresh, bounded portrait-canvas heartbeat only while its drawing surface is available. The backend expires the arm file after three seconds; absence, invalid geometry and non-root/nonregular files disable it. QML only suppresses its preview after a fresh native acknowledgement, and keeps the stroke history and raster commit. Native preview is black, constant width, and replaced by the selected graphite shade after pen-up; it does not supply raw pressure to saved strokes. Finger blending and the selected smudge tool retain the Qt path. Desktop tests and synthetic stroke-function benchmarks do not exercise physical Wacom-to-panel latency.

Renderers 4 and 5 mix shifted snapshots with source-over rather than darken. This softens and lightens the original line as well as depositing graphite beside it. A feathered capsule covers the entire sampled finger movement. Existing renderers 1–3 remain available so prior saved smudges replay consistently.

20 desktop QtTest checks pass, including a pixel assertion that smudging lightens the line's center, transfers graphite beside it, and preserves untouched white paper.

## Post-stroke queue and directional blending

Native pen segments still record every sample, but panel submissions now merge their dirty rectangles and run at most once per 16 ms, with a forced final submission on release. This avoids submitting roughly 500 updates per second. The host test `gcc -O2 tests/test-sketch-native-batch.c -ldl -lpthread -o /tmp/test-sketch-batch && /tmp/test-sketch-batch` verifies 1000 reports over two seconds become 126 submissions without dropping the final tail or union bounds. This is a scheduling test, not a physical panel measurement.

The raster commit processes up to 8192 jobs / 80 ms per pass instead of 256 jobs / 14 ms. Changed art tiles are refreshed once the pending pen commit finishes; smudging retains incremental presentation. Existing nonnative preview clearing still waits for the commit.

Renderer 5 moves more pigment in the finger's direction and uses stronger feathered mixing. The old renderer 4 remains available for saved strokes. Device pixel probes found the previous transfer extremely pale (235/255 beside a test line); the directional renderer yields 180/255 for the same fixture. The original line lightens from 76 to 158, and raster and visible-tile pixel values stay identical after another pen stroke and a full page replay.

Two complete synthetic runs execute these probes inside Xochitl. Reports are `docs/papersketch-commit-smudge-2026-10-31.json` (batching with renderer 4) and `docs/papersketch-directional-smudge-2026-10-31.json` (renderer 5). In the latter, 180-point pen commits take 304–433 ms; smudge scheduling medians are 78–84 ms. Artwork document hashes before and after each run match. These timings cover the Qt path on the tablet with the previously installed native module; physical Wacom testing is needed to quantify the new native coalescer's panel latency.
