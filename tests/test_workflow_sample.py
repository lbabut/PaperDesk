"""Free-preview route and privacy guards; no public issues are submitted."""
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


class WorkflowSampleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("sample_site", ROOT / "website/server.py")
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.module.STATE_DIR = Path(cls.tmp.name)
        cls.module.STATS_DB = cls.module.STATE_DIR / "stats.sqlite3"
        cls.module.initialize_stats()
        cls.server = cls.module.ThreadingHTTPServer(("127.0.0.1", 0), cls.module.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://127.0.0.1:" + str(cls.server.server_port)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def test_sample_page_and_no_backend_collection(self):
        with urllib.request.urlopen(self.base + "/workflow-sample.html") as r:
            page = r.read().decode()
        for item in ["No paid pack", "is public", "requires a GitHub account", "/assets/plan400/free-sample-v01.pdf", "template=workflow-sample-feedback.yml"]:
            self.assertIn(item, page)
        for item in ["<form", "<script", "mailto:", "ko-fi.com", "stripe.com"]:
            self.assertNotIn(item, page)

    def test_pdf_get_head_do_not_increment_program_downloads(self):
        before = self.module.download_count()
        path = "/assets/plan400/free-sample-v01.pdf"
        with urllib.request.urlopen(self.base + path) as r:
            self.assertEqual(r.headers.get_content_type(), "application/pdf")
            self.assertEqual(r.read(), (ROOT / "website" / path.lstrip("/")).read_bytes())
        with urllib.request.urlopen(urllib.request.Request(self.base + path, method="HEAD")) as r:
            self.assertEqual(r.read(), b"")
            self.assertGreater(int(r.headers["Content-Length"]), 0)
        self.assertEqual(before, self.module.download_count())

    def test_private_paths_still_rejected(self):
        for path in ["/server.py", "/data/interests.sqlite3", "/assets/../server.py", "/assets/plan400/../../server.py", "/assets/plan400/.secret"]:
            with self.subTest(path=path), self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(self.base + path)
            self.assertEqual(caught.exception.code, 404)

    def test_issue_form_required_questions_and_home_discovery(self):
        form = (ROOT / ".github/ISSUE_TEMPLATE/workflow-sample-feedback.yml").read_text()
        self.assertEqual(form.count("required: true"), 3)
        self.assertIn("are public", form)
        self.assertNotIn("labels:", form)
        self.assertIn('href="/workflow-sample.html"', (ROOT / "website/index.html").read_text())


if __name__ == "__main__": unittest.main()
