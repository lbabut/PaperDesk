# Paper Calc / PaperDesk Quiet Ink

Offline Qt Quick calculator for reMarkable. Black ink on white, large outlined
keys, tall + and =, black primary actions, no animations, photo assets, network
calls or added runtime dependencies. English UI follows the other PaperDesk apps.

- **Desk:** immediate execution (`2 + 3 × 4 = 20`), 12 significant digits,
  repeated equals, %, ±, √, 00, backspace, CE, AC, MC/MR/M+/M− and GT.
  AC clears the calculation and grand total; MC clears memory. GT sums results
  obtained with equals. Memory persists across app restarts.
- **Science:** operator precedence (`2+3×4 = 14`), parentheses, powers,
  factorial, trig/inverse trig, logarithms, exp, abs, sqrt, π, e, Ans, DEG/RAD.
  Powers associate right; `-2^2 = -4`. Multiplication must be explicit.
- **Graph:** three expressions Y1–Y3, solid/dashed/dotted lines, editable
  X/Y limits, zoom, standard window, DEG/RAD, tap-to-trace, trace arrows,
  seven-row table around the trace point and approximate sign-changing roots.
  Tap a formula to edit it with the keypad; tap its Y badge to enable/disable it.
  Press DRAW after editing. Select a window limit, AC, type, APPLY to change it.
  Functions, enable flags, angle mode and window persist across restarts.
- **History:** the live, scrollable receipt retains every entered amount and operator.
  Completed calculations persist in full, with no line truncation or entry limit.
  Tap a result to reuse its answer. CE/DEL correct the current amount; AC starts
  a new receipt and preserves saved calculations. Desk arithmetic remains immediate.

Numbers use IEEE 754 arithmetic; results display 12 significant digits. Graphs
sample 401 points per enabled function. Domain errors break curves and a jump
filter suppresses lines across poles. Roots use bisection after a sign change;
roots touching the axis can be missed. This is a selected practical feature set,
not full TI-84/Casio emulation (no CAS, matrices, 3D or programs).

Build from repository root: `bash scripts/build-calc.sh`.
Verify: `bash scripts/test-calc.sh` (Node plus the cached host Qt test runtime).
`PAPERDESK_QT_TEST_USR` can point to another matching Qt runtime with QtTest and
Qt.labs.settings. Test settings are separate from installed calculator data.

The AppLoad package consists of `manifest.json`, `resources.rcc`, `icon.png`
in an app directory named `papercalc`. This task builds that package; installing
it on a tablet and public release are separate steps. See the research and
verification notes in `docs/papercalc-research-2026-11-05.md`.

Responsiveness: the app uses AppLoad's Fast display method, scoped to the
calculator. Keys dispatch once on press and keep their colors while held, so a
tap updates the display without inverting and repainting the whole key twice.
The delete key uses the plain-text label DEL for reliable tablet font rendering.

Keys observe touch points with passive PointHandlers rather than synthesizing
a single mouse pointer or exclusively grabbing a MultiPointTouchArea. Rapid repeated digits and a second finger landing before the first
finger lifts are accepted independently, once per new contact. Mouse/stylus
input remains supported. Hardware burst probes compare both contact styles
with twelve monetary amounts (72 presses, expected sum 659.19).

The desk model processes every contact synchronously. Its display snapshot is
published immediately after idle and then at most once per 80 ms during a burst;
AC, equals and errors publish immediately. The app retains the Fast display method.
This bounds intermediate repaint requests without dropping input or delaying
arithmetic. Panel optical latency and ghosting are not measured by these tests.

Science uses the same 80 ms display pacing as Desk. Expression input is accepted
synchronously; the first idle key is visible immediately, burst updates are
coalesced, and equals, clear and mode entry flush the current expression. Numeric
results and error messages are published immediately. All modes share direct
multi-contact keys with no pressed-color inversion or animations.

Graph quick start: select the wide Y1 formula field, AC, x, x², −, 4, DRAW.
The small Y1 badge enables/disables that curve (black means enabled). DRAW
recomputes curves after editing; Standard restores the default window. Tap the
plot or use arrows to read x/y; Table shows nearby values; Find zero locates the
nearest sign-changing root. Select a window limit, AC, type a value and APPLY.
RAD is radians and DEG is degrees for trigonometric functions.

Automated Graph UI coverage lives in `tests/qml/tst_calcgraph.qml`: keypad entry,
three curves, enable flags, deferred DRAW, range entry/rejection, zoom/standard,
trace positions and clamping, table values/domain holes, DEG/RAD, invalid formulas,
roots versus poles, and actual Canvas repaint requests. The main app tests also
exercise rapid and overlapping Science contacts and bounded display publications.
Run both with `bash scripts/test-calc.sh`.

For an attached USB reMarkable, `python3 scripts/test-calc-device.py` builds a
separate test app with isolated settings. It checks Graph control handlers and
Canvas paint, then injects two 72-contact Science streams at 25/s and with
finger overlap. It restores the previous launcher configuration and removes the
test app from AppLoad on exit. It requires the cached ARM compiler and Qt rcc;
results are written to `work/papercalc-science-graph-device.json`. Software input
acceptance and repaint counts do not measure the e-ink panel's optical latency.

Rapid alternating-key regression: `python3 scripts/test-calc-repeat-device.py`
uses a separate test app and isolated settings. Add `--host 192.168.1.167
--host-key-alias 10.11.99.1` for the known Wi-Fi host. Eight streams each enter
60 ones separated by + and finish with =, checking the full accepted key order
and result 60. They cover release and press in one sensor frame, slot reuse,
overlap, 50 presses/s and a 100 ms GUI stall. The host Qt tests also verify
same-key overlap, no duplicate mouse/touch input and no typing by dragging.

The host test runner also compiles `tests/calc-buffered-touch.cpp` with the
cached Qt SDK and a C++17 compiler. Set `PAPERDESK_QT_TEST_INC` to another matching
Qt include directory when needed. It queues touch frames before processing GUI
events and verifies the full receipt, with and without same-frame handoffs.
