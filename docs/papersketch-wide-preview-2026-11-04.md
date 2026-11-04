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

Installed on the user's tablet after explicit save/close confirmation.
The installed native modules and RCC hashes match this branch's payload.
The isolated real-input fidelity probe at size 80 passed:
- 40/40 short contacts visible.
- Wide stroke: all 1200 samples retained, zero reader loss/overflow.
- First native preview submission: 1ms after the injected contact.
- Largest report-to-preview-submit delay: 14ms.
- Full-material release-to-drained tail: 2178ms under the 500Hz stress input.
- No QML runtime errors; original artwork settings and saved files preserved.

These are software pipeline timings, not optical panel measurements. The fast
preview removes the wait for first visible ink, but does not accelerate the
physical pigment model. Very rapid wide shading can still build a material
queue. Device report: papersketch-wide-device-2026-11-04.json.
No public release or version metadata was changed.
