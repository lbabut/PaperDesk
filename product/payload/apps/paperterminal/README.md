# Paper Terminal

PaperDesk's SSH terminal for reMarkable. The original C++ backend opens a
Linux PTY, renders a bounded VT screen and uses the system SSH client
(Dropbear on the tested tablet).
LiTerm is not required. The QML frontend keeps its existing GPL-2.0 ancestry;
the new native sources carry MIT SPDX notices.

The app-local QML plugin is loaded on demand from `native/`, including when
AppLoad opens the frontend from its registered RCC resource. No terminal
extension is loaded into xochitl at boot. Rebuild the native ARM plugin with
`python3 scripts/build-terminal.py` from the repository root, then compile
`application.qrc` with the normal resource compiler and update product hashes.

Output is coalesced to at most one frame every 90 ms, repaints changed rows,
uses a static cursor and AppLoad's Fast display method, and runs no periodic
idle refresh. Input is sent immediately without waiting for a display frame.
History is limited to 2000 lines and 262144 cells; geometry, parser buffers,
status replies, reads and queued writes are bounded. Mouse mode starts on:
tap for left click and hold for right click in programs that enable mouse
reports. Turn Mouse off to scroll with a finger; pinch to resize text.
Shift+PageUp/PageDown also scroll history.

Shortcuts has Keys and F1–F12 tabs. Tap Ctrl or Alt to arm the next key;
hold it for about 700 ms to lock it for several keys. Tap an armed or locked
modifier again to turn it off. Ctrl and Alt can be combined. The header keeps
their state visible when the panel is closed. Modifiers reset when returning
to the local menu, changing connections, opening Sessions or leaving the app.
Shortcuts preserve the chosen keyboard visibility. Turn off modifiers before
pasting text: a multi-character commit with Ctrl or Alt armed is rejected and
clears those modifiers, rather than changing the whole text into key chords.

The core supports streaming UTF-8, ANSI colours rendered as monochrome or four
gray levels, inverse selections, cursor/edit/erase controls, scroll margins,
alternate screens, common function keys and negotiated mouse reports. This
is a compact VT implementation: combining marks and emoji grapheme sequences
are not fully composed, and resize preserves existing cells without reflow.
Very large REP counts are truncated to 240 cells to bound UI work.

Saved connections retain the existing `PaperDeskSSH` QSettings category.
The start screen lists those same profiles in order, numbered from 1, with
their name and SSH address. Tap a row to connect, or type its number and press
Enter. The list scrolls when needed and updates after adding, editing or
deleting a profile in Sessions. Its New connection and Local shell actions
remain available alongside the saved profiles. The start screen is shown only
at the verified local launcher menu; input for it never reaches a remote shell.
In Sessions, one tap selects a saved profile; double-click or double-tap opens
that profile through the same action as Open, including the busy-session
confirmation when another terminal session is active.

Remember password is optional and off for a new connection. Each profile has
its own credential ID; passwords live in private local files (directory 0700,
file 0600), without encryption. Someone with root access can read them.
Passwords never enter QSettings, command arguments or environment variables.
With OpenSSH, the app-local `native/paperterminal-askpass` helper requests a
saved password through a private local socket. The stock tablet's Dropbear
has no askpass support. For that client, a password is sent once only to its
exact local authentication prompt, in canonical mode with echo disabled,
before it enters the raw mode used by remote sessions. Automatic entry is
cancelled by any manual input or uncertain state. After manually confirming
a new host key, enter the password for that first connection; later
connections can use the saved password. Host-key confirmation always remains
interactive. Long or different password prompts require manual entry.

The backend executes SSH directly with validated arguments; it never types
connection commands into another terminal session. A private state file
identifies each local launcher. When an SSH or local-shell session is still
active, Open offers an explicit Close and connect confirmation and a way back
to the active terminal. Cancelling keeps the existing session. Confirmation
is bound to that exact process and launcher revision, so an old prompt cannot
close a different session. The new endpoint and saved password are checked
before closing the old session. Open also works from retained exit diagnostics
and during an untouched menu's startup. SSH output and exit status remain
visible until Enter returns to the menu or Open starts another saved session.
Session-picker errors stay in its visible message area, separate from runtime
terminal errors, so a rejected Open does not cover the terminal prompt.

Host tests exercise the real PTY, parser, renderer and QML plugin. Separate
ARM rendering and scripted AppLoad tests passed on reMarkable 2 / OS 3.29.0.153.
The source reports record their hashes and results. Physical touch, Type Folio
hardware input and optical ghosting were not measured by these scripts.
