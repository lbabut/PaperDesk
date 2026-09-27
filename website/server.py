#!/usr/bin/env python3
from __future__ import annotations

import argparse
import mimetypes
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
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

    def target_for_path(self, path: str) -> tuple[Path, str] | None:
        if path == "/healthz":
            return None
        archive = path.removeprefix("/download/")
        if re.fullmatch(r"paperdesk-[0-9]+\.[0-9]+\.[0-9]+\.zip", archive):
            target = REPO / "dist" / archive
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
        self.send_bytes(404, b"not found\n", "text/plain; charset=utf-8")

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8090)
    args = parser.parse_args()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
