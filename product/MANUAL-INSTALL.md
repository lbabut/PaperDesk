# PaperDesk Apps — manual installation on reMarkable 2

These instructions cover manual installation of PaperDesk 1.2.3 from a Linux
computer over USB and SSH. The graphical installer is not required.

## 1. Prepare the tablet and computer

- Use a reMarkable 2 running reMarkable OS 3.29.x. The previously tested setup
  was OS 3.29.0.149, XOVI 0.3.3, rm-xovi-extensions v19, AppLoad 0.6.0,
  and LiTerm 0.1.7.
- XOVI, AppLoad, LiTerm, and the qt-resource-rebuilder extension must already
  work. PaperDesk does not install these prerequisites.
- Connect the tablet by USB. Enable its USB web interface in tablet settings
  and note the USB management code. This is the SSH password, not a licence key.
- The computer needs ssh, tar, gzip, and sha256sum.
- Close the tablet apps and save open documents. Restarting XOVI at the end
  will close running apps.

The default tablet address is `10.11.99.1`. If yours differs, substitute it
in every command below. On the first SSH connection, verify the host key
fingerprint before accepting it. If a previously saved host key changes
unexpectedly, stop the installation.

## 2. Extract and verify the package

In the directory containing the downloaded archive:

```sh
sha256sum paperdesk-linux-installer-1.2.3.tar.gz
tar -xzf paperdesk-linux-installer-1.2.3.tar.gz
cd paperdesk-linux-installer-1.2.3/product
sha256sum -c SHA256SUMS
```

Compare the archive's SHA-256 with the checksum published alongside the
download. The last command must report `OK` for every file. Stop if any
checksum differs.

## 3. Check prerequisites on the tablet

```sh
ssh root@10.11.99.1 'test -d /home/root/xovi &&
  test -d /home/root/xovi/exthome/appload &&
  test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so &&
  echo "XOVI, AppLoad and qt-resource-rebuilder: OK"'
```

SSH will ask for the USB management code. If `OK` does not appear, the tablet
is not ready. After a firmware update, XOVI may need a symbol-table rebuild
for that exact OS version. Do not install PaperDesk while XOVI is broken.

Check the currently installed app IDs:

```sh
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version 2>/dev/null || true
  for app in paperdesk literm paperweb paperrdp-login paperrdp paperrss papercare shims; do
    test -e "/home/root/xovi/exthome/appload/$app" && echo "$app"
  done
  true'
```

PaperDesk replaces only those AppLoad IDs. Other apps stay on the tablet.
On a first installation, originals of replaced directories are
saved in `/home/root/.local/share/paperdesk/original`. If you are upgrading
an older PaperDesk installation without `original-recorded`, keep its
earlier backups. The new installer cannot reconstruct the original LiTerm
from an already modified directory.

## 4. Copy the files

From the `product` directory entered in step 2:

```sh
ssh root@10.11.99.1 'mkdir -p /home/root/paperdesk-install-manual'
tar --exclude='./paperdesk.local.conf' -cf - . |
  ssh root@10.11.99.1 'tar -xf - -C /home/root/paperdesk-install-manual'
```

This excludes any local file containing the USB code. Do not put the code
in a command or copy it to the tablet. Verify the transferred files:

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-manual &&
  sha256sum -c SHA256SUMS'
```

## 5. Install and restart XOVI

```sh
ssh root@10.11.99.1 'cd /home/root/paperdesk-install-manual &&
  sh ./install.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

The first command should end with a completion message. The installer backs
up the previous state before replacing modules. After XOVI restarts, open
AppLoad on the tablet. Terminal, Web, RDP, RSS, and Care should appear.
Confirm that other apps remain visible, then open all five PaperDesk modules.

Check the installed version, update watcher, and absence of PaperDesk's old
boot-time XOVI service:

```sh
ssh root@10.11.99.1 'cat /home/root/.local/share/paperdesk/current-version;
  systemctl is-enabled xovi-autostart.service 2>/dev/null || true;
  systemctl is-enabled paperdesk-update.path;
  systemctl is-enabled paperdesk-download.path'
```

The version should be `1.2.3`; `xovi-autostart.service` should report
`disabled` or `not-found`, while both PaperDesk path units should report `enabled`.
Connection profiles remain in user data directories on the tablet.

## Uninstall and return to the previous state

Close the apps first. Keep `/home/root/.local/share/paperdesk`: it holds the
backups. If the directory copied in step 4 is still present:

```sh
ssh root@10.11.99.1 'sh /home/root/paperdesk-install-manual/uninstall.sh'
ssh root@10.11.99.1 '/home/root/xovi/start'
```

The uninstaller restores apps that existed before the first PaperDesk install
and have an original snapshot. Connection data and backups remain. If an
older PaperDesk installation has no `original-recorded` file, do not assume
that uninstall will restore stock LiTerm; use a saved copy or the
appropriate LiTerm installer.

To return to an earlier PaperDesk version without uninstalling the suite,
install its complete, verified archive again. Do not copy selected files
from `backups`: the release also changes AppLoad resources and services.
