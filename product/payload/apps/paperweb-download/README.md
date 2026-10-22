# Web document downloads

PaperWeb intercepts PDF/EPUB links and attachment headers. An accessible confirmation sheet offers **Save to My files** or Cancel. Files are streamed by a hidden, no-window ARM worker; binary data is never converted to a QML string. Web itself remains a reader-mode browser, not a general download manager.

Supported destination: reMarkable's native **My files** document library through `DocumentImporter`. Close Web and AppLoad to open the document in the built-in reader. Unsupported archives/installers/media are rejected, not saved in an invisible private folder. This does not log in to restricted sites or transfer browser cookies to the worker.

Safety limits: 64 MiB compressed/downloaded, 128 MiB declared uncompressed EPUB entries, 576 MiB free before starting, at least 512 MiB free during transfer. Content-Length is checked, but streamed bytes are independently capped even without it. The server must return a complete HTTP 200 response, then PDF header/trailer or EPUB structure/mimetype checks must pass. This is structural validation, not a malware guarantee.

Only public IPv4 HTTPS on standard port 443 is accepted, with system TLS verification. Local/private/link-local/metadata addresses are refused at the actual resolved socket, including every redirect. Proxy environment variables are disabled. IPv6-only servers, custom ports, HTTP links, credentials embedded in URLs and authenticated/cookie-only downloads are intentionally unsupported. Maximum six hops and a three-minute worker budget; connection and low-speed timeouts apply. Redirect bodies are discarded and capped at 64 KiB. Cancellation also works if requested before the worker starts.

Books and Web share a transfer lock. Native import is matched to both the exact staged source URL and a new native library wrapper; an uncertain-import marker tells users to check My files before retrying. Closing during a transfer requests cancellation; native import is not force-killed. Completed/error jobs are cleaned; interrupted private jobs are pruned after a week when a later download runs. Native documents and annotations are never deleted by this worker.

Build: `bash scripts/build-web-download.sh`, rebuild PaperWeb `resources.rcc`, then `bash scripts/update-product-checksums.sh`. The worker reuses the Books validation/staging source with compile-time limits; default Books limits and its ARM binary are unchanged. No system download service or XOVI autostart is enabled.

Regression tests: `tests/test_web_downloads.py`, `tests/web-download-validation.c`, `tests/qml/tst_web_downloads.qml`, and the existing Web actions/package suites. Network policy and callback behavior follow the official libcurl documentation: https://curl.se/libcurl/c/CURLOPT_OPENSOCKETFUNCTION.html and https://curl.se/libcurl/c/CURLOPT_MAXFILESIZE_LARGE.html (older curl versions still need an independent streaming cap).
