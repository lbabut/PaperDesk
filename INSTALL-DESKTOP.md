# PaperDesk installer for Linux

Connect the reMarkable 2 over USB and enable its USB web interface.
Run `./PaperDesk-Installer.sh` from the unpacked installer folder.
Enter the tablet address (normally `10.11.99.1`) and the USB management
code from tablet settings. This is a device access code, not a licence key:
PaperDesk is free and open source.

The installer uses Zenity dialogs. It checks the package hashes and the
tablet's SSH fingerprint, verifies XOVI, AppLoad and the resource rebuilder,
then shows the app IDs already present. Click Install to continue. Matching
IDs are backed up and replaced; other AppLoad applications are untouched.
On a first PaperDesk install, the tablet keeps a separate copy of the
original app IDs and restores those originals on uninstall. Profiles and
settings remain on the tablet. Earlier PaperDesk installations may not
have that original snapshot, so preserve their existing backups.

The code stays in process memory. It is not copied to the tablet or stored
in the installer package. The old command-line installer in
`product/install-from-computer.sh` remains available.

## Make the Linux bundle

Run `./scripts/build-linux-installer.sh` from the repository. It creates
`dist/paperdesk-linux-installer-1.1.4.tar.gz` and a SHA-256 file.
Extract the bundle, then launch `PaperDesk-Installer.sh`.
Zenity, OpenSSH, GNU coreutils and tar are required on the Linux computer.

Version 1.1.4 is an installation candidate. The installer has been checked
for shell syntax and package integrity; a clean physical tablet installation
and removal still need verification before public distribution.
