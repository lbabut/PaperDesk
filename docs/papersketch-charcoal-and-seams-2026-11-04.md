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

Installation and real application testing await the owner's save/close
confirmation. After confirmation, inspect the freshly saved image for a
one-pixel pale column before installing; then run isolated size-80 fidelity
checks and verify saved artwork and settings are preserved.


The most recent saved owner cache was inspected read-only. It contained no
one-pixel white column flanked by dark pixels for more than 30 rows. The
photographed page may have newer unsaved marks, so this does not establish
whether its particular line is absent from saved artwork.
