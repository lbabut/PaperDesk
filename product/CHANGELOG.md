# 4.1.3 — 2026-11-01

- Moved the Paper Sketch Materials settings icon to the first position in the middle toolbar, before the 2H pencil.

# 4.1.2 — 2026-11-01

- Start pen strokes at initial contact, including stationary dots, without waiting for a drag or pen release.
- Reduce repeated material calculations with a shared lookup of the same paper-response values, retaining the material equations and rendered image.
- Add isolated fresh/layered-page software latency diagnostics for input, material updates, publication and tile painting; these do not measure optical e-ink latency.

# 4.1.1 — 2026-11-01

- Moved the Paper Sketch Materials settings icon from the header into the bottom navigation bar.

# 4.1.0 — 2026-11-01

- Added directional tilt contact for graphite and charcoal, with an upright-tip fallback when tilt data is unavailable.
- Added stylus pressure calibration for the digital response, feeding distinct width and pigment deposition responses; no physical-pencil equivalence is claimed.
- Added Plain, Smooth and Rough paper contact presets and a persistent simulated burnishing map; changing paper preserves existing pigment.
- Added distance-based virtual tip wear and Sharpen for the selected tool.
- Added variable finger contact and Clean finger to clear pigment carried by the fingertip.
- Added two eraser models: a hard eraser that rubs along the stroke, and a kneaded eraser that lifts pigment once per contact for repeated dabbing.
- Updated installation guides, Care version and the project site. Source links remain on public GitHub; earlier release archives remain unchanged.

# 4.0.0 — 2026-11-01

- Added Paper Sketch to the installable bundle: pressure-sensitive graphite and charcoal, textured paper, pigment-lifting eraser and finger blending.
- Replaced text actions with icons and placed the tool-size slider in the same toolbar, giving the canvas the space previously used by the lower size bar.
- Audited material mass transfer, pointer sampling, save/export handling and incremental display rendering; kept full grayscale in saved artwork and PNGs.
- Installed the native material renderer with a supported-firmware check, previous-module backups and uninstall restoration; sketchbooks and exported PNGs remain intact.
- Updated the project site and both guides for eight apps, and linked source browsing directly to the GitHub repository.

# 3.0.3 — 2026-10-20

- RDP keeps its desktop, toolbar and shortcuts in one landscape coordinate space, including when opening or dismissing the keyboard.
- The existing system keyboard follows landscape sessions without replacing firmware resources or changing the tablet's global orientation.
- Native keyboard geometry and original bindings are restored on hide, foreground loss, Close and unexpected window destruction.
- Added regression tests for lazy keyboard discovery, bounded retries, layout restoration and stationary, reachable shortcut buttons; verified physical typing, Backspace, Enter, Close and reconnect on RM2.
- All seven apps and existing data remain included; updated signed Care feeds and manual SSH project packages.

# 3.0.2 — 2026-10-18

- Books now searches six sources: Project Gutenberg, Wolne Lektury, OpenStax, arXiv, Europe PMC and unrestricted Open Library / Internet Archive editions.
- PDF and EPUB downloads use the native My files importer and built-in reader; text reading and existing bookmarks remain available in Books.
- Web restores PDF/EPUB downloads with confirmation, cancellation, a 64 MB cap, free-space checks and structural validation before import.
- Downloads stream in a hidden worker, with HTTPS, resolved-address/redirect checks, timeouts and shared transfer locking instead of buffering binaries in QML.
- Deferred Books initialization preserves saved content, bookmarks and settings; interrupted native imports include a check-My-files warning.
- Updated source-first installation guides and signed Care feeds. No graphical installer links or boot-time XOVI autostart.

# 3.0.1 — 2026-10-18

Source-first distribution and detailed manual SSH installation guides. All seven apps retained. Existing Care versions can update directly to this three-part version. Graphical installer sources and historical artifacts remain available in the project.

# Changelog

## 3.0.0.1 — 2026-10-18

- Integrated Books and Dots into the release metadata and documentation.
- Added saved SSH connection management and per-profile RDP portrait/landscape.
- Standardised app icons, controls, typography and confirmation flows.
- Included the audited scrolling, networking, input and app-window lifecycle fixes.
- Added four-part version support to Care, the updater, installers and download routes.
- Retained a signed 3.0.0 compatibility feed for older Care clients; the current feed is `/update/stable.json`.
- Refreshed the product site and both guides while retaining aggregate download statistics.

## 3.0.0 — 2026-10-18 — Care compatibility release

- Same integrated app baseline as 3.0.0.1, with a three-part version accepted by older Care clients.
- Switches Care and the update agent to the current feed and enables four-part updates.

## 2.0.5 — 2026-10-02

