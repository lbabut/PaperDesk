# PaperDesk Books

Native reMarkable / XOVI AppLoad library, text reader and PDF/EPUB acquisition frontend.

## Sources and native reading

- **Project Gutenberg**: public-domain plain-text editions; **Europe PMC**: full-text Open Access articles, converted from JATS with attribution and licence information.
- **Wolne Lektury**: Polish literature, complete EPUB editions after checking the title's detail record, language and preview status. The large catalogue is reduced to search metadata and cached in memory for 24 hours or until Books closes, not downloaded for each query. It is not placed in QSettings, where megabytes of catalogue data would slow down settings/bookmark writes.
- **OpenStax**: live, Creative Commons-licensed textbooks with an actual free PDF. The catalogue uses the same session cache. PDF retains diagrams, equations and original attribution.
- **arXiv**: full PDF research preprints, not abstracts and not necessarily peer reviewed. Requests are paced by at least 3.1 seconds; further pages are available through Load more. Original article terms remain applicable.
- **Open Library / Internet Archive**: only public, readable, unrestricted editions. The concrete Archive item's metadata is checked again before offering an actual PDF/EPUB file. Borrowing, restricted collections, private files and DRM files are excluded; no login or restriction bypass is attempted.

PDF and EPUB files are downloaded by the no-window `paperbooks-download` worker and passed to Xochitl's own `DocumentImporter` (`xofm.libs.library`). They appear in **My files**, where reMarkable manages pagination, annotations and reading position. **Close Books**, close AppLoad, then tap the document in My files. Tapping its shortcut in Books explains this location; it does not use private window-routing APIs to force-open a native document. Removing a native title's shortcut from Books does **not** delete the original document or annotations from My files. Text titles retain the existing Books reader and bookmarks.

The importer is feature-detected: unsupported firmware gets an explanatory message, not a broken app. This integration does not enable the USB web interface, expose an HTTP server, modify native document metadata directly, or restart Xochitl for each import. Native document import is firmware-dependent and requires hardware validation.

Downloads require HTTPS with certificate validation, approved provider/redirect hosts, complete HTTP 200 responses, a 256 MB maximum, disk headroom and a bounded transfer time. PDF headers/trailers and EPUB ZIP structure/mimetype are checked before import. Binary files are streamed to private disk storage, never held as a huge QML string. Successful imports clean their staging files. Closing/cancelling before import requests cancellation; do not retry an uncertain native import without checking My files first.

Build the ARM worker with `bash scripts/build-books-download.sh`, then rebuild `resources.rcc` from `application.qrc` and run `bash scripts/update-product-checksums.sh`. Do not rebuild or replace an already-published release archive merely to test development changes.

- Uses the common PaperDesk action buttons, typography and black-and-white layout. Preferred languages are large touch tiles.
- Tap an offline book's title to read. Delete asks for confirmation and removes its saved reading position. The included Iliad can be hidden and restored in Settings.
- Tap a search result to download it. Saved results show **Saved offline** and open the local copy on a second tap.
- Results include authors, Title / Author / Newest added sorting, and further OPDS pages through Load more. Newest added refers to the Gutenberg catalogue, not the original publication year. Merged pages use catalogue IDs as a fallback when release dates are absent.
- Settings stores both language preferences and all six selected search services. Disabled services receive no search requests. Keep at least one service and language selected. Results and offline entries identify their source.
- Network requests are cancelled on close and bounded to 45 seconds. Search failures do not prevent another selected service from returning results. Each service retains its own pagination.
- Europe PMC uses its public REST API with `OPEN_ACCESS:y AND IN_PMC:y` and selected-language filters. Only full-text open-access records with a PMC id are offered. Full JATS XML is converted to offline readable text including source URL, licence/attribution, abstract, body and references. Incomplete XML or mismatched article ids are rejected without replacing an existing copy. This text path does not reproduce figures and complex formula layout; PDF editions from the other services use the native reader instead.
- Downloads are saved only after a complete HTTP response and a Gutenberg end marker. An incomplete retry never replaces a saved copy.
- Complete books scroll continuously. Small lazily rendered text blocks preserve every character, including the final licence, without artificial 9,000-character reading parts. Pinch resizes text; A− / A+ are also available. Reading positions use a text block and offset rather than a fragile whole-book pixel coordinate.
- Saving a search result updates its offline role in place instead of resetting the list. Model insertions preserve the visible book and offset. Lists reuse cached delegates; reader swipes have bounded inertia, stop on a new touch/pinch, and defer explicit disk synchronization until after the gesture.
- SQLite is optional. Firmware without its driver uses bounded persistent settings storage (at most 5 million characters per download and 10 million characters for the fallback shelf); reaching a limit reports a failure instead of truncating text.

The included Iliad is Project Gutenberg #2199, Homer translated by Samuel Butler: https://www.gutenberg.org/ebooks/2199. The complete source text and Gutenberg licence are bundled. The earlier section files remain in the source tree for integrity checks and old-bookmark migration.

Tests: `python3 -m unittest discover -s tests -p test_paperbooks.py`, `node tests/paperbooks-engine.cjs`, and the PaperBooks suite in `tests/run-ui-tests.sh`. The QML suite exercises actual title taps, deletion, language/service tiles, vector selection marks, readable source-labelled results, sorting, whole-book endings, touch scrolling and two-finger pinch events. Engine tests cover free-content filters, disabled services, article identity, complete XML, attribution and offline persistence. On-device tests retain original books and reading positions.

Hardware validation on 2026-10-17 (reMarkable 2, OS 3.29): live OPDS authors and all sort controls; a complete new download with Saved offline; full Sklepy cynamonowe and Iliad offline, including rendered final text; physical evdev scroll and two-contact pinch; reading-position restoration; delete/cancel/confirm persistence. Original downloaded texts and pre-test reading positions were retained. Physical input and Wi-Fi were restored after testing. No device screen-grab path was used.
