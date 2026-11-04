import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "scripts/prepare-release-stage.py"
spec = importlib.util.spec_from_file_location("release_stage", MODULE)
release_stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_stage)

class ReleasePublicationTests(unittest.TestCase):
    def fixture(self, directory):
        current, stage = Path(directory)/"live", Path(directory)/"stage"
        (current/"website/update").mkdir(parents=True)
        (current/"dist").mkdir()
        (current/"website/update/stable.json").write_text(json.dumps({"version":"4.2.8"}))
        for name in ("index.html","guide.html","guide-en.html"):
            (current/"website"/name).write_text('<div class="art">4.2.8 /download/paperdesk-sources-4.2.8.tar.gz Fresh 4.2.8 interface render.</div><details><summary>What changed in 4.2.8?</summary><p>Old note</p></details>')
        (current/"website/styles.css").write_text("/* current live design */")
        (current/"website/server.py").write_text("# current backend")
        (current/"dist/old.zip").write_bytes(b"immutable-old")
        shutil.copytree(current,stage)
        for name in ("paperdesk-4.2.9.zip","paperdesk-sources-4.2.9.tar.gz"):
            data=b"new-"+name.encode()
            (stage/"dist"/name).write_bytes(data)
            (stage/"dist"/(name+".sha256")).write_text(hashlib.sha256(data).hexdigest()+"  "+name+"\n")
        archive=stage/"dist/paperdesk-4.2.9.zip"
        feed={"product":"PaperDesk","channel":"stable","version":"4.2.9",
              "archiveUrl":"/download/"+archive.name,"archiveSha256":release_stage.sha(archive),
              "archiveSize":archive.stat().st_size,"releaseNotes":["Faster charcoal & preserved <texture>"]}
        (stage/"website/update/stable.json").write_text(json.dumps(feed))
        return current,stage

    def test_preserves_live_design_backend_old_archives_and_capture_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            live,stage=self.fixture(directory)
            live_before={str(p.relative_to(live)):p.read_bytes() for p in live.rglob("*") if p.is_file()}
            result=release_stage.prepare(stage,live,"4.2.9")
            self.assertEqual(result["version"],"4.2.9")
            for name in ("website/styles.css","website/server.py","dist/old.zip"):
                self.assertEqual((stage/name).read_bytes(),(live/name).read_bytes())
            text=(stage/"website/index.html").read_text()
            self.assertIn("paperdesk-sources-4.2.9.tar.gz",text)
            self.assertIn("Fresh 4.2.8 interface render.",text)
            self.assertIn("Faster charcoal &amp; preserved &lt;texture&gt;",text)
            self.assertIn("old.zip",(stage/"dist/SHA256SUMS").read_text())
            self.assertEqual(live_before,{str(p.relative_to(live)):p.read_bytes() for p in live.rglob("*") if p.is_file()})

    def test_rejects_different_existing_immutable_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            live,stage=self.fixture(directory)
            (live/"dist/paperdesk-4.2.9.zip").write_bytes(b"existing-different")
            with self.assertRaisesRegex(ValueError,"Immutable"):
                release_stage.prepare(stage,live,"4.2.9")

    def test_rejects_tampered_update_before_touching_html(self):
        with tempfile.TemporaryDirectory() as directory:
            live,stage=self.fixture(directory)
            before=(stage/"website/index.html").read_bytes()
            (stage/"dist/paperdesk-4.2.9.zip").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError,"checksum"):
                release_stage.prepare(stage,live,"4.2.9")
            self.assertEqual(before,(stage/"website/index.html").read_bytes())

    def test_rejects_live_directory_as_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            live,_stage=self.fixture(directory)
            with self.assertRaisesRegex(ValueError,"separate"):
                release_stage.prepare(live,live,"4.2.9")
