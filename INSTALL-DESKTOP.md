# PaperDesk desktop installer

The existing installation instructions are in [product/README.md](product/README.md).
The desktop installer offers the same USB installation from Linux and Windows.
The code requested by the installer is the tablet's **USB management code**,
not a PaperDesk licence key. PaperDesk is free and open source.

## Use

Connect a reMarkable 2 over USB, enable its USB web interface and note the
management code in the tablet settings. Start the installer, enter the code,
choose **Check tablet**, review the apps it finds, then choose **Install**.
The default tablet address is 10.11.99.1. On first connection, compare and
accept the tablet's SSH key fingerprint. A changed saved key stops connection.

The installer checks XOVI, AppLoad and the resource rebuilder. It verifies
the bundled payload hashes before sending anything to the tablet. It only
replaces PaperDesk's eight named app IDs, including the modified LiTerm
frontend and internal components. Other AppLoad apps remain in place.
Existing IDs appear in a confirmation dialog before installation.

On a first PaperDesk install, the tablet-side installer records an original
copy of replaced app IDs, resources and service files. Regular upgrade backups
remain separate. Uninstall restores original app IDs when that original
snapshot exists. App settings and connection profiles remain on the tablet.
Older PaperDesk installations may lack an original snapshot; their pre-existing
LiTerm installation cannot be reliably reconstructed by this new installer.
Back up the tablet before migrating an older installation.

The USB code is held in memory and is never written to a configuration file
or copied into the release payload. The earlier command-line installer remains
available in product/install-from-computer.sh.

## Build

Build separately on each operating system using Python 3.10 or newer:

    python -m venv .venv
    .venv/bin/python -m pip install -r desktop-requirements.txt
    .venv/bin/pyinstaller --onefile --windowed --name PaperDesk-Installer \
      --add-data "product:product" desktop-installer.py

On Windows, replace the last two commands with:

    .venv\Scripts\python -m pip install -r desktop-requirements.txt
    .venv\Scripts\pyinstaller --onefile --windowed --name PaperDesk-Installer ^
      --add-data "product;product" desktop-installer.py

On Linux install the OS package providing tkinter (often python3-tk).
PyInstaller creates dist/PaperDesk-Installer or dist/PaperDesk-Installer.exe.
Build on Windows for Windows; a Linux build does not produce a Windows EXE.
The binary includes the local product/ tree, so rebuild it after a product
release changes. The UI and binary still need tests on both host systems and
a clean physical tablet before public distribution.
