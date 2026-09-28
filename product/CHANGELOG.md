# Changelog

## 1.1.4 — release candidate

- The graphical Linux installer detects existing apps.
- The first install saves original app directories and restores them on uninstall.

## 1.1.3 — 2026-09-28

- Terminal forces several bounded refreshes on startup so an active SSH menu does not remain a blank e-ink panel.
- Each PTY buffer change triggers a controlled terminal redraw.
- The hardware test injects real text into the PTY and checks refresh, shortcuts, keyboard, and close.
- PaperWeb remembers the last successfully opened HTTP or HTTPS address and restores it on the next launch.

## 1.1.2 — 2026-09-27

- Added safe removal of the entire PaperDesk bundle without opening a terminal.
- Uninstall requires a separate, explicit confirmation.
- Connection profiles, reader data, and backups remain on the tablet.
- AppLoad resources reload automatically after removal.
- The release process always rebuilds embedded QML resources so a package cannot contain an outdated interface.

## 1.1.0 — 2026-09-27

- Added PaperDesk Care, showing installed and available versions and release notes.
- Updates use a signed Ed25519 manifest and a pinned public key.
- The ZIP is verified by SHA-256 before extraction, and its files by an internal manifest before installation.
- The installer still backs up the previous version and preserves app settings.
- The update job runs outside Xochitl, allowing it to reload XOVI safely after installation.
- USB installation requires only a local management code; the secret is not stored in the repository or process arguments.

## 1.0.5 — 2026-09-27

