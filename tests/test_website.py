import importlib.util
import json
import sqlite3
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_server():
    spec = importlib.util.spec_from_file_location("paperdesk_site", ROOT / "website/server.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WebsiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_server()
        cls.temp = tempfile.TemporaryDirectory()
        cls.module.DATA = Path(cls.temp.name)
        cls.module.DB = cls.module.DATA / "interests.sqlite3"
        cls.module.initialise()
        cls.httpd = cls.module.ThreadingHTTPServer(("127.0.0.1", 0), cls.module.Handler)
        cls.port = cls.httpd.server_address[1]
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=2)
        cls.temp.cleanup()

    def request(self, path, data=None):
        url = f"http://127.0.0.1:{self.port}{path}"
        if data is None:
            return urllib.request.urlopen(url)
        payload = json.dumps(data).encode()
        request = urllib.request.Request(
            url, data=payload, headers={"Content-Type": "application/json"}
        )
        return urllib.request.urlopen(request)

    def test_home_and_release_are_served(self):
        with self.request("/") as response:
            body = response.read().decode()
            self.assertEqual(response.status, 200)
            self.assertIn("Your quiet network desk", body)
            self.assertIn("Founding Edition", body)
            self.assertIn("Every control earns its place", body)
            self.assertIn('id="tour"', body)
            for screenshot in (
                "terminal-shortcuts.png",
                "web-reader.png",
                "rss-reading-list.png",
                "rdp-session.png",
            ):
                self.assertIn(f"/assets/screens/{screenshot}", body)
        with self.request("/download/paperdesk-1.0.5.zip") as response:
            self.assertEqual(response.status, 200)
            self.assertGreater(int(response.headers["Content-Length"]), 1_000_000)
            self.assertGreater(len(response.read()), 1_000_000)

    def test_head_supports_health_and_download_monitors(self):
        for path in ("/healthz", "/", "/download/paperdesk-1.0.5.zip"):
            request = urllib.request.Request(
                f"http://127.0.0.1:{self.port}{path}", method="HEAD"
            )
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 200)
                self.assertGreater(int(response.headers["Content-Length"]), 0)

    def test_interest_form_persists_explicit_consent(self):
        with self.request(
            "/api/interest",
            {"email": "founder@example.com", "useCase": "SSH / server work", "consent": True},
        ) as response:
            self.assertEqual(response.status, 201)
        with sqlite3.connect(self.module.DB) as db:
            row = db.execute("SELECT email,use_case,consent FROM interests").fetchone()
        self.assertEqual(row, ("founder@example.com", "SSH / server work", 1))

    def test_interest_form_rejects_missing_consent(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.request(
                "/api/interest",
                {"email": "founder@example.com", "useCase": "All four", "consent": False},
            )
        self.assertEqual(caught.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
