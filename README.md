# PaperDesk

PaperDesk turns a reMarkable 2 into a quiet, monochrome network workspace.
It bundles four touch-first tools designed around the limits of e-ink:

- Terminal — SSH, system keyboard, gestures, and common shortcuts.
- Web — static, reader-first browsing with mobile mode and optional images.
- RDP — a monochrome FreeRDP client with pan, zoom, and keyboard shortcuts.
- RSS — RSS/Atom feeds, full-text reading, favourites, and offline cache.

The currently validated release is **1.0.5**, tested on reMarkable OS
3.29.0.149 with XOVI 0.3.3, AppLoad 0.6.0, and LiTerm 0.1.7.

## Repository layout

- `product/` — installable release tree, including source and licence notices.
- `tests/` — package, QML, and physical-tablet user journey tests.
- `website/` — product site and local waitlist service.
- `docs/` — positioning, go-to-market plan, and launch checklist.
- `scripts/` — repeatable build and verification helpers.
- `dist/` — checksums for distributable artifacts. Release archives are built locally.

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
```

## Run the product site

```sh
python3 website/server.py --host 127.0.0.1 --port 8090
```

Open `http://127.0.0.1:8090/`. Interest-form submissions are stored locally
in `website/data/interests.sqlite3` and are intentionally not committed.

## Independence and warranty

PaperDesk is an independent community product. It is not affiliated with or
endorsed by reMarkable AS. It modifies unsupported parts of the tablet and is
provided without warranty. See `LICENSES.md` and the notices in `product/`.
