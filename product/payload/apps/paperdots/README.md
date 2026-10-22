# PaperDesk Dots

An offline game of Kropki for reMarkable 2 / XOVI AppLoad. All computation is
local. The computer's search yields between small batches to keep input and
the tablet watchdog responsive. Canvas repaints only when the position or
layout changes; there are no animations or network requests.

## Play

Tap an empty intersection. Player 1's dots are filled, Player 2's hollow. A ring
marks the last move; crosses identify captured dots. Closed bases are drawn
automatically. The score counts captured opponent dots; recapturing a base
releases friendly dots inside it.

New game offers 15 × 19, 19 × 23, or 29 × 33 intersections. The largest board
uses 5 mm squares fullscreen on reMarkable 2 (226 ppi, 44.49 px pitch). Each
player has an independent Human / Computer dropdown, supporting hot-seat play,
either human/computer order and computer/computer simulations. The shared AI
level can be Relaxed or Tactical. The score and leader are always visible.

With one human, Undo turn reverses that player's last move and its reply.
With two humans or computers, Undo move reverses one move. Undo pauses a
simulation or an undone computer opening so it is not immediately repeated.
Pause / Resume is available whenever a computer is playing. Simulations have
a short delay between turns and stop immediately on Close. Close saves the
position, players and pause state. Old version-1 saves retain their moves and
default to Human / Computer. There is no in-app rules screen or Finish action;
the game ends naturally when no legal intersections remain.

Rules reference: https://pl.wikipedia.org/wiki/Kropki_(gra). This implements
one-square connections (including diagonals), no empty bases, no edge-assisted
captures, no moves inside bases, and no use of captured dots to build a base.
Scoring variant: one point per currently captured opposing dot. No two-square
variant or network multiplayer mode is included.

## Files and verification

`game.js` contains the rules, replay validation and bounded heuristic AI.
`ui/main.qml` uses the common PaperDesk action style. `application.qrc` embeds
both files. Saved state is a versioned, validated move list in QSettings group
`PaperDeskDots`; malformed data starts a fresh game. User data is retained on
uninstall.

Run `node tests/paperdots-engine.cjs` from the repository root for capture,
nested-base, edge, AI, undo and save tests. `tests/run-ui-tests.sh` additionally
exercises the visible controls. `PAPERDESK_E2E_TARGET=dots tests/run-tablet-e2e.sh`
exercises physical touch input, both dropdowns, all board sizes and player
assignments, pause/resume, undo, close and saved-mode restoration.
The hardware test keeps screen capture off by default. Qt scene capture via
`grabToImage` caused a reproducible xochitl crash on the tested firmware; use
the local QtTest render for visual inspection instead. The hardware journey
checks actual evdev input and persisted state without that capture path.
