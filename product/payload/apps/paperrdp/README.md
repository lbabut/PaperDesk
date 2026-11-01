# PaperRDP

A minimal RDP client for reMarkable 2, based on FreeRDP 3 and QTFB/AppLoad.

- Selectable 50%, 75%, or 100% remote resolution, fitted to the panel.
- Selectable 256, 65K, or 16M colour sessions; the final panel output remains monochrome.
- Per-profile Portrait / Landscape. Landscape opens a real 1872×1292 desktop
  viewport (before the selected scale), with clockwise raster rotation and
  inverse-mapped pen/touch input. Turn the tablet left to read it.
- Existing v1 profiles remain Portrait; v2 profiles also retain orientation.
  No tablet-wide orientation or boot setting is changed.
- Monochrome RGB565 conversion.
- An always-available Close control.
- The system on-screen keyboard.
  The native panel follows the selected orientation; Keyboard and Close remain
  reachable in the fixed toolbar while the desktop fits above the panel.
- No audio, animation, or device channels.
- Up to eight recent server profiles, including their performance settings,
  are stored locally in root-only files (mode `0600`). Passwords are
  obfuscated as hexadecimal bytes, not encrypted.
- Profiles have explicit Open, Add, Edit, Save, and confirmed Delete actions.
- Remember password is enabled for new profiles by default and can be disabled
  so the password is used only in memory for the current app session.
- 100–300% zoom, one-finger panning when zoomed, and two-finger document
  scrolling. Moving the fingers apart pinches to zoom; the gesture keeps its
  chosen mode until release, so a pinch does not also scroll the document.
- Shortcuts has Keys, Navigation and F1–F12 pages. Navigation includes
  Home/End, Page Up/Down, arrows, Delete, Shift+Tab and Fit. Opening Shortcuts
  preserves the chosen keyboard visibility.
- With the native keyboard open, the remote desktop fits above it without
  changing its aspect ratio or the server resolution. Letterbox margins and
  the keyboard area do not send remote clicks. Hiding the keyboard restores
  the full viewport. Portrait and Landscape use the same raster/input mapping.
- The connection-error screen offers Retry using the current in-memory
  connection. A changed server certificate blocks Retry until the app closes;
  verify the change before attempting another connection.
- Save and Delete wait for a correlated helper result and the durable profile
  readback. Lock, write and stale-profile failures retain the form and the old
  list. An uncertain result requires Refresh before another change. Connect
  updates only the last connection; explicit Save owns the saved profile list.
- Server certificates use trust on first use. The first certificate is stored
  by FreeRDP; a changed certificate blocks the connection. Verify the server
  identity on a trusted network before first use. Do not remove a stored
  certificate merely to bypass a warning; first verify the change with the
  server administrator.
