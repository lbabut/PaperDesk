# Paper Sketch 4.1 material model

Date: 2026-11-01. Scope: native `sketch-material.h`; its API remains compatible with 4.0. Input acquisition, calibration, surface persistence and controls have separate integration coverage.

## Contact and media

Each medium now has its own monotonic width curve and a separate monotonic dose curve. At zero pressure or strength, pigment, fingertip, burnish and wear remain unchanged. The six width exponents are .90, 1.05, 1.15, 1.20, .80, .70; dose exponents are 1.20, 1.35, 1.45, 1.50, .90, .80 for 2H, HB, 2B, 6B, charcoal and soft charcoal respectively. These are chosen simulation parameters, not measured physical calibration.

Normalized tilt produces an oriented elliptical footprint. Tilt broadens the long axis and narrows the short axis; worn nibs broaden and flatten. Tilted charcoal has firmer shoulders than the soft circular dab. Missing tilt gives an upright tip. Every semiaxis is capped at 40 pixels, including maximum size, tilt and wear. The 82-column scratch arrays and 81-by82 padded fingertip map remain bounded. `footprintRadius()` provides conservative damage bounds to the raster layer.

Finger contact supports aspect 1..2 and orientation in radians. The persistent pigment map rotates with the contact; pickup, deposition and pairwise mixing conserve combined paper/fingertip mass exactly. Speed can affect contact strength in the input layer. No skin pressure sensor or detailed skin-ridge simulation is implied.

## Paper, wear and erasing

Plain paper retains the original deterministic multiscale grain. Smooth stock lowers and narrows the tooth range; rough stock increases contrast and adds broader structure. `setPaperKind()` rebuilds tooth only, retaining existing pigment and burnish. Firm strokes accumulate a per-pixel burnish map: polished areas catch future pigment differently, hold less additional pigment, and compact some loose pigment into the fixed fraction. Compaction preserves total mass. Existing pigment is never deleted when a capacity decreases. `resetSurface()` clears burnish only.

Each of the six dry media has independent normalized wear. It advances only at spatially resampled drawing dabs, by distance times pressure and strength, with rates .000003, .000004, .000006, .000008, .000018, .000024 per pixel. An initial stationary dab causes no distance wear. Sharpen resets only the selected medium's wear and leaves the drawing unchanged. Surface and wear persistence is provided by the raster layer.

Hard rubber removes loose and fixed pigment while rubbing. Kneaded rubber removes a gentler proportion with a strong preference for loose pigment, once at the first positive-pressure contact. Moving while held does not continue erasing; lift and dab again. An initial zero-pressure pointer event does not consume the later real-contact dab. Erasing intentionally removes pigment from the system.

## Verification

Both material suites pass with C++17, O2, Wall, Wextra and Werror. They also pass separate AddressSanitizer/UndefinedBehaviorSanitizer builds with leak detection. Tests cover:

- All existing pressure, conservation, saturation, import-compatible optical storage, residual fingertip transfer, edge and event-splitting invariants.
- Rotated pencil tilt footprints, independent monotonic dose/width across every medium and pressure range, and bounded maximum fractional footprints.
- Three paper textures, surface evolution, no pigment rewrite on paper change/reset/sharpen, distance wear and untouched other nibs.
- Kneaded versus hard erasing, selective loose-pigment lift and delayed positive-pressure contact.
- Rotated elliptical fingertip transfer with exact mass conservation and unchanged burnish.
- Exact matching mass, image, burnish and wear for the same fixed-tilt path split into different event counts, including tiny events and pressure ramps.

Commands from the repository root:

```sh
c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/test-sketch-material.cpp -o /tmp/material
/tmp/material
c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/test-sketch-material-realism.cpp -o /tmp/material-realism
/tmp/material-realism
```

The pre-saturation-optimization CPU workload is `tests/bench-sketch-material.cpp`. Nine alternating 4.0/4.1 host runs each warm up 500 and measure 2,000 further 1.5-pixel segments per tool at pressure .7 and strength 1. Raw results, source hashes and per-run percentiles for that earlier 4.1 kernel are recorded in `papersketch-v4.1-material-benchmark.json`. This is host material-loop evidence; 4.1's pencil width profile also changes covered area. It is not tablet input or panel latency, and it does not establish that every tool is faster. Device input/display verification must be assessed separately.

## Final saturated-pixel optimization

The final header SHA256 is `3a9991e19a646a56c0b68059cdb20f237d2cdcbf004f94829c38e6bb53c34f6e`. When a drawing pixel has no remaining pigment capacity, the kernel now skips the zero-result dose/division/bonding calculation. Paper burnishing and pigment compaction continue unchanged. Footprints, emitted pigment and stored state do not change.

`tests/bench-sketch-material-saturation.cpp` compiles the byte-identical pre-optimization header fixture beside the final kernel. It proves bitwise equality of mass, optical image, fingertip, burnish, wear and sampler residue over 48 complete 1260-point trajectories: all 8 tools, all 3 paper stocks, blank and fully loaded surfaces, tilted tips, rotated elliptical finger and kneaded erasing. The same comparison passes AddressSanitizer/UndefinedBehaviorSanitizer with leak detection.

Nine alternating O2 host runs of the charcoal 38px trajectory measured median fresh-surface time 73.420→70.675ms (3.74% lower) and fully loaded time 71.724→36.849ms (48.62% lower). These are CPU-only measurements. The large improvement concerns saturated layering, not a claim of the same improvement in fresh-page shading or end-to-end tablet response. Raw runs and exact source hashes are in `papersketch-v4.1-saturated-material-benchmark.json`.

```sh
c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/bench-sketch-material-saturation.cpp -o /tmp/material-saturation
/tmp/material-saturation
```

## Limits

The model approximates grayscale dry pigment. It does not reproduce a measured pencil grade, real nib wear/geometry, graphite sheen, paper deformation, skin oils or finger ridges. Existing bitmap pixels cannot reveal original material; imported mass retains the existing inferred fixed/loose split. Sensor availability, calibration quality, e-ink halftone and waveform behavior affect the experience independently. Shape unit tests and software timing cannot establish physical equivalence or perceived tablet feel.
