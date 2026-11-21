# Repeatable on-device speed checks

Run explicitly while the owner permits a UI restart and no physical input is
in progress. This is not an unattended timer: it takes over the display and
injects Linux evdev input into a disposable diagnostics app using production
Sketch handlers. The settings/cache namespace is unique. Original document
settings and checked Sketch material-cache files are hashed before/after;
this is not a full-library backup. Unsaved current strokes can be lost on restart.

```
python3 scripts/test-sketch-device-performance.py \
  --safe-state-confirmed --host 10.11.99.1 \
  --host-key-alias 192.168.1.167 \
  --key /home/lukasz/.ssh/id_ed25519_remarkable \
  --known-hosts /home/lukasz/.ssh/known_hosts \
  --expected-installed-rcc 3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1 \
  --repeats 3 --output-dir /tmp/sketch-speed-UNIQUE
```

Output directory must not exist. Native raster must match the local built
artifact; explicit installed RCC packaging hash additionally requires deployed
QML/engine source hashes to match. No native modules or production app packages
are installed by these checks. SSH host verification is mandatory.

Each repeat tests graphite 12px and charcoal 38px, 1260 synthetic samples per
case. Reports retain module/source/harness hashes, input correctness, queue
p95 upper bound, maximum GUI timer gap, release-to-drained tail, and idle
environment information. `summary.json` contains median and worst values.
Any failed repeat fails the aggregate: no averaging a regression away.
Initial engineering budgets (not measured physical perception thresholds):
GUI gap <200ms, queue p95 <100ms, release tail <150ms.

Exit 1 means a failed/incomplete check, not necessarily a crash. Raw reports
and logs remain available even after a budget failure. Incomplete/unsafe runs
stop further repetitions. The guarded runner attempts to restore config and
restart UI in `finally`; a disconnected/crashed host can still prevent cleanup.
Recovery artifacts are retained on device under `.local/state/papersketch-native.*`.

These checks measure software latency under synthetic pen shading, NOT physical
touch-controller delivery, menu touch-to-photon time, e-ink refresh or human
drawing feel. Idle CPU/memory are context, not active-load saturation evidence.
Use a camera/sensor for optical panel measurements. No background schedule is
created, and passing this benchmark alone does not accept UAT responsiveness.

Host report-validation tests:
`python3 -m unittest discover -s tests -p test_device_performance_report.py -v`
