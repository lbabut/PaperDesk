# PaperDesk 1.2.0

PaperDesk turns a reMarkable 2 into a quiet, monochrome network workspace.
The bundle adds five apps directly to the AppLoad list and keeps their
settings between sessions. The redundant hub and technical RDP worker are
hidden from users.

## Apps

- **SSH Terminal** — native keyboard, scrolling, resize gesture, Ctrl
  shortcuts, and readable black text.
- **Web Reader** — simplified pages without scripts, a remembered setting
  for showing or hiding pictures, compact cards with titles above images,
  pinch zoom, and e-ink scrolling without animation.
- **Remote Desktop** — FreeRDP, touch, keyboard, zoom, panning, recent
  profiles, and per-profile resolution and colour-depth presets.
- **RSS Reader** — RSS/Atom feeds, custom sources, favourites, read articles,
  full text, and an offline cache.
- **PaperDesk Care** — installed and available versions, release notes, and
  updates from signed, verified packages.

PaperDesk does not refresh anything automatically in the background.
The network and display are used only when requested, reducing flashing
and battery use.

The interface shares a monochrome visual system: editorial typography,
large touch targets, thin borders, and a calm layout without animation.
Web pages are also normalised to black and white; long articles retain
light, readable typography instead of being permanently bold.

The package includes an AppLoad 0.6.0 compatibility patch. When closing
a module, it detaches the keyboard before destroying the window, safely
handles an unloaded frontend, and emits the close signal only once. This
prevents an invisible layer with an X button from blocking touch input.
It also handles the newer AppLoad 0.6.0 screen-aspect reporting.

## Requirements

- reMarkable 2 running reMarkable OS 3.29.x (tested on 3.29.0.149);
- XOVI 0.3.3;
- rm-xovi-extensions v19;
- AppLoad 0.6.0;
- LiTerm 0.1.7.

This is the tested configuration. Other versions may work, but are not
covered by this release.

After a firmware update, XOVI needs a symbol table rebuilt for the exact
OS version. On the tested device, this was done with
`/home/root/xovi/rebuild_hashtable` before starting PaperDesk.

## Install from a computer

The graphical Linux installer is described in `../INSTALL-DESKTOP.md`.
It detects existing apps before installation and asks for confirmation
before replacing matching IDs. Detailed USB/SSH instructions, verification,
and removal steps are in `MANUAL-INSTALL.md`.

Connect the tablet by USB, extract the package, and run:

```sh
cp paperdesk.conf.example paperdesk.local.conf
chmod 600 paperdesk.local.conf
```

Enter only the USB management code from tablet settings in
`paperdesk.local.conf`, then run:

```sh
./install-from-computer.sh
```

The default address is `10.11.99.1`. Pass another address as an argument:

```sh
./install-from-computer.sh 192.168.1.50
```

The tablet-side installer saves previous versions under
`/home/root/.local/share/paperdesk/backups`, preserves connection
profiles, and does not delete user data. The computer installer restarts
XOVI so AppLoad does not use stale resources. For recovery safety on rM2,
PaperDesk deliberately does not start XOVI during boot. After a reboot, run
`/home/root/xovi/start` over SSH or use the community `xovi-tripletap` tool.

## Install directly on the tablet

Copy the directory to the tablet and run `./install.sh` as root, then
`/home/root/xovi/start`. Restarting XOVI closes open apps, so save any
work on the tablet first. See `MANUAL-INSTALL.md` for the complete procedure.

## Privacy and security

- Terminal verifies SSH host keys and does not save passwords.
- PaperRDP stores up to eight recent profiles in a root-owned directory with
  mode `0600`. Saved passwords are locally obfuscated, not encrypted.
- RSS stores feeds and articles locally in xochitl settings.
- When pictures are enabled, PaperWeb sends their public URLs to
  `images.weserv.nl` to work around the tablet libraries' outdated TLS,
  limit images to 760 px, and remove animation. It does not send cookies
  or login details there.
- PaperDesk has no telemetry or external account.
- PaperDesk Care pins the release public key and verifies the Ed25519
  signature, ZIP SHA-256, and internal file hashes before installation.
- The USB management code stays in the Git-ignored local file
  `paperdesk.local.conf`. It is not copied to the tablet or placed in
  process arguments.

## Uninstall

`./uninstall.sh` removes PaperDesk apps and restores original AppLoad
resources when available. The installer also saves original app
directories on a first install and restores them on uninstall. Connection
data and backups are deliberately retained. Restart XOVI afterwards.
Older installations without the original snapshot may need a separately
saved copy of LiTerm; see `MANUAL-INSTALL.md`.

## Component licences

The package contains licence texts for LiTerm, AppLoad/QTFB, and FreeRDP
under `licenses`. The bundled QTFB shim source is in
`third_party_source`. PaperDesk application code, the AppLoad QML
compatibility patch, and the PaperRDP client are shipped in the package.

## Release status

Release 1.2.0 was tested on a physical reMarkable 2 with OS 3.29.0.149:
all module launches and safe menu actions, system keyboard, persistent
settings, RSS refresh and full-text retrieval, AppLoad window cleanup,
physical scroll and pinch gestures, and scaled RDP sessions.
