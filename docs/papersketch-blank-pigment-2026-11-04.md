# Blank canvas turns charcoal into opaque black bands

A saved owner page matching the reported photograph contained packed pigment
0xff000000 under white optical pixels. Its pigment sum is 65280 out of 65535.
A stroke touched those pixels, found no deposition room, and displayed their
existing near-black pigment. This was an initialization fault rather than
evidence of a missing charcoal texture or a stale live preview.

The physical pigment map used QImage::Format_RGB32. clearPage() called fill(0),
which forces the opaque alpha byte to 0xff in that format. The format's alpha
normalization overwrote the upper eight bits of the packed fixed-pigment mass.

The pigment map now uses non-premultiplied Format_ARGB32 for bit-preserving
storage. Clearing fills all 32 bits with zero. Optical images remain RGB32.
When loading historical material caches, exactly-white optical pixels with
the known 0xff000000 sentinel are repaired to zero pigment in memory.
Existing optical pixels and genuine marked pixels are unchanged. Opening does
not rewrite files; the corrected physical state persists on explicit Save.

A regression failed before the fix and passes after it. It checks fresh/reset
and cleared pages, identical strokes from every dry tool on both blank states,
historical sentinel repair, drawing preservation, and explicit-save migration.

Validation completed before installation:
- Focused native regressions: blank pigment, rapidograph cache/PDF, finger,
  physical material, workflow, legacy/physical state, toolkit, publication,
  raster, preferences, raw input, rear eraser, PDF and latency all passed.
- Sketch QML suite: 65 passed, 0 failed, 2 device-runtime skips.
- ARM renderer built successfully.

The real-input fidelity harness now invokes the actual New page action and
Clear page action. It requires zero pigment and no optical mismatch on both,
then checks charcoal tonal variation as well as input completeness.
Device verification passed:
- Fresh book and actual New page action: pigment sum 0, no optical mismatch.
- Actual Clear page action after drawing: pigment sum 0, no optical mismatch.
- Wide charcoal: sampled optical gray range 75..228 rather than a flat black band.
- All 1200 input samples retained; no queue loss or QML errors.
- Saved owner artwork and configuration hashes preserved.
- Installed renderer and RCC hashes match the tested payload; UI service active.
Report: papersketch-blank-pigment-device-2026-11-04.json.

The owner UI Save acknowledgement was observed before installation. The
previous drawing caches and preferences were backed up, and the normal
isolated tablet probe verified their preservation across the test.
No public release metadata was changed.
