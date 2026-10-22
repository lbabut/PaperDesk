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
  The firmware keyboard keeps its native portrait layout; while it is open,
  the RDP toolbar moves to the physical top so Hide keyboard and Close remain
  reachable. Hiding it restores the landscape toolbar.
- No audio, animation, or device channels.
- Up to eight recent server profiles, including their performance settings,
  are stored locally in root-only files (mode `0600`). Passwords are
  obfuscated as hexadecimal bytes, not encrypted.
- Profiles have explicit Open, Add, Edit, Save, and confirmed Delete actions.
- Remember password is enabled for new profiles by default and can be disabled
  so the password is used only in memory for the current app session.
- 100–300% zoom and two-finger panning.
- Server certificates use trust on first use. The first certificate is stored
  by FreeRDP; a changed certificate blocks the connection. Verify the server
  identity on a trusted network before first use. Do not remove a stored
  certificate merely to bypass a warning; first verify the change with the
  server administrator.
