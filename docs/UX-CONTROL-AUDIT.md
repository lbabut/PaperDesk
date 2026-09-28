# PaperDesk control audit

Date: 2026-09-27  
Target: reMarkable 2, OS 3.29.0.149, AppLoad 0.6.0, XOVI 0.3.3

This audit treats tablet space, e-ink refreshes, and attention as scarce resources. A control stays only when it supports a primary task, makes an otherwise inaccessible key available, or provides a reliable escape/recovery path.

## Hub

| Control | Keep? | User purpose | Explain publicly? |
| --- | --- | --- | --- |
| Terminal | Yes | Start an SSH or local recovery session | Yes; core product tool |
| Web reader | Yes | Read a web page in an e-ink-safe layout | Yes; core product tool |
| Remote desktop | Yes | Connect to an RDP computer | Yes; core product tool |
| RSS reader | Yes | Read cached RSS/Atom feeds | Yes; core product tool |
| Menu | Yes | Return to AppLoad/system navigation | No; expected navigation |

Decision: no separate PaperDesk launcher inside the hub. The five AppLoad applications are the product navigation.

## Terminal

| Control | Keep? | User purpose | Explain publicly? |
| --- | --- | --- | --- |
| Close | Yes | Guaranteed exit from the terminal | No; utility action |
| Keyboard | Yes | Explicit recovery when the system keyboard is hidden | Briefly; contextual system keyboard matters |
| Shortcuts | Yes | Reveal terminal-only keys without a permanent second keyboard | Yes; differentiating usability feature |
| Ctrl+C / Ctrl+D / Ctrl+Z / Ctrl+L | Yes | Interrupt, EOF/logout, suspend, clear | As a group, not one by one |
| Tab / Esc / arrows | Yes | Completion, mode escape, history/cursor navigation | As a group |
| Menu | Yes | AppLoad navigation and keyboard access | No |

Decision: keep the shortcut row collapsible. A permanent row would reduce terminal height; hiding these keys completely would make real shell work impractical.

## Web reader

| Control | Keep? | User purpose | Explain publicly? |
| --- | --- | --- | --- |
| Close | Yes | Reliable exit | No |
| Back arrow | Yes | Browser history without wasting space on a text label | No; familiar convention |
| Address field | Yes | Direct navigation; selects all text on focus | Yes, in documentation |
| Go / Stop | Yes | Start or cancel a request in the same location | No |
| Use Mobile / Use Computer | Yes | Choose compact extraction or desktop request profile | Yes; explain what changes |
| Show / Hide Pictures | Yes | Trade bandwidth and refresh cost for context | Yes; meaningful e-ink choice |
| Zoom − / + | Yes | Precise fallback to pinch zoom | Briefly; accessibility |
| Pinch and drag | Yes | Natural zoom and scroll | Yes; central interaction |
| Permanent keyboard | No | It obscures reading and duplicates AppLoad input | Yes; absence is intentional |
| Home | No | Duplicated address navigation and caused toolbar clutter | No |

Decision: the browser keyboard appears only when editing the address. Mobile remains the default, while Computer is an explicit per-page escape hatch.

## RDP

| Control | Keep? | User purpose | Explain publicly? |
| --- | --- | --- | --- |
| Server / user / password | Yes | Required connection credentials | Explain local profile storage |
| Port | Yes | Support non-default RDP endpoints | Documentation only; advanced field |
| Saved profiles | Yes | Switch between recent computers without retyping credentials | Explain local-only storage |
| Scale | Yes | Lower the negotiated desktop resolution for faster rendering | Yes; recommend 75% on rM2 |
| Colors | Yes | Reduce RDP colour depth and bandwidth | Yes; recommend 256 colours on e-ink |
| Connect | Yes | Primary login action | No |
| Keyboard | Yes | Recover or summon native AppLoad input | Yes; key usability feature |
| Close | Yes | Always-visible escape from login/session/error states | No |
| Shortcuts | Yes | Send combinations an on-screen keyboard cannot express | Yes; as one feature |
| Ctrl+C/V/X/A | Yes | Standard remote editing operations | As a group |
| Alt+Tab / Ctrl+Alt+Del / Win | Yes | Remote window and session management | As a group, with remote-target note |
| Esc / Tab | Yes | Dialog and focus navigation | As a group |
| Pan / pinch | Yes | Move around and resize a desktop larger than the tablet | Yes |
| Back in shortcut/error views | Yes | Return without dropping the session | No |

Decision: keep the connected-session chrome to two primary buttons: Shortcuts and Close. Keyboard access remains in the AppLoad pull-down because drawing a second keyboard caused duplication and stale overlays. Connection profiles retain their own Scale and Colors choices; lower values reduce remote pixels and bandwidth without changing the monochrome panel output.

## RSS

| Control | Keep? | User purpose | Explain publicly? |
| --- | --- | --- | --- |
| Refresh / Stop | Yes | Update feeds or cancel network work in the same location | Briefly |
| Add feed | Yes | Add any RSS/Atom source | Yes |
| Close | Yes | Reliable exit | No |
| All articles | Yes | Clear source filtering | No |
| Source row | Yes | Filter the reading list | No |
| Remove | Yes, guarded | Manage stale sources | Documentation only |
| Article card | Yes | Open and mark an article read | No |
| Articles | Yes | Return from reader to list | No |
| Favourite | Yes | Maintain a local reading shortlist | Yes |
| Full text / Stop | Yes | Fetch an article body or cancel the request | Yes |
| Cancel / Add feed | Yes | Complete or abandon feed creation | No |
| Pinch and scroll | Yes | Read long cached text comfortably | Yes |

Decision: replace the cryptic `×` with `Remove` and require a second `Sure?` tap within three seconds. Destructive feed management remains available without making a stray touch costly.

## Cross-product rules

1. Close is large and stable in every application state.
2. Menu is centered by AppLoad and is not duplicated inside content.
3. Keyboards are contextual; PaperDesk never draws a competing full keyboard.
4. Secondary keyboard combinations live in one collapsible Shortcuts surface.
5. Network actions reuse their button as Stop to avoid layout movement.
6. Every touch target is exercised in QML tests; primary journeys are repeated with injected hardware touch events on a physical tablet.
7. Marketing describes outcomes—working in a shell, reading a page, controlling a desktop, building a reading queue—not every utility button.
