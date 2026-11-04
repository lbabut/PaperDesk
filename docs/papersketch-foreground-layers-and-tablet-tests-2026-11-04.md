# Foreground input ownership, charcoal layers and tablet regressions

Sketch kept its raw reader and direct preview armed while Care covered it.
AppLoad disabled the underlying window, but Sketch checked visibility without
inherited enabled state. Native strokes continued after Care had opened.
Sketch now requires enabled ownership for raw input and heartbeat publication.
Losing visibility or enabled state disarms preview, disables the native pointer
filter, and ends or cancels a contact. Returning to foreground re-enables input.
No shared launcher changes were needed.

Normal charcoal is lighter and drier; soft charcoal is darker and broader with
more loose pigment. Their dose, pressure, width and capacity responses differ.
Repeated passes darken gradually. On actual tablet plain paper, normal charcoal
mean gray went 227.7 to 170.1 over five passes; soft charcoal 136.8 to 59.3.
All five passes darkened on all three paper stocks.

Validation:
- Sketch QML: 66 passed, 0 failed, 2 device-runtime skips.
- Host material, realism, frozen pencil compatibility, charcoal, blank-pigment,
  rear eraser and regenerated preview shades passed.
- Tablet New page/Clear leave zero initial pigment; all 1200 wide-stroke input
  samples retained, with tonal texture and correct optical/pigment consistency.
- Actual touch input tapped Clear page and its confirmation. Sketch stayed
  foreground, and the cleared pigment sum was zero.
- Launching real Care disabled raw input and preview. Forty real pen contacts
  over Care changed neither Sketch image nor stroke count. Closing Care
  restored drawing and exactly 40 resumed preview contacts.
- Seven native ARM suites passed on the tablet: charcoal layers (three papers,
  two widths), material conservation/resampling, realism, pressure, touch,
  ordered pen input, and display conversion.
- Owner artwork/settings hashes preserved; installed ink/raster/RCC hashes
  match the tested payload; UI service active after configuration restoration.

Repeat from the source checkout on the workstation:

    python3 scripts/run-sketch-tablet-regressions.py --host TABLET_IP --key KEY_PATH --known-hosts HOSTS_PATH --host-key-alias 10.11.99.1 --output docs/native-tablet-results.json
    python3 tests/run-sketch-native.py --host TABLET_IP --key KEY_PATH --known-hosts HOSTS_PATH --host-key-alias 10.11.99.1 --extended-fidelity-probe --fidelity-brush-size 80 --output docs/tablet-ui-results.json

The first runner compiles ARM binaries and executes them directly on the tablet
without restarting its UI or grabbing device input. The UI suite uses an
isolated frontend and restarts the tablet UI: save/close artwork first and
leave tablet input idle. It restores configuration and checks owner hashes.
Install matching current native modules before the UI suite. These are software
timings, not optical e-ink latency. Extreme 500Hz wide shading still has about
2.6 seconds of final material catch-up; immediate preview remains active.

Reports: papersketch-native-tablet-regressions-2026-11-04.json and
papersketch-layers-foreground-device-2026-11-04.json.
No public release metadata changed.
