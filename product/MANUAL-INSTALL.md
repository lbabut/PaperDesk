# PaperDesk 4.2.11 — manual SSH installation

Source + prepared ARM tablet files, not a from-scratch build or a Windows EXE.
Browse sources at <https://github.com/lbabut/PaperDesk>. Download the project
package below for the prepared ARM files.
Read the complete illustrated English or Polish guide on the project website.

## Before installing

Back up/sync notebooks, close apps and connect a USB data cable. The suite baseline is
reMarkable 2 / OS 3.29.0.149; Sketch is also validated on OS 3.29.0.153. XOVI 0.3.3, AppLoad 0.6.0,
qt-resource-rebuilder must already work. This procedure does not
install dependencies. Stop if firmware or dependencies differ. The v4 installer
accepts only OS 3.29.0.149 or 3.29.0.153 / ARMv7 because Sketch installs a native Qt material
renderer in XOVI. It does not enable the optional legacy pen-preview extension.
Use OpenSSH, scp and tar on Windows PowerShell, Linux or macOS. Keep Windows
protection enabled. Enter the USB management code only in SSH password prompts.
Verify the tablet host-key fingerprint independently; stop on unexpected changes.

## Download and verify

Linux commands (macOS: use shasum -a 256 -c instead of sha256sum -c):

```sh
curl -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-4.2.11.tar.gz
curl -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-4.2.11.tar.gz.sha256
sha256sum -c paperdesk-sources-4.2.11.tar.gz.sha256
# macOS: shasum -a 256 -c paperdesk-sources-4.2.11.tar.gz.sha256
```

Windows PowerShell: compare the entire SHA-256 in the two outputs:

```powershell
curl.exe -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-4.2.11.tar.gz
curl.exe -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-4.2.11.tar.gz.sha256
Get-FileHash .\paperdesk-sources-4.2.11.tar.gz -Algorithm SHA256
Get-Content .\paperdesk-sources-4.2.11.tar.gz.sha256
```

Stop on any mismatch. A checksum is not publisher authentication.

## Extract, inspect and check prerequisites

All subsequent commands work in PowerShell and Linux/macOS terminals.

```sh
tar -xzf paperdesk-sources-4.2.11.tar.gz
cd paperdesk-sources-4.2.11
ssh root@10.11.99.1 'uname -m; cat /etc/os-release; df -h /home/root'
ssh root@10.11.99.1 'test -x /home/root/xovi/start && test -d /home/root/xovi/exthome/appload && test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so && echo READY'
```

Expect armv7l, IMG_VERSION 3.29.0.149 or 3.29.0.153 and READY. Allow free space for the archive,
extracted files and existing-app backups. Inspect product/install.sh and
product/uninstall.sh before running them.

## Transfer and verify on the tablet

```sh
ssh root@10.11.99.1 'test ! -e /home/root/paperdesk-install-4.2.11 && mkdir -m 700 /home/root/paperdesk-install-4.2.11'
tar --exclude=paperdesk.local.conf -czf paperdesk-tablet-4.2.11.tar.gz -C product .
scp paperdesk-tablet-4.2.11.tar.gz root@10.11.99.1:/home/root/paperdesk-install-4.2.11/
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-4.2.11 && tar -xzf paperdesk-tablet-4.2.11.tar.gz && sha256sum -c SHA256SUMS'
```

Stop if the staging directory already exists; inspect the earlier attempt.
Every inner checksum must say OK. Do not proceed after an error.

## Install, start and verify

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-4.2.11 && sh ./install.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version'
```

Run each command only after the preceding command succeeds. Expect version
4.2.11. Open and close Sketch, SSH, Web, RDP, RSS, Books, Dots and Care. Verify notebooks
remain accessible. Backups and app data stay in /home/root/.local/share/paperdesk
and the apps' settings/data directories. Sketch artwork stays in
/home/root/.local/share/paperdesk/sketch; PNG exports stay in Documents. Save
unsaved drawings before installing. Keep these directories.
XOVI is NOT injected at boot. After a reboot start /home/root/xovi/start manually.
Unofficial modifications can require recovery; on RM2 this can require a pogo-pin
adapter. A backup cannot guarantee recovery.

## Check the new Sketch controls

After opening Sketch, open Materials using the first icon in the middle
toolbar, before the 2H pencil. Try a tilted mark, the pressure calibration controls,
each paper preset, Sharpen, Clean finger, and hard/kneaded erasers. Kneaded
lifting responds to pressure and movement, with a bounded effect per contact:
lift and dab again for another layer. The hard eraser rubs along the path. Missing tilt data falls back to an upright tip. Calibration changes
digital stylus response and does not claim a physical-pencil match.
With a pencil selected, touch and lift without moving to check a dot, then draw
a continuous line. Strokes start at initial pen contact; the
physical e-ink refresh remains separate from software input processing.

Save before updating and back up the entire existing sketchbook directory.
4.1 reads older material pages without repainting their optical pixels; its
first explicit Save writes v2 material state, including paper, burnishing and
wear. Keep the pre-upgrade sketchbook if you need to return to 4.0, whose reader
does not understand v2 material pages. The older package alone cannot downgrade
a new sketchbook. Earlier release archive URLs remain available and unchanged.

Pressure calibration uses its own practice pad and three stages: light, normal
and comfortably firm lines. Next becomes available after enough samples; Save
response commits a valid profile. Cancel preserves the prior profile and your
artwork. Calibration adjusts digital input, not a measured physical pencil.

## Remove

Use Care → Remove PaperDesk, or:

```sh
ssh root@10.11.99.1 'sh /home/root/paperdesk-install-4.2.11/uninstall.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

Apps and the bundled native Sketch renderer are removed; saved data and backups
remain. A renderer or Sketch app present before the first v4 installation is
restored from the original snapshot. Restoration cannot recreate an
original LiTerm that an older installation never backed up.