- Fixed RSS full-text downloads on reMarkable's Qt network stack, including valid HTTPS responses reported without a usable status and one retry for transient failures.
- Extracted the actual article body from common page containers instead of saving site navigation, sharing controls, and related-story sections.
- Removed the duplicate article title from the reading canvas because the title is already visible in the app header.
- Added a live physical-tablet test that opens RSS with a real tap and downloads, cleans, displays, and caches a ScienceDaily article.

## 2.0.4 — 2026-10-01

- Fixed RDP double-clicks by sending the first click immediately and snapping the second click to the first click's exact remote coordinates.
- Removed the redundant synthetic click pair that could make the remote desktop receive four button transitions instead of one double-click.
- Added a focused physical-tablet double-click journey and verified the resulting press/release pair directly inside the XRDP X11 session.

## 2.0.3 — 2026-10-01

- Reduced sparse RDP update latency from 300–900 ms to 80–160 ms and dense-frame latency from 3.2–4.2 s to 0.7–0.9 s.
- Reduced unnecessary e-ink work with finer damage tiles, desktop-only dense updates, and idle-only full cleanup refreshes.
- Precomputed RDP scaling maps so frame conversion no longer performs floating-point coordinate calculations for every output pixel.
- Extended the physical RDP test to use the selected saved profile and verified double-click, long-press right-click, zoom, shortcuts, refresh soak, and clean close on a real reMarkable 2.

## 2.0.2 — 2026-10-01

- Removed the experimental PaperPet app from the release. Upgrades back up and remove an existing PaperPet installation.
- Added a standalone Windows installer.

## 2.0.1 — 2026-09-29

- Fixed Terminal's Keyboard button so it toggles the native keyboard instead of only requesting that it open.
- The button now says Hide keyboard while the keyboard is visible and returns focus to the terminal after hiding it.
- Added a robust keyboard inset fallback so the prompt remains visible when reMarkable reports an empty input-method rectangle.
- Extended the physical Terminal journey to verify a complete hide/show cycle.

## 2.0.0 — 2026-09-29

- Removed PaperWeb's private download worker and Downloads screen because reMarkable has no system download manager.
- File responses are now refused cleanly instead of being saved in a hidden Linux directory or destabilising Xochitl.
- Added an icon-only Reload action immediately to the left of the address field.
- Terminal now opens the system keyboard automatically after its window gains focus.
- Added an opt-in Terminal mouse mode for mouse-aware text applications: tap sends left click and hold sends right click without continuous pointer traffic.
- Added complete RDP profile management: create, edit, save, connect, and confirmed delete.
- Removed the unused RSS Favourite action and reclaimed its header space for article titles.
- Reworked RDP profile usability with a vertical list, New/Edit/Delete, Cancel during editing, and a single Connect action.
- Added a Remember password control. It defaults to on for new profiles and keeps the password out of the profile file when disabled.
- RDP profile changes use an atomic, root-only background helper without creating an AppLoad window.
- Removed Terminal's saved SSH profiles and Advanced flow, leaving one simple New connection action.
- Removed unsupported OpenSSH-only connection flags that Dropbear printed as warnings.

## 1.2.3 — 2026-09-29

- Moved PaperWeb downloads out of AppLoad and Xochitl into an isolated systemd worker.
- Fixed a reproducible Xochitl segmentation fault when two file links were downloaded in quick succession.
- Added unit tests for repeated downloads, safe duplicate names, and rejected local-file URLs.
- The physical-tablet test now downloads two real files in sequence and verifies that Xochitl keeps the same process.

## 1.2.2 — 2026-09-28

- PaperWeb downloads a linked file when the user taps its link.
- Removed the misleading toolbar action that saved the currently displayed page.
- Added direct recognition of SVG, GIF, and WebP file links.
- Replaced the old toolbar test with a physical-tablet test that taps a real file link and verifies the saved file.

## 1.2.1 — 2026-09-28

- RSS automatically downloads full article text when an article is opened.
- Cached full text opens immediately offline and survives later feed refreshes.
- The feed copy remains visible when a full page cannot be downloaded.
- Removed the redundant manual Full text / Stop action from the article header.

## 1.2.0 — 2026-09-28

- Added a touch-first list of up to eight recent RDP connection profiles.
- Each RDP profile remembers 50%, 75%, or 100% session scale and 256, 65K, or 16M colours.
- Lower scale presets negotiate a smaller remote desktop and fit it to the full tablet screen, reducing remote pixels by up to 75%.
- RDP disables wallpaper, animation, themes, font smoothing, and desktop composition to reduce unnecessary e-ink and network work.
- Mouse, double-click, right-click, pan, and pinch coordinates now follow the negotiated remote resolution.

## 1.1.9 — 2026-09-28

- Removed PaperDesk's automatic XOVI startup during boot to preserve a stock-UI recovery path on reMarkable 2.
- Existing installations remove only PaperDesk's known legacy systemd unit during update.
- Signed updates use a one-shot transient reload and do not create boot persistence.
- Documented deliberate SSH or xovi-tripletap startup after a reboot.

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
