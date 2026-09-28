# PaperRDP

A minimal RDP client for reMarkable 2, based on FreeRDP 3 and QTFB/AppLoad.

- Selectable 50%, 75%, or 100% remote resolution, fitted to the panel.
- Selectable 256, 65K, or 16M colour sessions; the final panel output remains monochrome.
- Monochrome RGB565 conversion.
- An always-available Close control.
- The system on-screen keyboard.
- No audio, animation, or device channels.
- Up to eight recent server profiles, including their performance settings,
  are stored locally in root-only files (mode `0600`). Passwords are
  obfuscated as hexadecimal bytes, not encrypted.
- 100–300% zoom and two-finger panning.