- Refreshed the whole visual system with editorial typography, lighter borders, consistent spacing, radii, and touch states.
- Adapted AppLoad's central MENU/KEYBOARD button to the new visual system.
- Reserved a clear central MENU zone in Terminal so the shortcuts and keyboard controls do not overlap it.
- Redesigned the home screen, RDP form, Terminal toolbar, Web reader, and RSS lists and forms.
- PaperWeb's keyboard appears only when the address field is touched and hides after an action, Enter, a page tap, or scrolling.
- PaperWeb requests mobile documents by default, simplifying layout before e-ink reader conversion.
- Mobile reader mode folds sections, grids, tables, and columns into one vertical flow instead of restoring multicolumn site CSS.
- Added a remembered Mobile/Computer switch; changing the mode reloads the current page with the selected request profile.
- The mobile reader recognises repeated headers and JSON-embedded data lists so JavaScript-built pages do not end on an empty screen.
- PaperWeb remembers Show/Hide Pictures; images are hidden by default, capped at 12, scaled to 760 px, and converted to static JPEG through a tablet-compatible TLS gateway.
- Reader cards place the title above the image; buttons show the active mode and switching action clearly.
- The AppLoad list hides the redundant PaperDesk hub and technical PaperDesk RDP Engine, leaving the user-facing apps visible.
- PaperWeb enforces calm black-and-white page rendering over site styles, without colours, shadows, or animation.
- RSS article text uses natural weight instead of constant bold, improving long-form readability.
- RSS lists use roomier article cards, a calmer sources panel, and more comfortable text widths.
- Added a one-time, non-invasive science starter set: Physics World, Quanta Magazine, MIT Technology Review, ScienceDaily, and Nature Physics.
- Capped a feed at 12 newest entries and 12 kB per entry to keep large feeds from blocking the UI thread or system watchdog.
- Refreshing one source now fetches only that feed; refreshing all merges, sorts, saves, and redraws the list once at the end.
- Completed RSS request callbacks no longer touch a destroyed window after the app closes.
- Added repeatable physical-tablet user journeys for the hub, Terminal, Web, RDP, and RSS, checking restarts, watchdog events, and fresh traces after each action.
- The RSS test parses a synthetic heavy feed on the tablet before running reader gestures.
- The hardware long-article fixture runs only during a live test, is read-only, and cannot replace the normal RSS cache.
- Verified compatibility on physical reMarkable OS 3.29.0.149 with AppLoad 0.6.0 and LiTerm 0.1.7.
- Handled zero or missing screen aspect ratio values from AppLoad 0.6.0.
- Centred AppLoad's MENU/KEYBOARD button relative to the full screen.
- Rebuilt the UI as a consistent, high-contrast e-ink product with one header, large touch targets, and a simpler hierarchy.
- Removed duplicated menus and a technical footer from the home screen; four tools now have clear product cards.
- Unified headers, action names, forms, and messages across Terminal, PaperWeb, PaperRDP, and PaperRSS.
- Gave all action bars uniform black-and-white buttons instead of prototype-looking default Qt controls.
- Added stable test targets to every safe UI action and covered them with automated click tests.
- The hardware journey visits four apps in one session, using real taps, scrolling, and two-finger gestures.
- Terminal keeps the keyboard hidden at startup; large buttons expose keyboard and shortcuts when needed.
- Terminal, RDP, and hub buttons use native touch handlers instead of mouse emulation.
- Fixed RSS full-text scrolling blocked by links and added a physical gesture test.
- Added automatic XOVI startup after a complete device reboot.
- Fixed link-coordinate offsets after scrolling in PaperWeb.
- Anchored the gesture layer to a stationary screen region.
- Link taps now account for the current page scroll and zoom.
- PaperRDP clears the e-ink screen when switching from login to the remote desktop.
- PaperRDP performs one delayed full refresh after connecting, without periodic flashing during work.
- Removed PaperRDP's second drawn keyboard; the app uses only the system keyboard.
- Added a visible instruction for opening the system keyboard by swiping from the top edge.
- Added RDP shortcuts: Ctrl+C/V/X/A, Alt+Tab, Ctrl+Alt+Del, Win, Esc, and Tab.
- System-keyboard typing refreshes only the form instead of the whole screen, preventing a clogged e-ink queue.
- The login screen clears remnants of the previous keyboard once.
- Backspace handles Qt Backspace, Delete, ASCII BS, and DEL.
- Added click tests for all four hub buttons and a test preventing global AppLoad overrides.
- The RDP login is a native QML form with system keyboard and working Backspace.
- A saved RDP profile populates the native form; FreeRDP starts only after Connect is pressed.
- Directly starting the RDP engine uses the saved profile instead of showing the old drawn-keyboard login.
- RDP updates delivered in bands are coalesced into a coherent frame before e-ink display.
- Repeated, unchanged pixels do not trigger unnecessary screen refreshes.
- The PaperDesk hub stays active underneath a running module, preventing an orphaned X button or blocked touch layer after RDP closes.
- The system keyboard's Enter works with both Qt Return and Enter codes in RDP.
- Backspace and Enter in an active RDP session normalise Qt, X11, and ASCII codes from different AppLoad keyboard versions.
- Control characters from the encoded Unicode path become real RDP scan codes rather than invisible text.
- RDP pan and pinch publish one coherent frame after fingers lift rather than flooding the e-ink queue every 320 ms.
- Large RDP desktop changes are rate-limited for the e-ink driver; small cursor and text updates remain fast.
- The native RDP form owns the window during a session; after RDP closes, the form returns instead of an orphaned AppLoad layer with an X button.
- Fixed an AppLoad 0.5.3 close bug: no access to a deleted loader, keyboard detached before window destruction, and close signal handled once.
- In fullscreen, AppLoad's `KEYBOARD` button directly toggles the system keyboard, without a short gesture and a disappearing icon.
- Inactive QTFB controllers no longer mark internal AppLoad windows as closed prematurely; the RDP form emits a real close signal and leaves no X layer.

## 1.0.4 — 2026-09-26

- Translated the PaperDesk, Terminal, PaperWeb, PaperRSS, and PaperRDP interfaces into English.
- Translated SSH profile menus and connection messages.
- Combined PaperWeb scrolling and pinch into one multitouch controller.
- Added minus and plus buttons for reliable zoom control.
- Preserved short-tap link opening.

## 1.0.3 — 2026-09-26

- Fixed PaperWeb pinch handling blocking normal scrolling.
- One finger now scrolls without animation or inertia.
- Two fingers still change zoom.
- A short link tap still opens the selected page.
- Enabled fast e-ink refresh while working with a document.

## 1.0.2 — 2026-09-26

- Removed an X button left above AppLoad after exiting a module.
- The hub closes only after safely launching a selected module.
- A zoomed RDP view can be panned with one finger.
- Panning is no longer forwarded to the remote desktop as a click.
- Refreshes during gestures were reduced to limit e-ink flashing.

## 1.0.1 — 2026-09-25

- Fixed hub closing that could leave an inactive AppLoad window.
- The hub remains the home screen and accepts return from every module.
- Enabled safe reopening of the hub after an AppLoad failure.

## 1.0.0 — 2026-09-25

- First shared PaperDesk home screen.
- SSH Terminal, PaperWeb, PaperRDP, and PaperRSS in one bundle.
- Installation with backup and data preservation.
- Consistent, high-contrast interface without animation.
- Release package with checksums.
