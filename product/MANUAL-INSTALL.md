# PaperDesk 3.0.3 — manual SSH installation

Source + prepared ARM tablet files, not a from-scratch build or a Windows EXE.
Read the complete illustrated English or Polish guide on the project website.

## Before installing

Back up/sync notebooks, close apps and connect a USB data cable. Only the tested
reMarkable 2 / OS 3.29.0.149 configuration is covered. XOVI 0.3.3, AppLoad 0.6.0,
LiTerm 0.1.7 and qt-resource-rebuilder must already work. This procedure does not
install dependencies. Stop if firmware or dependencies differ.
Use OpenSSH, scp and tar on Windows PowerShell, Linux or macOS. Keep Windows
protection enabled. Enter the USB management code only in SSH password prompts.
Verify the tablet host-key fingerprint independently; stop on unexpected changes.

## Download and verify

Linux commands (macOS: use shasum -a 256 -c instead of sha256sum -c):

```sh
curl -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-3.0.3.tar.gz
curl -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-3.0.3.tar.gz.sha256
sha256sum -c paperdesk-sources-3.0.3.tar.gz.sha256
# macOS: shasum -a 256 -c paperdesk-sources-3.0.3.tar.gz.sha256
```

Windows PowerShell: compare the entire SHA-256 in the two outputs:

```powershell
curl.exe -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-3.0.3.tar.gz
curl.exe -fLO https://paperdesk.lukaszbabut.info/download/paperdesk-sources-3.0.3.tar.gz.sha256
Get-FileHash .\paperdesk-sources-3.0.3.tar.gz -Algorithm SHA256
Get-Content .\paperdesk-sources-3.0.3.tar.gz.sha256
```

Stop on any mismatch. A checksum is not publisher authentication.

## Extract, inspect and check prerequisites

All subsequent commands work in PowerShell and Linux/macOS terminals.

```sh
tar -xzf paperdesk-sources-3.0.3.tar.gz
cd paperdesk-sources-3.0.3
ssh root@10.11.99.1 'uname -m; cat /etc/os-release; df -h /home/root'
ssh root@10.11.99.1 'test -x /home/root/xovi/start && test -d /home/root/xovi/exthome/appload/literm && test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so && echo READY'
```

Expect armv7l, OS 3.29.0.149 and READY. Allow free space for the archive,
extracted files and existing-app backups. Inspect product/install.sh and
product/uninstall.sh before running them.

## Transfer and verify on the tablet

```sh
ssh root@10.11.99.1 'test ! -e /home/root/paperdesk-install-3.0.3 && mkdir -m 700 /home/root/paperdesk-install-3.0.3'
tar --exclude=paperdesk.local.conf -czf paperdesk-tablet-3.0.3.tar.gz -C product .
scp paperdesk-tablet-3.0.3.tar.gz root@10.11.99.1:/home/root/paperdesk-install-3.0.3/
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-3.0.3 && tar -xzf paperdesk-tablet-3.0.3.tar.gz && sha256sum -c SHA256SUMS'
```

Stop if the staging directory already exists; inspect the earlier attempt.
Every inner checksum must say OK. Do not proceed after an error.

## Install, start and verify

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-3.0.3 && sh ./install.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version'
```

Run each command only after the preceding command succeeds. Expect version
3.0.3. Open and close SSH, Web, RDP, RSS, Books, Dots and Care. Verify notebooks
remain accessible. Backups and app data stay in /home/root/.local/share/paperdesk
and the apps' settings/data directories. Keep these directories.
XOVI is NOT injected at boot. After a reboot start /home/root/xovi/start manually.
Unofficial modifications can require recovery; on RM2 this can require a pogo-pin
adapter. A backup cannot guarantee recovery.

## Remove

Use Care → Remove PaperDesk, or:

```sh
ssh root@10.11.99.1 'sh /home/root/paperdesk-install-3.0.3/uninstall.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

Apps are removed; saved data and backups remain. Restoration cannot recreate an
original LiTerm that an older installation never backed up.
