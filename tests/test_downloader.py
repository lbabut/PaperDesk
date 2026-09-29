import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
AGENT = ROOT / "product/payload/system/paperdesk-download-agent"


class DownloadAgentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = pathlib.Path(self.temp.name)
        self.settings = self.base / "xochitl.conf"
        self.state = self.base / "state"
        self.downloads = self.base / "downloads"
        self.lock = self.base / "download.lock"
        self.fake_wget = self.base / "wget"
        self.fake_wget.write_text(
            "#!/bin/sh\n"
            "set -eu\n"
            "output=\n"
            "while [ \"$#\" -gt 0 ]; do\n"
            "  if [ \"$1\" = -O ]; then shift; output=$1; fi\n"
            "  shift\n"
            "done\n"
            "test -n \"$output\"\n"
            "printf 'downloaded payload' > \"$output\"\n"
        )
        self.fake_wget.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            {
                "PAPERDESK_DOWNLOAD_SETTINGS": str(self.settings),
                "PAPERDESK_DOWNLOAD_STATE": str(self.state),
                "PAPERDESK_DOWNLOAD_DIR": str(self.downloads),
                "PAPERDESK_DOWNLOAD_LOCK": str(self.lock),
                "PAPERDESK_DOWNLOAD_WGET": str(self.fake_wget),
            }
        )

    def tearDown(self):
        self.temp.cleanup()

    def request(self, request_id, url, name):
        self.settings.write_text(
            "[PaperWebDownload]\n"
            "requested=true\n"
            f"requestId={request_id}\n"
            f'requestUrl="{url}"\n'
            f'suggestedName="{name}"\n'
        )
        return subprocess.run(
            ["sh", str(AGENT)], env=self.env, text=True, capture_output=True
        )

    def test_two_sequential_requests_are_isolated_and_saved(self):
        first = self.request(
            "1790620000001", "https://example.test/first.zip", "first.zip"
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual((self.downloads / "first.zip").read_text(), "downloaded payload")
        self.assertIn("1790620000001|saved|Saved: first.zip", (self.state / "download-status").read_text())
        self.assertIn("requested=false", self.settings.read_text())

        second = self.request(
            "1790620000002", "https://example.test/checksums", "SHA256SUMS"
        )
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.downloads / "SHA256SUMS").read_text(), "downloaded payload")
        self.assertIn("1790620000002|saved|Saved: SHA256SUMS", (self.state / "download-status").read_text())

    def test_existing_file_gets_a_safe_numbered_name(self):
        self.downloads.mkdir()
        (self.downloads / "manual.pdf").write_text("old")
        result = self.request(
            "1790620000003", "https://example.test/manual.pdf", "manual.pdf"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.downloads / "manual-2.pdf").read_text(), "downloaded payload")

    def test_non_http_request_is_rejected_before_wget(self):
        result = self.request("1790620000004", "file:///etc/passwd", "passwd")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.downloads / "passwd").exists())
        self.assertIn("failed|Unsupported download address", (self.state / "download-status").read_text())


if __name__ == "__main__":
    unittest.main()
