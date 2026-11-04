# PaperDesk UI tests

`qml/tst_design.qml` exercises all seven visible apps at tablet resolution.
It checks shared Close geometry, the separate SSH command row and panel
ownership, finger-sized Web options with explicit current state, the RDP Save
dock and validation message, RSS actions and content-sized Care cards.
The runner stages the real Paper Terminal QML with a host build of its native
plugin, exercising PTY input and rendering without loading the tablet ARM
binary. Portable core tests cover VT parsing and bounded scrollback; native
integration tests cover process lifecycle, resize, input and SSH validation.
The physical `terminal` scenario remains required for e-ink refresh and the
reMarkable system keyboard. Desktop Qt has
an `Accessible` attachment that this firmware lacks; a package regression
prevents adding that load-time dependency accidentally.

Run the complete local suite with:

```sh
./tests/run-ui-tests.sh
```

Networking regressions in `qml/tst_network_lifecycle.qml` inject controllable
requests into the real apps. They exercise timeouts, cancelled/late callbacks,
optional CSS failure, stale Care status and operation completion without relying
on a public server. `test_installer_safety.py` runs the real installer in an
isolated filesystem with failed copies/renames, corrupt checksums and a signal
between app-renaming operations. No tablet paths are used by these host tests.

The separate Windows/POSIX preparation suite can be run in an environment with
the dependencies from `windows/requirements.txt` installed:

```sh
python -m unittest discover -s windows/tests -v
```

Build the native RDP logic regressions with `bash scripts/build-rdp.sh --tests`.
The resulting `work/tests/rdp-regression` is an ARM binary for the tablet: it
tests password-storage policy, certificate decisions, profile parsing and key
mapping without opening a framebuffer, connecting to a server or writing
profiles. `bash scripts/build-rdp.sh` builds the actual client. Neither command
publishes a release or installs anything on the tablet.

Run the hardware end-to-end suite against the USB-connected tablet with:

```sh
./tests/run-tablet-e2e.sh
```

Do not run hardware input tests in parallel or use the tablet during a run.
Screen capture is disabled by default; pass `PAPERDESK_E2E_CAPTURE=1` only when
needed. The runner gates cleanup on actual setup ownership, restores the
original settings, uses bounded FIFO shutdown, and temporarily runtime-masks
the firmware failure-reboot service during controlled maintenance, restoring
its previous enabled/masked state afterward. RDP profile actions and Care
management actions use live control geometry; Care scrolls controls into view
before tapping. The Care scenario only opens and cancels uninstall: it never
confirms removal or installs an update.

The Dots scenario allows up to 60 seconds for a large saved game to reconstruct
in small UI-friendly slices. If it finds more than 64 saved moves, it also
exercises large Undo before the new-game/mode checks. Host tests verify that
closing during reconstruction never persists a partial board. Input and game
changes during reconstruction are disabled; Close remains available.
New saves also have a bounded, validated derived checkpoint. Host regressions
verify exact board/base/score restoration, rejection of damaged or stale caches,
and cached Undo for recent moves; the portable move log remains the fallback.

`PAPERDESK_E2E_TARGET=ssh-sessions` physically taps New, native-keyboard fields,
Save, Edit, Open (localhost port 1, not a user server), Delete/cancel and
Delete/confirm. Settings are isolated and restored by the normal runner trap.
`PAPERDESK_E2E_TARGET=rdp` additionally opens the real system keyboard, checks
the fixed Save dock is above it, swipes the form and focuses Port. The host SSH
protocol regression checks that saved connections call the native connection
API; the backend rejects active/unknown launcher state and passes SSH arguments
directly to the process, so Open cannot type commands into a live remote shell.
The app probe also exercises Open again from retained SSH exit diagnostics,
visible busy-session feedback, default Mouse on, and the optional password
save/forget flow. It backs up and restores the private credential directory.

`tst_terminal_home.qml` checks the numbered start-screen list, pointer actions,
numeric selection (including two-digit numbers), and changes to the shared
saved-session model. The native tests verify that menu input is intercepted
only in the current local menu and cannot be carried into a remote session.
The AppLoad probe uses an isolated saved-profile list and a disposable
localhost endpoint for the start-screen flow, then restores the full config.

