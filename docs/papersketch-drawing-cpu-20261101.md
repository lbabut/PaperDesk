# Paper Sketch drawing CPU audit

Baseline: Paper Sketch 4.1.1, commit `202fc75`. Scope: dry-media kernel and read-only inspection of raster state copies. QML, input processing, damage publication, display conversion and metadata were not modified by this change.

The kernel recalculated the same surface grain and valley response for every covered pixel of every dab. These values depend only on the two existing 8-bit tooth and burnish values. A process-wide lookup now stores their exact double results for all 65,536 pairs. Pressure, pigment capacity, deposition, bonding and compaction retain their original arithmetic order. The lookup is initialized during page setup, and it is shared across pages.

The tradeoff is one additional 1 MiB lookup per process. The per-page material instance size and persisted cache format do not change. The host compiler prepared the constant table before the measured drawing work; the lookup initialization call measured below one microsecond on this host. This does not establish cold-load cost on the tablet.

Read-only inspection found no full-page optical or pigment copy for each ordinary pen point. A writer snapshot can cause a full QImage detach on the first edit after a manual Save. Tentative finger input intentionally saves the small fingertip map and affected 128px image/material patches for palm cancellation. Qt painting and texture-upload costs require separate display-path measurements; the kernel benchmark does not cover them.

## Verification

The comparison retains a byte-identical 4.1.1 header under `tests/fixtures/sketch-material-v411-before-grain-cache.h`. It verifies exact mass, optical image, fingertip, burnish, wear and sampling residue over 48 full 1,260-point trajectories: all eight tools, all three paper stocks, empty and loaded pages, tilted nibs, rotated finger contact and kneaded erasing. A further 1,179,648 one-pixel comparisons exercise every tooth/burnish pair across six drawing media and three pressures, including wear and partial pigment loads.

All comparisons pass, including AddressSanitizer, UndefinedBehaviorSanitizer and leak detection. The existing material and realism suites pass. A compile-time check also verifies that the lookup adds no bytes to the per-page material object.

```sh
c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/bench-sketch-material-grain-cache.cpp -o /tmp/material-grain-cache
/tmp/material-grain-cache
```

## Host CPU results

Each case uses nine alternating reference/candidate runs of the entire trajectory. Allocation and state reset are excluded. Raw runs, source hashes and validation details are in `papersketch-drawing-cpu-20261101.json`.

| Case | 4.1.1 median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| HB, fresh paper, size 12 | 9.510 ms | 7.802 ms | -17.96% |
| Charcoal, fresh paper, size 38 | 70.953 ms | 52.206 ms | -26.42% |
| Charcoal, loaded paper, size 38 | 35.556 ms | 26.541 ms | -25.35% |
| Finger, loaded paper, size 64 | 173.960 ms | 173.932 ms | -0.02% |

Finger transport does not use the new grain lookup. These measurements support reduced drawing-kernel work with unchanged visible and physical state. They do not establish that input queueing or delayed panel updates have been resolved. The combined application still requires tablet verification.
