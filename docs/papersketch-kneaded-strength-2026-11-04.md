# Kneaded eraser strength — 2026-11-04

The previous kneaded contact removed at most 55% of loose pigment and 12% of fixed pigment. The fixed-pigment limit made dark graphite and worked charcoal barely lighten. The new full-pressure bounds are 90% loose and 50% fixed pigment, with a less restrictive fixed-pigment pressure curve. Soft edges, pressure response and preferential loose-pigment removal remain.

Removal is capped per contact, independent of pointer sample count. Higher pressure during a contact can lift more; holding at constant pressure cannot keep bleaching the paper. Lifting and dabbing again removes another layer. Ink remains unaffected.

## Verification

- Host targeted native suites: kneaded strength, material, material realism, contact cache, realism integration, blank pigment, rapidograph integration and stylus eraser.
- QML: 67 passed, 0 failed, 2 device-only skips.
- Eight native suites passed on the tablet ARM CPU without restarting the UI or grabbing input. Saved artwork hashes were unchanged.
- The dedicated pure C++ test covers dense fixed pigment, graphite and two charcoal mixtures; zero pressure, increasing pressure, 100 held samples and a second dab.
- The extended device UI suite passed all nine graphite/charcoal and paper combinations, held-contact checks, Clear and Care foreground/background checks. No QML runtime errors. Saved artwork and settings were preserved.
- A kernel input pressure ramp from 0.125 to 0.88 lightened the sampled soft-charcoal patch from gray 34.16 to 156.77; firm API contact reached 176.19 and a second dab 231.20.

Native CPU results: [JSON](papersketch-kneaded-native-device-2026-11-04.json).
UI results: [JSON](papersketch-kneaded-ui-device-2026-11-04.json).

CPU fixture center grays (0 black, 255 white):

| Medium | Before | Light | Medium | Firm | Second dab |
|---|---:|---:|---:|---:|---:|
| Dense fixed pigment | 2 | 4 | 9 | 25 | 79 |
| Graphite | 61 | 70 | 94 | 132 | 184 |
| Normal charcoal mixture | 87 | 105 | 151 | 210 | 239 |
| Soft charcoal mixture | 61 | 80 | 134 | 213 | 246 |

These are software pigment/optical values, not optical measurements of the e-ink panel.

## Run on the tablet

Use the SSH host/key arguments documented in [the tablet regression guide](papersketch-foreground-layers-and-tablet-tests-2026-11-04.md). Run scripts/run-sketch-tablet-regressions.py for eight native ARM suites, or tests/run-sketch-native.py --extended-fidelity-probe --fidelity-brush-size 80 for the isolated UI/input checks. The latter temporarily restarts the UI and restores the owner's saved settings and artwork.