Session-switch regressions select the second of two profiles while a local
shell is active, cancel without affecting that shell, then confirm Close and
connect. Native tests reject stale process/menu-revision tokens and validate
the replacement endpoint and credentials before ending the current session.

RDP usability regressions cover exact keyboard scan-code flags, Unicode,
two-finger wheel/pinch separation, zoom/pan, shared raster/input transforms,
keyboard letterboxing, input reset, retry and changed-certificate rejection.
Build the memory-only ARM regression binary with `scripts/build-rdp.sh --tests`.
The real-device runner `tests/run-rdp-usability.py` additionally requires a
private loopback FreeRDP sample-server fixture at
`work/rdp-usability/server-src/fixture-server` (or `--server`), matching
`server.crt`/`server.key` and `changed.crt`/`changed.key`, and the local
`../PaperDesk-terminal/work/capture-terminal-screen.py` capture helper with
the bundled Pillow-capable Python runtime. These diagnostic fixtures are not
shipped in the product. Run without `--run` to prepare resources locally;
`--run` temporarily restarts the idle tablet UI and restores its configuration,
and `--deploy` retains the tested RDP apps only after every check succeeds.
`--e2e` builds a separate fixture client in `work/tests/`; its bounded private
FIFO and private config override are absent from the production binary.
Profile helper tests use temporary directories and exercise concurrent writes,
stale revisions, private correlated results, unknown outcomes and readback.
The login QML tests also verify real launcher exceptions, delayed ACK and
preserving unsaved fields after focus/refresh errors.
Saved-session pointer regressions also check that one click selects, a
double-click opens the clicked row exactly once, and the existing busy-session
confirmation remains required.

`tst_terminal_shortcuts.qml` exercises the function-key tab and pointer tap/hold
behavior for one-shot and locked Ctrl/Alt. Native PTY tests and the isolated
ARM raw-input probe verify the resulting bytes, modifier consumption,
multi-character commit rejection and the distinction between explicit
Ctrl+Alt combinations and a physical AltGr character.

`tests/run-terminal-ssh-integration.py` requires Paramiko in its Python
environment and a freshly built host helper (`scripts/build-terminal.py --test`).
It starts a temporary loopback SSH server with synthetic credentials, then
uses the real system OpenSSH client to verify manual host-key approval,
persisted opt-in password authentication and opening another saved connection
without returning to the menu first. HOME and known_hosts are isolated.

Books regressions compare the actual result delegate and viewport before and
after an offline save; real touch events exercise reader inertia and pinch.
`PAPERDESK_E2E_TARGET=books-live` downloads a real Gutenberg title from a scrolled
list, checks its viewport and shelf count, then opens and swipes the saved text.
It requires internet; cleanup discards the test download and restores the exact
original settings-backed book library. The runner requires an observed
QSQLITE-unavailable warning and refuses downloads on SQLite-equipped firmware
until a database backup/restore path is implemented.
`PAPERDESK_E2E_TARGET=dots-cache` opens the saved game,
closes it with a physical tap, restarts the frontend and requires a validated
checkpoint load under two seconds. Both use the normal input/settings trap.
`PAPERDESK_E2E_TARGET=dots-cache-large` uses a generated 431-move legacy save
for the same cold-load check, preserving the original game in the exit trap.

Run the repeated, user-style stability journey across every application with:

```sh
PAPERDESK_E2E_TARGET=journey PAPERDESK_E2E_LOOPS=2 ./tests/run-tablet-e2e.sh
```

The hardware suite temporarily routes Xochitl's touchscreen device to a
`/dev/uinput` panel, performs real kernel-level taps, swipes and two-finger
pinches, and restores both the physical input node and the original Xochitl
settings in an exit trap. Its default `all` scenario visits Terminal, WWW,
RDP, and RSS in one Xochitl session. It exercises every safe menu action,
keyboard opening, close/return flows, scrolling and pinch zoom. Actions that
could alter user data or start a real remote session are covered against
isolated fixtures in the QML suite instead. Set `PAPERDESK_E2E_TARGET` to
`terminal`, `web`, `rdp`, or `rss` to audit an individual product path.
The `journey` target repeats all five product paths, requires a fresh log event
after every physical action, and fails immediately if Xochitl restarts, its
watchdog fires, or the synthetic input device stops responding. RSS additionally
parses a tablet-side oversized feed fixture before the reader gestures run.
It also refreshes the real Physics World source while that source is selected,
waits for a one-feed completion event, and checks process health again.

