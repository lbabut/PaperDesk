# PaperDesk source snapshot

## 4.2.0 — 2026-11-01

This tree contains the complete source and prepared ARM payload of the published
PaperDesk 4.2.0 release: the independent Paper Terminal, RDP usability changes,
all eight apps, installers, tests, website and release documentation. Paper Sketch
app files remain identical to the released 4.1.3 payload.

The release was assembled from verified public 4.1.3 sources and the tested
Terminal/RDP changes, preserving GitHub history and existing deployment guidance.
Validation: 149 Python tests (2 skipped), 265 QML tests (2 skipped), 10 disposable
filesystem installer cases, and real AppLoad Terminal/RDP checks on reMarkable 2
with OS 3.29.0.153. See docs/release-4.2.0-audit.json for scope and limits.

Signed updates and the complete installable project package are available at
<https://paperdesk.lukaszbabut.info/>. Archive checksums are retained in dist/.
The product checksums cover the exact prepared tablet payload. This is not a
complete cross-compilation SDK.

Local build caches, release archives, service databases, SSH keys, signing keys,
credentials, private operations reports and host-specific runtime state are
excluded. Original working trees and their uncommitted changes remain untouched.
