# Rapid tiny circles and surrounding hatching

Run the dedicated hardware regression with the existing authenticated tablet connection:

```sh
python3 tests/run-sketch-native.py --detail-probe --detail-check-latency \
  --host TABLET_IP --key SSH_KEY --known-hosts KNOWN_HOSTS \
  --output work/detail-tablet.json
```

Use `--host-key-alias` if the Wi-Fi address uses a previously pinned USB host identity.
Save current drawing work before running: the diagnostic restarts xochitl. It uses a
private application/settings namespace, restores the previous configuration and
checks the saved artwork hash. This does not preserve an unsaved in-memory sketch.

For each of HB 3px and charcoal 3px, draw a 10x10 grid of 100 separate circles with
4/6/8 drawing-pixel diameters, each surrounded by four separate 3px diagonal
hatches. The patch is 200x200 drawing pixels. Each circle contains 17 samples
(including its closing point), each hatch five. Target sample interval is 2ms
(500 Hz while in contact), with 2ms pen lifts that retain pen proximity; actual duration is reported.
Use `--detail-proximity-exits` to stress full proximity exit/entry on each lift.
There are 500 contacts and 3700 down samples per tool, 1000 contacts overall.

The probe fails on missing contacts, incorrect sample counts per stroke, open
circle endpoints, missing material marks at any circle quadrant or hatch center,
queue overflows, a nonempty drained queue, injection errors or QML runtime errors.
It expects 4200 raw input records per tool, including release boundaries. If the
native fine preview is armed before injection, it also requires all 500 native
preview contacts and a released mask. An unsupported/inactive preview is recorded
as unchecked rather than treated as a successful preview test.

`--detail-check-latency` additionally fails if either mean queue age or the
release-to-drained tail exceeds 100ms. Omit it for a baseline measurement;
the report still records whether that budget was met.

Use `--detail-fullscreen` to exercise the full-screen fallback and then tap Exit
with the pen, requiring a return to the windowed view without any artwork change.

Use `--detail-no-preview` for a comparison with the provisional silhouette disabled.
Use `--baseline-qml PATH` to run a saved UI baseline against the same installed native module.

Reports contain exact optical/physical digests, queue age, maximum GUI timer gaps, release-to-drained time, native material
timing and (when available) the last contact's native preview submission delay.
These are software milestones, not measured optical panel latency. Pixel checks
verify material marks after processing; they cannot prove the provisional trace
followed the stylus on the physical display. That needs a camera measurement.

The shared deterministic pattern has a host regression for circular radius,
closure, independent hatch length, bounds and workload counts, included in
`scripts/test-sketch-native.py`. The evdev driver restores tilt and releases the
synthetic contact on cancellation. Hardware execution has passed all 1000 contacts and 7400 down samples on the tablet.
See [the latency audit](papersketch-latency-audit-2026-11-03.md) for the actual timings and remaining limitations.
The runner also compares the production namespace's material/cache/preference file
hashes and records installed native module hashes.

The separate fidelity/shading driver now fixes upright tilt before injection and
restores it afterwards. Its earlier uncontrolled runs must not be treated as
optically equivalent across changing physical stylus states. Hardware validation
of that correction passed: baseline/current complete optical and physical-state
digests match with all 1200 wide samples retained. Wide release tails remain
about 2.3 seconds.

Use `--detail-user-settings` for a separate acceptance run with synthetic 2B/charcoal 8px, strength 0.8 and legacy tone 51. It fails before injecting if these settings do not arm a strength-aware native preview; the previous full-strength-only workload could miss this disabling condition. The flag name is historical: these stale legacy fields are reset by material restore and are not the observed live user settings. It retains the same 100-circle/400-hatch pattern and all input integrity checks.
