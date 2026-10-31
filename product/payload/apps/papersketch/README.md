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

Tests: tests/qml/tst_papersketch.qml uses the existing QtTest environment. Covers drawing input, touch blending, suppression while drawing, pixel-level pigment transfer, white-paper preservation, history, page navigation, save serialization, validation and PNG output. The repository's desktop QSettings import is a stub; actual persisted reopening must also be checked on the tablet. New strokes use renderer version 2: native stroked paths, size-based sample reduction, dirty rectangles and fast e-ink updates during input. Saved version-1 strokes keep their original rendering. Smudge gestures interpolate the complete path, starting at the initial touch, and transfer pigment with native clipped image patches and darken compositing. Tests cover sparse touch events crossing a pencil stroke and immediate blending after pen-up. The canvas paints incrementally and replays in batches. It does not implement reMarkable's proprietary low-latency pen pipeline, so physical pen feel still needs an artist's check.
