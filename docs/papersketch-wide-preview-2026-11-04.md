# Paper Sketch wide-stroke latency fix

Based on the published 4.2.8 commit 3a0db31.

The QML fast-preview eligibility limit was 16 document pixels. Wider graphite,
charcoal and rapidograph strokes therefore waited for the material renderer.
The new limit is 80 document pixels, with a 96-screen-pixel native permit bound
covering the 1404/1200 maximum canvas scale. A fresh wide_preview capability
acknowledgement is required; earlier native modules retain the narrow path.
The post-stroke repair margin now covers the wider temporary silhouette.
The material kernel and stored artwork format are unchanged.

Validation:
- QML Sketch suite: 64 passed, 0 failed, 2 device-runtime skips.
- Native preview regression passed on host and on the tablet ARM CPU in a
  private in-memory framebuffer. Includes the 96px bound, clipping of pixels
  and masks, invalid permits, pressure, shades, and 8ms flush scheduling.
- ARM native modules and RCC built successfully.
- Full native regression suite passed (C++ cases and C input/preview checks),
  including publication repair, latency, raster, physical material, save/load,
  rapidograph, palm cancellation, and PDF export.

Not installed in the running tablet application yet: Sketch is open and the
journal shows drawing after its last explicit save. Save and close Sketch
before installing or running the isolated device fidelity probe. Do not restart
xochitl or substitute in-memory artwork with a test fixture before that.

After save/close, use scripts/install-sketch-dev.py with --native-raster and
--native-ink, then the existing isolated fidelity probe at size 80. Its backup
and artwork restoration checks must pass. Measure preview submission delay and
release tail separately: software submission timing is not optical panel latency.
This branch does not publish a public release or update version metadata.
