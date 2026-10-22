"""Private PaperDesk Care update-download accounting.

The archive download must have completed before record_update is called.
Records no client address, user agent, or browser cookies. Never expose via HTTP.
"""
from __future__ import annotations

from contextlib import closing
from datetime import datetime, timezone
import hashlib
import hmac
import os
from pathlib import Path
import re
import sqlite3

DB_PATH = Path(os.environ.get("PAPERDESK_PRIVATE_UPDATES_DB", "/var/lib/paperdesk/private-updates.sqlite3"))
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){2,3}$")
TOKEN_RE = re.compile(r"^[0-9a-f]{32}$")
COUNTRY_RE = re.compile(r"^[A-Z]{2}$")


def _get_secret(db_path: Path) -> bytes:
    path = db_path.with_suffix(".key")
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "wb") as f:
            f.write(os.urandom(32))
    secret = path.read_bytes()
    if len(secret) != 32:
        raise ValueError("Invalid private update statistics key")
    return secret


def record_update(version: str, country: str, installation_id: str = "", *, db_path: Path | None = None) -> None:
    """Record one completed Care archive transfer, optionally one anonymous installation."""
    if not VERSION_RE.fullmatch(version):
        raise ValueError("Invalid version")
    if not COUNTRY_RE.fullmatch(country):
        country = "ZZ"
    if installation_id and not TOKEN_RE.fullmatch(installation_id):
        installation_id = ""
    path = Path(db_path or DB_PATH)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    day = datetime.now(timezone.utc).date().isoformat()
    fingerprint = hmac.new(_get_secret(path), installation_id.encode(), hashlib.sha256).hexdigest() if installation_id else None

    with closing(sqlite3.connect(path, timeout=10)) as db, db:
        os.chmod(path, 0o600)
        db.execute("BEGIN IMMEDIATE")
        db.execute("""CREATE TABLE IF NOT EXISTS updates (
            day TEXT NOT NULL, version TEXT NOT NULL, country TEXT NOT NULL,
            transfers INTEGER NOT NULL, PRIMARY KEY (day, version, country))""")
        db.execute("""CREATE TABLE IF NOT EXISTS installations (
            fingerprint TEXT PRIMARY KEY, first_day TEXT NOT NULL,
            last_day TEXT NOT NULL, transfers INTEGER NOT NULL)""")
        db.execute("""CREATE TABLE IF NOT EXISTS installation_versions (
            fingerprint TEXT NOT NULL, version TEXT NOT NULL, first_day TEXT NOT NULL,
            last_day TEXT NOT NULL, transfers INTEGER NOT NULL,
            PRIMARY KEY (fingerprint, version))""")
        db.execute("""INSERT INTO updates(day, version, country, transfers)
            VALUES (?, ?, ?, 1) ON CONFLICT(day, version, country)
            DO UPDATE SET transfers = transfers + 1""", (day, version, country))
        if fingerprint:
            db.execute("""INSERT INTO installations(fingerprint, first_day, last_day, transfers)
                VALUES (?, ?, ?, 1) ON CONFLICT(fingerprint)
                DO UPDATE SET last_day = excluded.last_day, transfers = transfers + 1""",
                (fingerprint, day, day))
            db.execute("""INSERT INTO installation_versions
                (fingerprint, version, first_day, last_day, transfers)
                VALUES (?, ?, ?, ?, 1) ON CONFLICT(fingerprint, version)
                DO UPDATE SET last_day = excluded.last_day, transfers = transfers + 1""",
                (fingerprint, version, day, day))


def read_report(*, db_path: Path | None = None) -> dict:
    """Read-only report; never create an endpoint or publish identifiers."""
    path = Path(db_path or DB_PATH)
    if not path.exists():
        return {"care_transfers": 0, "distinct_installations": 0, "recent_installations_30d": 0, "versions": []}
    with closing(sqlite3.connect(f"file:{path}?mode=ro", uri=True)) as db:
        total = db.execute("SELECT COALESCE(SUM(transfers), 0) FROM updates").fetchone()[0]
        distinct = db.execute("SELECT COUNT(*) FROM installations").fetchone()[0]
        recent = db.execute("SELECT COUNT(*) FROM installations WHERE last_day >= date('now', '-29 days')").fetchone()[0]
        rows = db.execute("""SELECT u.version, SUM(u.transfers),
            (SELECT COUNT(*) FROM installation_versions i WHERE i.version = u.version)
            FROM updates u GROUP BY u.version ORDER BY u.version DESC""").fetchall()
    return {"care_transfers": total, "distinct_installations": distinct,
            "recent_installations_30d": recent,
            "versions": [{"version": v, "care_transfers": count, "distinct_installations": devices}
                         for v, count, devices in rows]}
