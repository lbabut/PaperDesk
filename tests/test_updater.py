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
        fake_systemd_run = self.bin / "systemd-run"
        fake_systemd_run.write_text("#!/bin/sh\nexit 0\n")
        fake_systemd_run.chmod(fake_systemd_run.stat().st_mode | stat.S_IXUSR)
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

    def run_agent(self, version="1.1.1", overrides=None, installed="1.1.0"):
        self.settings.write_text(
            "[PaperDeskUpdate]\n"
            "installRequested=true\n"
            f"requestedVersion={version}\n"
            "requestedId=test-request-1\n"
        )
        (self.state / "current-version").write_text(installed + "\n")
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env['PATH']}",
                "PAPERDESK_TEST_MARKER": str(self.marker),
                "PAPERDESK_UPDATE_BASE_URL": f"http://127.0.0.1:{self.httpd.server_port}",
                "PAPERDESK_UPDATE_MANIFEST_PATH": "/update/latest.json",
                "PAPERDESK_UPDATE_STATE": str(self.state),
                "PAPERDESK_UPDATE_SETTINGS": str(self.settings),
                "PAPERDESK_UPDATE_PUBLIC_KEY": str(self.public_key),
                "PAPERDESK_UPDATE_WORK": str(self.root / "work"),
                "PAPERDESK_UPDATE_LOCK": str(self.root / "update.lock"),
                "PAPERDESK_UNINSTALLER": str(self.bin / "paperdesk-uninstall"),
                "PAPERDESK_TEST_UNINSTALL_MARKER": str(self.uninstall_marker),
            }
        )
        env.update(overrides or {})
        return subprocess.run(["sh", AGENT], env=env, capture_output=True, text=True, timeout=20)

    def test_signed_release_is_verified_installed_and_marked_successful(self):
        self.build_release()
        result = self.run_agent()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.marker.read_text().strip(), "--from-updater")
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "success")
        self.assertIn("1.1.1", status["message"])
        self.assertEqual(status["requestId"], "test-request-1")
        self.assertIn("installRequested=false", self.settings.read_text())

    def test_four_part_release_updates_three_and_four_part_installations(self):
        self.build_release("3.0.0.1")
        for installed in ("2.0.5", "3.0.0", "3.0.0.0"):
            with self.subTest(installed=installed):
                result = self.run_agent("3.0.0.1", installed=installed)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads((self.state / "update-status.json").read_text())["state"], "success")

    def test_four_part_release_does_not_downgrade_newer_installation(self):
        self.build_release("3.0.0.1")
        result = self.run_agent("3.0.0.1", installed="3.0.0.2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.marker.exists())
        self.assertEqual(json.loads((self.state / "update-status.json").read_text())["state"], "current")

    def test_tampered_manifest_is_rejected_before_download_or_install(self):
        manifest = self.build_release()
        manifest.write_text(manifest.read_text().replace("1.1.1", "1.1.2", 1))
        result = self.run_agent("1.1.2")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "error")
        self.assertIn("signature", status["message"].lower())

    def test_existing_workspace_contents_are_never_deleted(self):
        self.build_release()
        workspace = self.root / "work"
        workspace.mkdir()
        sentinel = workspace / "unrelated-user-file"
        sentinel.write_text("keep me")
        result = self.run_agent()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), "keep me")
        self.assertEqual(list(self.root.glob("work.*")), [])

    def test_concurrent_invocation_does_not_consume_the_request_or_status(self):
        import fcntl
        status_file = self.state / "update-status.json"
        status_file.write_text('{"state":"installing"}\n')
        with (self.root / "update.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_agent()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("installRequested=true", self.settings.read_text())
        self.assertEqual(status_file.read_text(), '{"state":"installing"}\n')

    def test_archive_tampering_never_runs_the_installer(self):
        self.build_release()
        archive = self.web / "download/paperdesk-1.1.1.zip"
        archive.write_bytes(b"not the signed archive")
        result = self.run_agent()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertEqual(json.loads((self.state / "update-status.json").read_text())["state"], "error")

    def test_same_or_older_version_is_not_installed(self):
        self.build_release()
        result = self.run_agent(installed="1.2.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.marker.exists())
        self.assertEqual(json.loads((self.state / "update-status.json").read_text())["state"], "current")

    def test_invalid_requested_version_cannot_corrupt_json_status(self):
        result = self.run_agent('bad"version')
        self.assertNotEqual(result.returncode, 0)
        status = json.loads((self.state / "update-status.json").read_text())
        self.assertEqual(status["state"], "error")
        self.assertEqual(status["version"], "")

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
