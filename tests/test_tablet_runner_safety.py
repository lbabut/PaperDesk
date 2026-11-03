import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TabletRunnerSafetyTests(unittest.TestCase):
    def test_local_build_failure_never_runs_device_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            tools = base / "bin"
            tools.mkdir()
            log = base / "ssh-calls"
            ssh = tools / "ssh"
            ssh.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$AUDIT_SSH_LOG"\n')
            ssh.chmod(0o700)
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       PAPERDESK_WORKDIR=str(base / "no-toolchain"),
                       PAPERDESK_ARTIFACT_DIR=str(base / "artifacts"),
                       AUDIT_SSH_LOG=str(log))
            result = subprocess.run(["bash", str(ROOT / "tests/run-tablet-e2e.sh")],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            calls = log.read_text().splitlines()
            self.assertEqual(len(calls), 1, calls)
            self.assertNotIn("systemctl stop", calls[0])
            self.assertNotIn("mknod", calls[0])

    def test_detail_options_reject_before_device_access(self):
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);tools=base/"bin";tools.mkdir();log=base/"ssh-calls"
            ssh=tools/"ssh";ssh.write_text('#!/bin/sh\nprintf "called" >> "$AUDIT_SSH_LOG"\n');ssh.chmod(0o700)
            env=dict(os.environ,PATH=f"{tools}:{os.environ['PATH']}",AUDIT_SSH_LOG=str(log))
            for options in [["--detail-fullscreen"],["--detail-check-latency"],["--detail-proximity-exits"],["--detail-no-preview"],["--detail-probe","--latency-probe"],["--detail-probe","--eraser-probe"]]:
                result=subprocess.run([__import__("sys").executable,str(ROOT/"tests/run-sketch-native.py"),
                    "--host","unused","--key","unused","--known-hosts","unused"]+options,
                    capture_output=True,text=True,env=env,timeout=5)
                self.assertEqual(result.returncode,2,result.stderr)
                self.assertFalse(log.exists(),"Argument rejection must not touch the tablet")

    def test_shell_scripts_parse(self):
        scripts = [ROOT / "product/install.sh", ROOT / "product/uninstall.sh",
                   ROOT / "product/payload/system/paperdesk-update-agent",
                   ROOT / "product/payload/system/rmssh-menu"]
        for script in scripts:
            with self.subTest(script=script):
                subprocess.run(["sh", "-n", str(script)], check=True)
        subprocess.run(["bash", "-n", str(ROOT / "tests/run-tablet-e2e.sh")], check=True)
