#!/usr/bin/env python3
"""Prepare only release metadata and links in a clone of the live website."""
import hashlib
import html
import json
from pathlib import Path
import re
import sys

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare(stage, current, version):
    stage, current = Path(stage).resolve(), Path(current).resolve()
    if stage == current or stage.is_relative_to(current) or current.is_relative_to(stage):
        raise ValueError("Release stage and live directory must be separate siblings")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    old = json.loads((current / "website/update/stable.json").read_text())["version"]
    if tuple(map(int, version.split("."))) < tuple(map(int, old.split("."))):
        raise ValueError("Refusing release rollback")
    feed = json.loads((stage / "website/update/stable.json").read_text())
    if (feed.get("product"), feed.get("channel"), feed.get("version")) != ("PaperDesk", "stable", version):
        raise ValueError("Unexpected staged release feed")
    zip_name = f"paperdesk-{version}.zip"
    if feed["archiveUrl"] != "/download/" + zip_name:
        raise ValueError("Unexpected archive URL")
    for name in (zip_name, f"paperdesk-sources-{version}.tar.gz"):
        archive = stage / "dist" / name
        digest = sha(archive)
        if (current / "dist" / name).exists() and sha(current / "dist" / name) != digest:
            raise ValueError("Immutable archive already exists with different bytes: " + name)
        checksum = (stage / "dist" / (name + ".sha256")).read_text().split()
        if len(checksum) != 2 or checksum[0] != digest or checksum[1] != name:
            raise ValueError("Archive checksum mismatch: " + name)
        if name == zip_name and (feed["archiveSha256"] != digest or feed["archiveSize"] != archive.stat().st_size):
            raise ValueError("Signed update archive does not match the stage")
    audit = {"previous_version": old, "version": version, "html": {}}
    for name in ("index.html", "guide.html", "guide-en.html"):
        path = stage / "website" / name
        text = path.read_text()
        before = sha(path)
        text = re.sub(r"(?<!Fresh )" + re.escape(old) + r"\b", version, text)
        if name == "index.html":
            marker = r"(<summary>What changed in " + re.escape(version) + r"\?</summary>).*?(</details>)"
            notes = "<ul>" + "".join("<li>" + html.escape(note) + "</li>" for note in feed["releaseNotes"]) + "</ul>"
            text = re.sub(marker, lambda match: match[1] + notes + match[2], text, flags=re.S)
        path.write_text(text)
        audit["html"][name] = {"before": before, "after": sha(path)}
    archives = sorted(p for p in (stage / "dist").iterdir()
                      if p.is_file() and (p.name.endswith(".zip") or p.name.endswith(".tar.gz")))
    (stage / "dist/SHA256SUMS").write_text("".join(sha(p) + "  " + p.name + "\n" for p in archives))
    return audit

if __name__ == "__main__":
    print(json.dumps(prepare(*sys.argv[1:]), sort_keys=True))
