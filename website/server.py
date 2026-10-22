#!/usr/bin/env python3
from __future__ import annotations

from contextlib import closing
import argparse
import json
import mimetypes
import os
import re
import shutil
import sqlite3
import ipaddress
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
STATE_DIR = Path(os.environ.get("PAPERDESK_STATE_DIR", "/var/lib/paperdesk"))
STATS_DB = STATE_DIR / "stats.sqlite3"
DOWNLOAD_PATTERN = r"/download/paperdesk-(?:(?:windows|linux)-installer-|sources-)?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.zip|\.tar\.gz)(?:\.sha256)?"
PUBLIC_PAGES = frozenset({"/", "/index.html", "/app.js", "/styles.css",
                          "/guide.html", "/guide-en.html", "/guide.css",
                          "/update/latest.json", "/update/latest.json.sig",
                          "/update/stable.json", "/update/stable.json.sig"})
sys.path.insert(0, str(ROOT))
from geoip import CountryLookup
from private_update_stats import record_update

COUNTRIES = CountryLookup(STATE_DIR / 'dbip-country-lite.csv.gz')


def initialize_stats() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(STATS_DB, timeout=5)) as database, database:
        database.execute(
            "CREATE TABLE IF NOT EXISTS counters "
            "(name TEXT PRIMARY KEY, value INTEGER NOT NULL CHECK(value >= 0))"
        )
        database.execute(
            "INSERT OR IGNORE INTO counters(name, value) VALUES('downloads', 0)"
        )
        database.execute(
            "CREATE TABLE IF NOT EXISTS download_countries "
            "(day TEXT NOT NULL, artifact TEXT NOT NULL, country TEXT NOT NULL, "
            "downloads INTEGER NOT NULL, PRIMARY KEY(day, artifact, country))"
        )
        # Preserve the existing total without inventing locations for old downloads.
        database.execute(
            "INSERT INTO download_countries SELECT 'before-country-tracking', 'legacy', 'ZZ', value "
            "FROM counters WHERE name = 'downloads' AND NOT EXISTS "
            "(SELECT 1 FROM download_countries)"
        )


def download_count() -> int:
    with closing(sqlite3.connect(STATS_DB, timeout=5)) as database, database:
        row = database.execute(
            "SELECT value FROM counters WHERE name = 'downloads'"
        ).fetchone()
    return int(row[0]) if row else 0


def country_counts() -> dict:
    with closing(sqlite3.connect(STATS_DB, timeout=5)) as database, database:
        rows = database.execute(
            "SELECT country, SUM(downloads) FROM download_countries GROUP BY country ORDER BY SUM(downloads) DESC"
        ).fetchall()
    return {'countries': dict(rows), 'downloaded': sum(count for _, count in rows)}


def record_download(artifact: str = 'unknown', country: str = 'ZZ') -> int:
    with closing(sqlite3.connect(STATS_DB, timeout=5)) as database, database:
        database.execute("BEGIN IMMEDIATE")
        database.execute(
            "UPDATE counters SET value = value + 1 WHERE name = 'downloads'"
        )
        database.execute(
            "INSERT INTO download_countries(day, artifact, country, downloads) VALUES(?, ?, ?, 1) "
            "ON CONFLICT(day, artifact, country) DO UPDATE SET downloads = downloads + 1",
            (datetime.now(timezone.utc).date().isoformat(), artifact, country),
        )
        row = database.execute(
            "SELECT value FROM counters WHERE name = 'downloads'"
        ).fetchone()
        database.commit()
    return int(row[0])


