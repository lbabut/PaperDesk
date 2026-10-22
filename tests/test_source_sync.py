"""Safety regressions for source copies; never contact a real server."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/sync-sources-lola.sh"


class SourceSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bin = Path(self.temp.name)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        rsync = self.bin / "rsync"
        rsync.write_text('#!/bin/sh\nprintf "ARG=%s\\n" "$@"\nexit "${FAKE_RSYNC_EXIT:-0}"\n')
        rsync.chmod(0o700)
        ssh = self.bin / "ssh"
        ssh.write_text('#!/bin/sh\necho UNEXPECTED_REMOTE_WRITE >&2\nexit 99\n')
        ssh.chmod(0o700)

    def run_sync(self, *args, script=SCRIPT):
        return subprocess.run(
            ["bash", str(script), *args], env=self.env, text=True,
            capture_output=True, check=False,
        )

    def test_default_is_read_only_checksum_comparison(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ARG=-rlnic\n", result.stdout)
        self.assertIn("ARG=--delete\n", result.stdout)  # Reporting only, -n above.
        self.assertIn("ARG=lola:/home/lukasz/PaperDesk-sources/\n", result.stdout)
        self.assertNotIn("UNEXPECTED_REMOTE_WRITE", result.stderr)

    def test_copy_excludes_credentials_runtime_and_git_internals(self):
        result = self.run_sync("--check")
        for pattern in (
            "/.git/", "/work/", "/build/", "/website/data/",
            "/product/paperdesk.local.conf", "__pycache__/",
        ):
            self.assertIn(f"ARG=--exclude={pattern}\n", result.stdout)

    def test_invalid_arguments_stop_before_transport(self):
        for args in (("--deploy",), ("--apply", "unexpected")):
            with self.subTest(args=args):
                result = self.run_sync(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")

    def test_transport_failure_is_not_reported_as_success(self):
        self.env["FAKE_RSYNC_EXIT"] = "42"
        result = self.run_sync("--check")
        self.assertEqual(result.returncode, 42)

    def test_relocated_or_old_copy_cannot_publish(self):
        folder = self.bin / "old-copy/scripts"
        folder.mkdir(parents=True)
        relocated = folder / SCRIPT.name
        shutil.copyfile(SCRIPT, relocated)
        result = self.run_sync("--apply", script=relocated)
        self.assertEqual(result.returncode, 2)
        self.assertIn("authoritative project", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
