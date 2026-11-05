# Paper Calc research and implementation — 2026-11-05

The user's priorities are PaperDesk styling, large readable keys, no animation,
a real office calculator feel and function graphs. The selection below is a
fit assessment for that use, not a universal ranking of physical calculators.

| Reference | Official evidence | Adopted in Paper Calc |
| --- | --- | --- |
| Casio DJ-120D | [12-digit desktop model with 150-step checking](https://www.casio.com/us/basic-calculators/product.DJ-120D/) | Immediate execution, 12-digit presentation, grouped large keys; a 150-result reusable tape rather than a step-by-step checking emulator |
| Casio MU behavior | [Manufacturer's 120 / 25% example](https://www.casio.com/intl/support/calculators/faq/article/00/06/83/26/) | Selling price 160 and profit 40; margin measured against selling price |
| TI-84 Plus CE | [Manufacturer specifications](https://www.university.ti.com/en/products/online-calculators/ti-84ce-online-calc/specifications), [graph/trace/table tutorials](https://education.ti.com/en/product-resources/product-video-tutorials/ti-84plus-ce-tutorials) | Function editor, graph window, zoom, trace, numerical table and approximate zeros; three monochrome curves instead of the original ten colored functions |
| Casio fx-CG50 | [Official guide: graphing](https://edu.casio.com/support/qsg/pdf/fx-CG50/02_CASIO_QuickStartGuide_fx-CG50_GRAPH.pdf), [official guide: modes](https://edu.casio.com/support/qsg/pdf/fx-CG50/00_CASIO_QuickStartGuide_fx-CG50_Function%20keys%20and%20icons.pdf) | Confirms usefulness of a separate graph/table workspace; no animated/3D/image graph modes selected |

Recommendation: combine the desk calculator interaction of the DJ-120D with
selected TI-84 graph workflows. Use PaperDesk's Quiet Ink visual rules, not
manufacturer branding or firmware. The app contains an original implementation.

## Implementation and evidence

Baseline arithmetic/ink engine imported from the previous Paper Calc feature
at `2026-11-03-jeszcze-musimy-co-zoptymalizowa-w-paper/repo`; current canonical
PaperDesk was inspected first and had no Paper Calc directory. Its Quiet Ink
design tokens guided the replacement. Only calculator-owned files are added
to canonical PaperDesk; installer, launcher and release metadata are untouched.
The original imported skin is archived in this task's `work/papercalc-original.tar.gz`.

- 29 engine checks: immediate versus precedence execution, percentage contexts,
  repeat equals, memory, GT, scientific domains,
  parser rejection, variable evaluation, root finding and rejection of a pole.
- 13 QtTest cases including setup/cleanup: actual UI clicks,
  graph/table/trace/range operations, once-per-press dispatch without key-color
  changes, save/destroy/recreate persistence, and
  layouts at 1404×1872, 800×1024 and 1872×1404.
- Rendered actual QML desk and graph screens inspected as PNG files.
- Resource bundle built with Qt RCC; package contains only referenced runtime
  sources, manifest and icon. SHA-256 manifest accompanies the package.

The keypad-only revision was installed over USB on the physical reMarkable.
Startup was confirmed in Xochitl logs and the installed resource SHA-256 matched
the built bundle. Tablet touch behavior and optical e-ink refresh were not measured.
The inherited Qt.labs.settings API is retained for tablet compatibility; the Qt 6
host prints its deprecation notice. No load or rendering errors remain.

## Follow-up: keypad only

At the user's request the Ink tab, writing canvas, ink state and handwriting
recognizer were removed entirely. Desk, Science, Graph and History now occupy
four equally wide navigation buttons. Existing calculator memory, history and
graph settings retain their original storage keys.

## Follow-up: simpler desk calculator

Removed the entire business-function row (Set TAX, TAX+, TAX−, MU/margin),
tax state, display labels and the business calculations themselves. The desk
keypad now uses the freed space for taller keys. Percentages, memory and basic
arithmetic remain. Existing saved history and memory are preserved.

## Follow-up: key response and display method

The original keys inverted their full background on press/release and dispatched
on release. They now keep static colors and dispatch once on press. A local
DisplayMethodArea selects AppLoad.Fast, matching other PaperDesk applications;
the global launcher and firmware refresh settings are not changed. DEL replaces
the backspace glyph that was unclear on the tablet. Host tests check that the
value changes before release, release adds no digit, and repeated taps are kept.

The isolated on-tablet comparison passed all 12 injected digit taps (six per
version): input-to-value software time was 83–91 ms before and 5–8 ms after;
input-to-first-subsequent-frame was 104–117 ms before and 18–23 ms after.
These are input/Qt submission timestamps, not optical panel latency. The two
versions used isolated settings; original Xochitl configuration was restored
and the probe was removed from AppLoad. See papercalc-key-response-2026-11-05.json.

## Follow-up: fast monetary entry and overlapping fingers

A host touch regression reproduced a missed second key: holding digit 1 and
pressing digit 2 produced 1 instead of 12 with MouseArea. Replacing mouse
synthesis with MultiPointTouchArea fixed that regression. A second integration
test enters twelve amounts using real Qt touch events, including consecutive
identical digits and decimals, and checks the exact displayed total 659.19.

The hardware probe injects all 72 contacts without SSH waits between keys, at
120/60/40 ms intervals and with an 80 ms hold at 60 ms intervals (overlap).
Only its isolated application is exercised; original calculator settings and
Xochitl configuration are preserved. Counts and totals, not optical refresh
timing, determine success.

The on-tablet A/B reproduced the overlap loss: the old MouseArea accepted only
36/72 presses and produced 1.12233445566; direct touch accepted 72/72 and
produced 659.19. Both versions accepted sequential 120/60/40 ms bursts.
The final revision also separates the immediate desk model from its display
snapshot: intermediate repaints are paced at 80 ms, with AC/equals/errors
published immediately. The app retains its existing Fast display method.
The final hardware rerun checks both the model total and displayed snapshot.

Cold-autostart limitation: the first synthetic contact following an Xochitl
restart was consistently consumed before monetary entry, including after
changes to focus and slot initialization. This is not claimed fixed. Final
normal-use burst checks explicitly activate the tablet with one contact on
the non-interactive display before entering amounts. The activation is recorded
separately and is excluded from monetary key counts. Normal calculator entry
is then checked at every tested cadence with the displayed snapshot included.

Final awake-screen verification passed all twelve series: 864/864 monetary
contacts accepted, at 120/60/40 ms intervals and 60 ms intervals with 80 ms
holds. Every model and display snapshot ended at 659.19. See
`papercalc-burst-2026-11-05.json` for scope, activation and per-series evidence.
