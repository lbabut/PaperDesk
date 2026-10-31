# Paper Sketch

Offline grayscale sketchbook for reMarkable 2 and XOVI AppLoad.

Choose 2H, HB, 2B or 6B graphite, two charcoal tools, an eraser or a blending stump. Pen pressure changes stroke width and density. Adjust size, strength and graphite shade. Drag a finger to blend existing graphite or charcoal; the pen keeps the selected tool. Finger blending can be disabled. Active pen input suppresses finger blending; hovering the pen does not prevent an intentional finger gesture. Touch movement must exceed a small threshold before blending starts. This reduces accidental palm marks but is not a guarantee of palm rejection on every firmware.

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

Tests: tests/qml/tst_papersketch.qml uses the existing QtTest environment. Covers drawing input, touch blending, suppression while drawing, pixel-level pigment transfer, white-paper preservation, history, page navigation, save serialization, validation and PNG output. The repository's desktop QSettings import is a stub; actual persisted reopening must also be checked on the tablet. The reMarkable build uses 64 px bitmap preview tiles and 400 px committed-art tiles, with one constant Fast waveform. Rotated Qt Quick rectangles are unsuitable for libqsgepaper on the tested firmware. The full raster is a clipped off-screen backing store; the screen only sees the changed bitmap tiles. Bitmap commits wait until pen-up, and autosave is deferred until three seconds of inactivity. Existing version-1 and version-2 strokes retain their original renderers. Tests cover sparse touch events crossing a pencil stroke and immediate blending after pen-up. The canvas paints incrementally and replays in batches. It does not implement reMarkable's proprietary low-latency pen pipeline, so physical pen feel still needs an artist's check.

## Native device measurements

Run tests/run-sketch-native.py with --host, --key, --known-hosts and optional --host-key-alias. An optional --baseline-qml compares another frontend revision with the current code. The runner creates an isolated AppLoad diagnostics app, uses separate QSettings groups, backs up the tablet configuration, restores the original configuration, removes the diagnostics app and checks the artwork document hash. It does not replace the physical input devices or enable XOVI autostart.

The diagnostics execute synthetic stroke-function calls inside Xochitl on the reMarkable, collecting event-loop gaps, Qt frameSwapped delays, raster commit times and sampled process CPU time. These are not physical pen-to-glass measurements and do not replace a video check. reports: docs/papersketch-native-2026-10-31.json and docs/papersketch-native-tiled-2026-10-31.json.

The tiled native run recorded a maximum charcoal input-loop gap of 43 ms versus 2127 ms in the preceding frontend; median smudge scheduling fell from 147 ms to 86 ms in that run, with a 216 ms p95. Bitmap commits still took 743–926 ms for the tested pen strokes. The first case after switching frontend variants had a roughly two-second outlier, so these results do not establish a universal latency bound.

Platform constraints were cross-checked against https://github.com/dav01d/RemarkableAnimator/blob/main/docs/ARCHITECTURE.md for the same reMarkable 2 firmware (3.29.0.153). No native pen-path extension or firmware function-address hook is installed by Paper Sketch. Pressure is supported by the stroke engine; actual pressure input needs a native evdev bridge on firmware that presents the Marker only as a mouse.