The suite contains two layers:

- `test_package.py` prevents packaging regressions. In particular, it rejects
  any global AppLoad QRR override, verifies release checksums, and confirms that
  the shipped `resources.rcc` was rebuilt from the current hub QML.
- `tst_paperdesk_clicks.qml` renders the real PaperDesk hub and uses Qt Test
  pointer events to click Terminal, WWW, RDP, and RSS. A mock AppLoad launcher
  verifies the exact application ID requested by every click.
- `tst_product_actions.qml` clicks the complete PaperWeb and PaperRSS action
  surfaces. Its RSS add/delete flow uses an isolated temporary settings
  directory and a disposable feed, never the tablet's saved feeds.

`rm-touchd.c` is the live-tablet input helper. It creates a temporary `pt_mt`
touchscreen through `/dev/uinput`; the runner exposes that device as
`/dev/input/event2` before Xochitl starts. Commands use normal portrait-screen
coordinates; the helper applies the RM2 vertical-axis inversion. It is test
infrastructure only and is never installed by PaperDesk.

The RDP keyboard path is also verified against a real server with a separately
compiled `PAPERDESK_E2E` binary. The test clicks the remote terminal, sends
Backspace, `l`, `s`, and `Qt.Key_Enter`, then inspects the QTFB framebuffer for
the resulting directory listing. The E2E binary and its FIFO are temporary and
are not included in the release package.

Backspace and Enter are normalised before dispatch so that Qt key values, X11
keysyms, plain ASCII control codes, and control codes carried by the encoded
Unicode path all produce real RDP scan-code press/release pairs.

The dedicated Paper Sketch tablet probe `--detail-probe` exercises 100 tiny circles
and 400 surrounding hatches per tool at a target 500 Hz, checks input/material
integrity and records responsiveness. See [the hardware test instructions](../docs/papersketch-detail-test.md).

For latency regression gating add `--detail-check-latency` (100ms mean queue and
release tail budgets). `--detail-fullscreen` additionally tests the overlaid Exit
button with a real pen event, requiring no new artwork. Full results and the
operator incident are documented in [the latency audit](../docs/papersketch-latency-audit-2026-11-03.md).

The `preview-shade` native group checks the six leading-trace shade tables against material-engine output at 17 pressure anchors and verifies all fast-display raster thresholds. `test-sketch-native-batch.c` also checks that pale native previews preserve underlying pixels/masks, remain stable across repeated samples, and retain opaque ink and legacy erasure.


## Paper Sketch tablet regressions

The native ARM runner executes nine suites directly on the tablet without
restarting its UI. The extended UI probe additionally exercises five charcoal
layers on three paper stocks, both charcoal types, kneaded pressure/dab response
for graphite and both charcoals, actual Clear/confirmation
taps, and real Care foreground/background transitions with injected pen input.
Both produce JSON reports and check saved artwork preservation.

See [the tablet regression guide](../docs/papersketch-foreground-layers-and-tablet-tests-2026-11-04.md)
for commands, required device state and the distinction between CPU-only and
UI-changing runs. The extended UI flag is --extended-fidelity-probe.

Kneaded eraser strength, its contact cap, and device pressure ramp are covered in
[the kneaded regression report](../docs/papersketch-kneaded-strength-2026-11-04.md).

The charcoal-speed suite compares full optical, pigment, burnish, ink, finger and
sampler state with the frozen pre-optimization kernel and checks concurrent
independent surfaces sharing the row worker. Add --charcoal-benchmark to the
native tablet runner for paired 48/80 px timing measurements without UI restart.

See [wide charcoal calculation](../docs/papersketch-charcoal-wide-2026-11-04.md)
for the row-worker design and device measurement procedure.
