import importlib.util
import threading
import unittest
import urllib.error
import urllib.request
import hashlib
import io
import json
import re
import tarfile
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / "product/VERSION").read_text().strip()
INDEX = (ROOT / "website/index.html").read_text()
# Historical installers remain downloadable, but are not linked by public pages.
WINDOWS_VERSION = "3.0.0.1"
LINUX_VERSION = "3.0.0.1"


def load_server():
    spec = importlib.util.spec_from_file_location("paperdesk_site", ROOT / "website/server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WebsiteTests(unittest.TestCase):
    def test_dots_description_links_to_the_correct_wikipedia_rules(self):
        card = re.search(r'<h3>PaperDesk Dots</h3>(.*?)</article>', INDEX, re.S).group(1)
        self.assertIn('href="https://en.wikipedia.org/wiki/Dots_(paper-and-pencil_game)#Rules"', card)
        self.assertIn('How to play (Wikipedia)', card)
        self.assertIn('target="_blank" rel="noopener noreferrer"', card)
        self.assertIn('href="/guide-en.html#dots"', card)

    @classmethod
    def setUpClass(cls):
        cls.module = load_server()
        # Historical binaries are intentionally absent from source checkouts.
        # Serve immutable synthetic historical artifacts from a temporary repo,
        # while the current release route still opens the real built archive.
        cls.artifacts = tempfile.TemporaryDirectory(prefix='paperdesk-site-artifacts-')
        cls.module.REPO = Path(cls.artifacts.name)
        distribution = cls.module.REPO / 'dist'
        distribution.mkdir()
        current = ROOT / 'dist' / f'paperdesk-{VERSION}.zip'
        (distribution / current.name).symlink_to(current)
        windows = distribution / f'paperdesk-windows-installer-{WINDOWS_VERSION}.zip'
        with zipfile.ZipFile(windows, 'w') as archive:
            archive.writestr('README.txt', 'Historical download route test fixture.\n')
        linux = distribution / f'paperdesk-linux-installer-{LINUX_VERSION}.tar.gz'
        with tarfile.open(linux, 'w:gz') as archive:
            payload = b'Historical download route test fixture.\n'
            entry = tarfile.TarInfo('README.txt')
            entry.size = len(payload)
            archive.addfile(entry, io.BytesIO(payload))
        for archive in (windows, linux):
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            checksum = distribution / (archive.name + '.sha256')
            checksum.write_text(digest + '  ' + archive.name + '\n')
            archive.chmod(0o444)
            checksum.chmod(0o444)
        cls.state = tempfile.TemporaryDirectory()
        cls.module.STATE_DIR = Path(cls.state.name)
        cls.module.STATS_DB = cls.module.STATE_DIR / 'stats.sqlite3'
        cls.module.initialize_stats()
        cls.httpd = cls.module.ThreadingHTTPServer(("127.0.0.1", 0), cls.module.Handler)
        cls.port = cls.httpd.server_address[1]
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=2)
        cls.state.cleanup()
        cls.artifacts.cleanup()

    def request(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        return urllib.request.urlopen(url)

    def test_home_and_release_are_served(self):
        with self.request("/") as response:
            body = response.read().decode()
            self.assertEqual(response.status, 200)
            self.assertIn("A little more<br>", body)
            self.assertIn("A small independent project", body)
            self.assertIn("Made with curiosity.", body)
            self.assertIn(
                'href="https://ko-fi.com/lbabut"',
                body,
            )
            self.assertIn("Support PaperDesk on Ko-fi", body)
            self.assertIn("Eight free apps", body)
            self.assertIn('id="tour"', body)
            self.assertNotIn("Founding Edition", body)
            self.assertNotIn("€29", body)
            self.assertNotIn("<form", body)
            for screenshot in (
                "terminal-shortcuts.png",
                "paperbooks-20261103.png",
                "paperdots-20261103.png",
                "paperweb-20261103.png",
            ):
                self.assertIn(f"/assets/screens/{screenshot}", body)
            self.assertNotIn("web-illustration", body)
            self.assertNotIn("web-reader.png", body)
        with self.request(f"/download/paperdesk-{VERSION}.zip") as response:
            self.assertEqual(response.status, 200)
            self.assertGreater(int(response.headers["Content-Length"]), 1_000_000)
            self.assertGreater(len(response.read()), 1_000_000)

    def test_head_supports_health_and_download_monitors(self):
        for path in ("/healthz", "/", f"/download/paperdesk-{VERSION}.zip", f"/download/paperdesk-windows-installer-{WINDOWS_VERSION}.zip", f"/download/paperdesk-linux-installer-{LINUX_VERSION}.tar.gz", f"/download/paperdesk-windows-installer-{WINDOWS_VERSION}.zip.sha256", "/update/latest.json", "/update/latest.json.sig"):
            request = urllib.request.Request(
                f"http://127.0.0.1:{self.port}{path}", method="HEAD"
            )
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 200)
                self.assertGreater(int(response.headers["Content-Length"]), 0)

    def test_windows_installer_and_checksum_are_served(self):
        import hashlib
        with self.request(f'/download/paperdesk-windows-installer-{WINDOWS_VERSION}.zip') as response:
            data = response.read()
        with self.request(f'/download/paperdesk-windows-installer-{WINDOWS_VERSION}.zip.sha256') as response:
            checksum = response.read().decode().split()[0]
        self.assertEqual(hashlib.sha256(data).hexdigest(), checksum)

    def test_download_cards_and_polish_business_guide(self):
        with self.request('/') as response:
            page = response.read().decode()
        self.assertIn('class="download-cards"', page)
        self.assertIn('href="/guide.html"', page)
        self.assertIn('<details class="advanced-downloads">', page)
        with self.request('/guide.html') as response:
            guide = response.read().decode()
        self.assertIn('<html lang="pl">', guide)
        for section in ['before', 'install', 'linux', 'use', 'help', 'updates']:
            self.assertIn(f'id="{section}"', guide)
        self.assertIn('sha256sum -c SHA256SUMS', guide)
        self.assertIn('scp paperdesk-tablet-', guide)
        self.assertIn('Get-FileHash', guide)
        self.assertIn('Remember password', guide)
        self.assertIn('Remove PaperDesk', guide)
        with self.request('/guide.css') as response:
            self.assertIn('@media print', response.read().decode())

    def test_download_path_traversal_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.request('/download/../deploy/Caddyfile')
        self.assertEqual(caught.exception.code, 404)

    def test_only_public_site_files_are_exposed(self):
        for path in ("/server.py", "/geoip.py", "/data/interests.sqlite3",
                     "/__pycache__/server.cpython-313.pyc", "/.env",
                     "/assets/../server.py", "/assets/%2e%2e/server.py",
                     "/update/../data/interests.sqlite3", "/%00"):
            with self.subTest(path=path):
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    self.request(path)
                self.assertEqual(caught.exception.code, 404)

    def test_archives_are_streamed_in_bounded_chunks(self):
        from unittest.mock import patch
        with patch.object(Path, "read_bytes", side_effect=AssertionError("Unbounded read")):
            with self.request(f"/download/paperdesk-{VERSION}.zip") as response:
                data = response.read()
                self.assertEqual(len(data), int(response.headers["Content-Length"]))

    def test_head_api_matches_get_without_a_response_body(self):
        for path in ("/api/download-count", "/api/download-countries"):
            request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method="HEAD")
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.read(), b"")
                self.assertEqual(response.headers["Cache-Control"], "no-store")

    def test_signed_update_feed_matches_download(self):
        with self.request("/update/stable.json") as response:
            manifest = json.loads(response.read())
        self.assertEqual(manifest["product"], "PaperDesk")
        self.assertEqual(manifest["version"], VERSION)
        self.assertEqual(manifest["archiveUrl"], f"/download/paperdesk-{VERSION}.zip")
        self.assertEqual(len(manifest["archiveSha256"]), 64)
        self.assertGreaterEqual(len(manifest["releaseNotes"]), 3)
        with self.request("/update/stable.json.sig") as response:
            self.assertGreater(len(response.read()), 32)

    def test_retired_interest_endpoint_does_not_collect_data(self):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/api/interest",
            data=b'{"email":"visitor@example.com"}',
            headers={"Content-Type": "application/json"},
        )
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request)
        self.assertEqual(caught.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
