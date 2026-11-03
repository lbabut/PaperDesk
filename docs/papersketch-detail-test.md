# Rapid tiny circles and surrounding hatching

Run the dedicated hardware regression with the existing authenticated tablet connection:

```sh
python3 tests/run-sketch-native.py --detail-probe \
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
(500 Hz while in contact), with 2ms pen lifts; actual duration is reported.
There are 500 contacts and 3700 down samples per tool, 1000 contacts overall.

The probe fails on missing contacts, incorrect sample counts per stroke, open
circle endpoints, missing material marks at any circle quadrant or hatch center,
queue overflows, a nonempty drained queue, injection errors or QML runtime errors.
It expects 4200 raw input records per tool, including release boundaries. If the
native fine preview is armed before injection, it also requires all 500 native
preview contacts and a released mask. An unsupported/inactive preview is recorded
as unchecked rather than treated as a successful preview test.

Reports contain maximum GUI timer gaps, release-to-drained time, native material
timing and (when available) the last contact's native preview submission delay.
These are software milestones, not measured optical panel latency. Pixel checks
verify material marks after processing; they cannot prove the provisional trace
followed the stylus on the physical display. That needs a camera measurement.

The shared deterministic pattern has a host regression for circular radius,
closure, independent hatch length, bounds and workload counts, included in
`scripts/test-sketch-native.py`. The evdev driver restores tilt and releases the
synthetic contact on cancellation. Hardware execution of this new probe is pending
the user's saved-work confirmation; host compilation, geometry and QML component
loading have passed.
