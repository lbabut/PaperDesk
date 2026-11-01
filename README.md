# PaperDesk

PaperDesk turns a reMarkable 2 into a quiet, monochrome network workspace.
It bundles touch-first tools designed around the limits of e-ink:

- Paper Sketch — graphite and charcoal with stylus tilt, pressure calibration, paper presets and burnishing, virtual tip wear and sharpening, finger blending and cleaning, hard and kneaded erasers, manual saves and grayscale PNG export.
- PaperDesk SSH — SSH, system keyboard, gestures, and common shortcuts.
- PaperDesk Dots — offline Kropki with human or computer players, three board sizes, saved games and undo.
- PaperDesk Books — six free literature/textbook/research sources, offline text reading and native PDF/EPUB import, with saved language and service preferences.
- Web — static, reader-first browsing with optional images and bounded PDF/EPUB downloads to native My files.
- RDP — FreeRDP with saved profiles, performance presets, pan, zoom, and shortcuts.
- RSS — RSS/Atom feeds, full-text reading, read state, and offline cache.
- Care — signed updates, release notes, automatic verification, and rollback backups.

The current release is **4.1.1**, targeting the tested reMarkable OS
**3.29.0.149** with XOVI 0.3.3, AppLoad 0.6.0, and LiTerm 0.1.7.

The installer accepts only OS 3.29.0.149 or 3.29.0.153 because Sketch loads a native
Qt extension into Xochitl. Other firmware versions are not validated.

Paper Sketch 4.1 models six aspects of dry media: tilt/contact shape, pressure
response, paper tooth and burnishing, virtual tip wear, finger contact and two
eraser behaviors. These are digital approximations. Calibration adjusts stylus
input; no physical-pencil matching or optical panel latency is claimed.
Open the Materials settings icon in the bottom navigation bar for these controls.

Browse the source at <https://github.com/lbabut/PaperDesk>. The release project
archive also contains prepared ARM files for installation.

## Repository layout

- `product/` — installable release tree, including source and licence notices.
- `tests/` — package, QML, and physical-tablet user journey tests.
- `website/` — open-source product site and download service.
- `docs/` — positioning, go-to-market plan, launch checklist, and the
  [control-by-control UX audit](docs/UX-CONTROL-AUDIT.md).
- `scripts/` — repeatable build and verification helpers.
- `dist/` — checksums for distributable artifacts. Release archives are built locally.

## Manual installation over SSH

Download the project-source + prepared ARM package and follow
[the terminal installation guide](product/MANUAL-INSTALL.md) on Windows,
Linux or macOS. Existing XOVI/AppLoad/LiTerm dependencies are required.
No Windows EXE is needed. Graphical installer sources and historical artifacts
are retained for developers; the public site does not link to installers.

## Verify

```sh
./tests/run-ui-tests.sh
```

The local Qt test runtime is discovered through `PAPERDESK_TOOLCACHE`. On this
workstation it defaults to the existing PaperDesk tool cache; set the variable
to an equivalent unpacked Qt runtime when moving the repository elsewhere.

For a connected tablet:

```sh
PAPERDESK_E2E_TARGET=journey PAPERDESK_E2E_LOOPS=2 ./tests/run-tablet-e2e.sh
```

## Build a release archive

```sh
./scripts/build-release.sh
sh ./scripts/build-source-package.sh
```

## Run the product site

```sh
python3 website/server.py --host 127.0.0.1 --port 8090
```

Open `http://127.0.0.1:8090/`. The site has no accounts, email capture or
tracking cookies. It keeps aggregate download totals by file, day and country;
IP addresses are not stored in the statistics database.

## Independence and warranty

PaperDesk is an independent community product. It is not affiliated with or
endorsed by reMarkable AS. It modifies unsupported parts of the tablet and is
provided without warranty. See `LICENSES.md` and the notices in `product/`.
