import hashlib
import http.server
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import threading
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
AGENT = ROOT / "product/payload/system/paperdesk-update-agent"


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class UpdaterIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.web = self.root / "web"
        self.state = self.root / "state"
        self.bin = self.root / "bin"
        (self.web / "update").mkdir(parents=True)
        (self.web / "download").mkdir()
        self.state.mkdir()
        self.bin.mkdir()
        self.settings = self.root / "xochitl.conf"
        self.private_key = self.root / "signing.pem"
        self.public_key = self.root / "public.pem"
        self.marker = self.root / "installed"
        self.uninstall_marker = self.root / "uninstalled"
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "ED25519", "-out", self.private_key],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            ["openssl", "pkey", "-in", self.private_key, "-pubout", "-out", self.public_key],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        fake_systemctl = self.bin / "systemctl"
        fake_systemctl.write_text("#!/bin/sh\nexit 0\n")
        fake_systemctl.chmod(fake_systemctl.stat().st_mode | stat.S_IXUSR)
        fake_uninstaller = self.bin / "paperdesk-uninstall"
        fake_uninstaller.write_text('#!/bin/sh\nprintf "%s\\n" "$1" > "$PAPERDESK_TEST_UNINSTALL_MARKER"\n')
        fake_uninstaller.chmod(fake_uninstaller.stat().st_mode | stat.S_IXUSR)
        fake_xovi = self.root / "xovi-start"
        fake_xovi.write_text("#!/bin/sh\nexit 0\n")
        fake_xovi.chmod(fake_xovi.stat().st_mode | stat.S_IXUSR)
        self.httpd = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            lambda *args, **kwargs: QuietHandler(*args, directory=self.web, **kwargs),
        )
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def build_release(self, version="1.1.1"):
        release = self.root / f"paperdesk-{version}"
        release.mkdir()
        installer = release / "install.sh"
        installer.write_text('#!/bin/sh\nprintf "%s\\n" "$1" > "$PAPERDESK_TEST_MARKER"\n')
        installer.chmod(0o755)
        digest = hashlib.sha256(installer.read_bytes()).hexdigest()
        (release / "SHA256SUMS").write_text(f"{digest}  install.sh\n")
        archive = self.web / "download" / f"paperdesk-{version}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
            for path in release.iterdir():
                bundle.write(path, f"paperdesk-{version}/{path.name}")
        archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        manifest = {
            "product": "PaperDesk",
            "channel": "stable",
            "version": version,
            "publishedAt": "2026-09-28",
            "archiveUrl": f"/download/paperdesk-{version}.zip",
            "archiveSha256": archive_sha,
            "archiveSize": archive.stat().st_size,
            "releaseNotes": ["Updater integration fixture"],
        }
        manifest_path = self.web / "update/latest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        subprocess.run(
            [
                "openssl", "pkeyutl", "-sign", "-rawin", "-inkey", self.private_key,
                "-in", manifest_path, "-out", self.web / "update/latest.json.sig",
            ],
            check=True,
        )
        return manifest_path

    def run_agent(self, version="1.1.1"):
        self.settings.write_text(
            "[PaperDeskUpdate]\n"
            "installRequested=true\n"
            f"requestedVersion={version}\n"
        )
        (self.state / "current-version").write_text("1.1.0\n")
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "PAPERDESK_TEST_MARKER": str(self.marker),
                "PAPERDESK_UPDATE_BASE_URL": f"http://127.0.0.1:{self.httpd.server_port}",
                "PAPERDESK_UPDATE_STATE": str(self.state),
                "PAPERDESK_UPDATE_SETTINGS": str(self.settings),
                "PAPERDESK_UPDATE_PUBLIC_KEY": str(self.public_key),
                "PAPERDESK_UPDATE_WORK": str(self.root / "work"),
                "PAPERDESK_UPDATE_LOCK": str(self.root / "update.lock"),
                "PAPERDESK_UNINSTALLER": str(self.bin / "paperdesk-uninstall"),
                "PAPERDESK_TEST_UNINSTALL_MARKER": str(self.uninstall_marker),
            }
        )
        return subprocess.run(["sh", AGENT], env=env, capture_output=True, text=True)

    def test_signed_release_is_verified_installed_and_marked_successful(self):
        self.build_release()
        result = self.run_agent()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.marker.read_text().strip(), "--from-updater")
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "success")
        self.assertIn("1.1.1", status["message"])
        self.assertIn("installRequested=false", self.settings.read_text())

    def test_tampered_manifest_is_rejected_before_download_or_install(self):
        manifest = self.build_release()
        manifest.write_text(manifest.read_text().replace("1.1.1", "1.1.2", 1))
        result = self.run_agent("1.1.2")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "error")
        self.assertIn("signature", status["message"].lower())

    def test_uninstall_requires_a_separate_request_and_runs_bundled_uninstaller(self):
        self.settings.write_text(
            "[PaperDeskUpdate]\n"
            "installRequested=false\n"
            "uninstallRequested=true\n"
            "requestedVersion=\n"
        )
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "PAPERDESK_UPDATE_STATE": str(self.state),
                "PAPERDESK_UPDATE_SETTINGS": str(self.settings),
                "PAPERDESK_UPDATE_LOCK": str(self.root / "update.lock"),
                "PAPERDESK_UNINSTALLER": str(self.bin / "paperdesk-uninstall"),
                "PAPERDESK_TEST_UNINSTALL_MARKER": str(self.uninstall_marker),
            }
        )
        result = subprocess.run(["sh", AGENT], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.uninstall_marker.read_text().strip(), "--from-care")
        self.assertIn("uninstallRequested=false", self.settings.read_text())
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "success")
        self.assertIn("removed", status["message"].lower())


if __name__ == "__main__":
    unittest.main()
