import importlib.util
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
        cls.httpd = cls.module.ThreadingHTTPServer(("127.0.0.1", 0), cls.module.Handler)
        cls.port = cls.httpd.server_address[1]
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=2)

    def request(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        return urllib.request.urlopen(url)

    def test_home_and_release_are_served(self):
        with self.request("/") as response:
            body = response.read().decode()
            self.assertEqual(response.status, 200)
            self.assertIn("Your quiet network desk", body)
            self.assertIn("Open source, for real", body)
            self.assertIn("Support development", body)
            self.assertIn("Every control earns its place", body)
            self.assertIn('id="tour"', body)
            self.assertNotIn("Founding Edition", body)
            self.assertNotIn("€29", body)
            self.assertNotIn("<form", body)
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
