#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import re
import sqlite3
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
DATA = ROOT / "data"
DB = DATA / "interests.sqlite3"
EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")
MAX_BODY = 4096


def initialise() -> None:
    DATA.mkdir(mode=0o700, parents=True, exist_ok=True)
    with sqlite3.connect(DB) as db:
        db.execute(
            """CREATE TABLE IF NOT EXISTS interests (
            id INTEGER PRIMARY KEY,
            created_at INTEGER NOT NULL,
            email TEXT NOT NULL,
            use_case TEXT NOT NULL,
            consent INTEGER NOT NULL,
            source TEXT NOT NULL,
            visitor_hash TEXT NOT NULL
            )"""
        )


class Handler(BaseHTTPRequestHandler):
    server_version = "PaperDesk/1.0"

    def send_standard_headers(self, code: int, content_type: str, length: int) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cache-Control", "no-store" if code != 200 else "public, max-age=300")
        self.end_headers()

    def send_bytes(self, code: int, payload: bytes, content_type: str) -> None:
        self.send_standard_headers(code, content_type, len(payload))
        self.wfile.write(payload)

    def send_json(self, code: int, value: dict) -> None:
        self.send_bytes(code, json.dumps(value).encode(), "application/json; charset=utf-8")

    def target_for_path(self, path: str) -> tuple[Path, str] | None:
        if path == "/healthz":
            return None
        if path == "/download/paperdesk-1.0.5.zip":
            target = REPO / "dist" / "paperdesk-1.0.5.zip"
        elif path == "/download/SHA256SUMS":
            target = REPO / "dist" / "SHA256SUMS"
        else:
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
        resolved = self.target_for_path(path)
        if resolved is None:
            self.send_bytes(404, b"not found\n", "text/plain")
            return
        target, mime = resolved
        self.send_bytes(200, target.read_bytes(), mime)

    def do_HEAD(self) -> None:
        path = unquote(urlsplit(self.path).path)
        if path == "/healthz":
            self.send_standard_headers(200, "text/plain; charset=utf-8", 3)
            return
        resolved = self.target_for_path(path)
        if resolved is None:
            self.send_standard_headers(404, "text/plain; charset=utf-8", 0)
            return
        target, mime = resolved
        self.send_standard_headers(200, mime, target.stat().st_size)

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/api/interest":
            self.send_json(404, {"ok": False, "error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length < 2 or length > MAX_BODY:
            self.send_json(413, {"ok": False, "error": "invalid_body"})
            return
        try:
            data = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_json(400, {"ok": False, "error": "invalid_json"})
            return
        email = str(data.get("email", "")).strip().lower()[:254]
        use_case = str(data.get("useCase", "")).strip()[:120]
        consent = data.get("consent") is True
        if not EMAIL.match(email) or not use_case or not consent:
            self.send_json(400, {"ok": False, "error": "invalid_fields"})
            return
        visitor = hashlib.sha256((self.client_address[0] + "paperdesk-local-salt").encode()).hexdigest()
        with sqlite3.connect(DB) as db:
            db.execute(
                "INSERT INTO interests(created_at,email,use_case,consent,source,visitor_hash) VALUES(?,?,?,?,?,?)",
                (int(time.time()), email, use_case, 1, "product-site", visitor),
            )
        self.send_json(HTTPStatus.CREATED, {"ok": True})

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()
    initialise()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