class Handler(BaseHTTPRequestHandler):
    server_version = "PaperDesk/1.0"

    def download_country(self) -> str:
        peer = self.client_address[0]
        # Caddy overwrites this header; accept it only from the local proxy.
        if ipaddress.ip_address(peer).is_loopback:
            peer = self.headers.get('X-PaperDesk-Client-IP', peer)
        return COUNTRIES.country(peer)

    def send_standard_headers(
        self, code: int, content_type: str, length: int, *, cache_control: str | None = None
    ) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Cache-Control",
            cache_control or ("no-store" if code != 200 else "public, max-age=300"),
        )
        self.end_headers()

    def send_bytes(self, code: int, payload: bytes, content_type: str) -> None:
        self.send_standard_headers(code, content_type, len(payload))
        self.wfile.write(payload)

    def send_download_count(self) -> None:
        payload = json.dumps({"downloaded": download_count()}).encode("utf-8") + b"\n"
        self.send_standard_headers(
            200,
            "application/json; charset=utf-8",
            len(payload),
            cache_control="no-store",
        )
        if self.command != "HEAD":
            self.wfile.write(payload)

    def send_country_counts(self) -> None:
        payload = json.dumps(country_counts()).encode() + b"\n"
        self.send_standard_headers(200, "application/json; charset=utf-8", len(payload), cache_control="no-store")
        if self.command != "HEAD":
            self.wfile.write(payload)

    def target_for_path(self, path: str) -> tuple[Path, str] | None:
        if path == "/healthz" or "\x00" in path or "\\" in path:
            return None
        archive = path.removeprefix("/download/")
        if re.fullmatch(DOWNLOAD_PATTERN, path):
            target = REPO / "dist" / archive
        elif path == "/download/SHA256SUMS":
            target = REPO / "dist" / "SHA256SUMS"
        else:
            # The website directory also contains code and legacy private data.
            # Only explicit public entry points and non-hidden assets are served.
            if path not in PUBLIC_PAGES and not (
                path.startswith("/assets/") and
                all(part and not part.startswith(".") for part in path.split("/")[2:])
            ):
                return None
            relative = "index.html" if path in ("/", "/index.html") else path.lstrip("/")
            target = (ROOT / relative).resolve()
            if ROOT not in target.parents and target != ROOT:
                return None
        if not target.is_file():
            return None
        return target, mimetypes.guess_type(target.name)[0] or "application/octet-stream"

    def do_GET(self) -> None:
        path = unquote(urlsplit(self.path).path)
        if path == "/healthz":
            self.send_bytes(200, b"ok\n", "text/plain; charset=utf-8")
            return
        if path == "/api/download-count":
            self.send_download_count()
            return
        if path == '/api/download-countries':
            self.send_country_counts()
            return
        resolved = self.target_for_path(path)
        if resolved is None:
            self.send_bytes(404, b"not found\n", "text/plain")
            return
        target, mime = resolved
        is_download = re.fullmatch(DOWNLOAD_PATTERN, path) and not path.endswith('.sha256')
        # Bound memory per request; simultaneous installer downloads must not
        # each allocate an entire archive. fstat describes the opened file even
        # if a release switches the directory while it is being downloaded.
        try:
            with target.open("rb") as source:
                self.send_standard_headers(200, mime, os.fstat(source.fileno()).st_size,
                                           cache_control='no-store' if is_download or path.startswith('/update/') else None)
                shutil.copyfileobj(source, self.wfile, length=64 * 1024)
        except (BrokenPipeError, ConnectionResetError):
            return
        except FileNotFoundError:
            self.send_bytes(404, b"not found\n", "text/plain")
            return
        if is_download:
            country = self.download_country()
            record_download(target.name, country)
            care_release = re.fullmatch(r"paperdesk-([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip", target.name)
            if care_release and self.headers.get("X-PaperDesk-Update") == "care-v1":
                try:
                    record_update(care_release.group(1), country, self.headers.get("X-PaperDesk-Install-Id", ""))
                except (OSError, sqlite3.Error, ValueError):
                    self.log_message("Private update accounting unavailable")

    def do_HEAD(self) -> None:
        path = unquote(urlsplit(self.path).path)
        if path == "/api/download-count":
            self.send_download_count()
            return
        if path == "/api/download-countries":
            self.send_country_counts()
            return
        if path == "/healthz":
            self.send_standard_headers(200, "text/plain; charset=utf-8", 3)
            return
        resolved = self.target_for_path(path)
        if resolved is None:
            self.send_standard_headers(404, "text/plain; charset=utf-8", 0)
            return
        target, mime = resolved
        is_download = re.fullmatch(DOWNLOAD_PATTERN, path) and not path.endswith('.sha256')
        self.send_standard_headers(200, mime, target.stat().st_size, cache_control='no-store' if is_download or path.startswith('/update/') else None)

    def do_POST(self) -> None:
        self.send_bytes(404, b"not found\n", "text/plain; charset=utf-8")

    def log_message(self, fmt: str, *args: object) -> None:
        print(fmt % args)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()
    initialize_stats()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
