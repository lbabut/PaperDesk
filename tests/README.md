# PaperDesk UI tests

Run the complete local suite with:

```sh
./tests/run-ui-tests.sh
```

Run the hardware end-to-end suite against the USB-connected tablet with:

```sh
./tests/run-tablet-e2e.sh
```

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
