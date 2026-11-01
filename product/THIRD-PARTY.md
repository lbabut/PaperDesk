# Third-party components

PaperDesk integrates with open-source software in the XOVI environment.
The release contains or uses:

- **FreeRDP 3** — Apache License 2.0. The PaperRDP client is built with
  FreeRDP libraries; the licence text is in
  `licenses/FreeRDP-Apache-2.0.txt`.
- **Paper Terminal frontend ancestry** — the inherited QML frontend retains
  its LiTerm GNU GPL v2 notice in `licenses/LiTerm-GPL-2.0.txt`. The PTY,
  VT parser and terminal renderer are original PaperDesk code. No LiTerm
  runtime or global extension is required.
- **AppLoad and QTFB shim** — GNU GPL v3. The licence text and bundled
  shim source are included in the package.
- **Qt** — libraries supplied by reMarkable OS and XOVI; they are not
  redistributed in this package.

reMarkable, XOVI, AppLoad, LiTerm, Qt, and FreeRDP are names of their
respective owners. PaperDesk is not an official reMarkable AS product.
