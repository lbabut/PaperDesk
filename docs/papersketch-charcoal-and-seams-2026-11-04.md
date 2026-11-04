# Charcoal response and tile-border guard

The owner reported uniformly filled charcoal strokes and a straight pale line
crossing several marks in a tablet photograph.

Charcoal and soft charcoal now normalize deposition by footprint radius.
Broad strokes no longer saturate just because many dabs overlap. The paper's
grain response also modulates the dose. Tilt produces a wider, flatter charcoal
side than a pencil nib. Loose-pigment binding, layering and conservative finger
transfer remain part of the physical model.

The native live preview now varies charcoal density across its footprint and
uses stable spatial grain. Its narrow-tip shade lookup was regenerated from
the changed material model. New charcoal marks retain a softer grainy edge.

The native QML tile loaders carry one source pixel beyond their right/bottom
border, bounded by the sheet. This protects fractional-scale tile coverage
without changing the authoritative image or saving artificial border pixels.
A regression exercises incremental painting across all tile borders at scales
.73, .87, .95, 1, 1.07 and 1.17. All interior pixels remain covered. The exact
photographed artifact has not been reproduced on the host; the tile guard is
a candidate mitigation, not proof of its origin.

Validation:
- Sketch QML: 65 passed, 0 failed, 2 tablet-runtime skips.
- Focused material tests passed: monotonic pressure, loose dust, layered
  darkening, broad texture and full-state event resampling.
- Narrow preview shades match the material samples at all 17 pressure anchors.
- Maximum-width native preview regression passed on tablet ARM CPU using a
  private memory framebuffer without restarting the running Sketch app.
- Native regression coverage completed successfully across the initial and
  remaining runs. The rear-eraser fixture now lays down six charcoal contacts
  to retain its original dark-seed precondition with the softer deposition.
  Material persistence, PDF, pressure, smudge conservation, publication, latency
  and raster checks passed. Final preview checks also passed after feathering.
- ARM native modules and RCC built; no public release published.

Installed on the owner's tablet after explicit save/close confirmation.

The actual size-80 input fidelity probe passed: 40/40 tiny contacts, all 1200
wide-charcoal samples retained, zero input loss/overflow, no QML runtime errors.
First native preview submission was 1ms after injected contact; maximum
report-to-submit delay was 15ms. Full-material release tail was 2852ms in the
500Hz stress workload. These are software timings, not optical panel latency.

The saved artwork and settings hashes are unchanged after the isolated probe.
The installed ink/raster modules and RCC hashes match commit 117f70f's payload.
The tablet UI service is active following restoration of the user's settings.

All ten owner cache pages were inspected read-only. None contained a one-pixel
column above gray 230 flanked by pixels below gray 70 for more than 30 rows.
This supports investigating display composition, but does not optically
reproduce or conclusively identify the photographed line. The tile-border guard
is installed; visual confirmation from the tablet remains necessary.

Device report: papersketch-charcoal-device-2026-11-04.json.
Saved-page column scan: papersketch-charcoal-seam-inspection-2026-11-04.json.
No public release or version metadata was changed.
