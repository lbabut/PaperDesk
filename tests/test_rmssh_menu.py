import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MENU = ROOT / "product/payload/system/rmssh-menu"


class RmsshMenuTests(unittest.TestCase):
    def test_graphical_picker_never_types_into_an_active_session(self):
        node = shutil.which("node")
        if not node: self.skipTest("Node.js unavailable")
        result = subprocess.run([node, str(ROOT / "tests/ssh-session-protocol.cjs")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_saved_session_protocol_and_active_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary) / "home"
            fake_bin = pathlib.Path(temporary) / "bin"
            home.mkdir(); fake_bin.mkdir()
            log = pathlib.Path(temporary) / "ssh.log"
            fake_ssh = fake_bin / "ssh"
            fake_ssh.write_text('#!/bin/sh\ncat "$HOME/.config/rmssh/state" >> "$SSH_LOG"\nprintf "%s\\n" "$*" >> "$SSH_LOG"\n')
            fake_ssh.chmod(0o755)
            env = dict(os.environ, HOME=str(home), PATH=str(fake_bin) + ":" + os.environ["PATH"],
                       SSH_LOG=str(log), PAPERDESK_RMSSH_START_DELAY="0")
            result = subprocess.run(["sh", str(MENU)], input="c ::1 tester 2222\n\nq\n",
                                    text=True, capture_output=True, env=env, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertRegex(log.read_text(), r"^busy [0-9]+ [0-9]+\n")
            self.assertIn("-p 2222 -l tester -- ::1", log.read_text())
            self.assertFalse((home / ".config/rmssh/state").exists(), "State must be cleaned up on exit")
            self.assertEqual((home / ".config/rmssh").stat().st_mode & 0o777, 0o700)
            log.unlink()
            for invalid in ["c -option user 22", "c host user 0", "c host user 65536", "c host user 22 extra", "c host user;touch 22"]:
                result = subprocess.run(["sh", str(MENU)], input=invalid + "\nq\n", text=True,
                                        capture_output=True, env=env, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(log.exists(), invalid)

    def test_new_connection_has_no_profiles_aliases_or_advanced_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary) / "home"
            fake_bin = pathlib.Path(temporary) / "bin"
            home.mkdir()
            fake_bin.mkdir()
            ssh_log = pathlib.Path(temporary) / "ssh.log"
            fake_ssh = fake_bin / "ssh"
            fake_ssh.write_text(
                "#!/bin/sh\n"
                "printf '%s|%s\\n' \"$TERM\" \"$*\" >> \"$SSH_LOG\"\n"
            )
            fake_ssh.chmod(0o755)

            environment = os.environ.copy()
            environment.update(
                HOME=str(home),
                PATH=f"{fake_bin}:{environment['PATH']}",
                SSH_LOG=str(ssh_log),
                PAPERDESK_RMSSH_START_DELAY="0",
            )
            answers = (
                "n\n"
                "nostalgiczny\n"
                "lukasz\n"
                "2222\n"
                "\n"
                "q\n"
            )
            result = subprocess.run(
                ["sh", str(MENU)],
                input=answers,
                text=True,
                capture_output=True,
                env=environment,
                timeout=5,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((home / ".config/rmssh/profiles").exists())
            invocation = ssh_log.read_text()
            self.assertTrue(invocation.startswith("xterm-256color|"), invocation)
            self.assertNotIn(" -C ", invocation)
            self.assertIn("-p 2222", invocation)
            self.assertIn("-l lukasz -- nostalgiczny", invocation)
            self.assertIn("UserKnownHostsFile=" + str(home / ".ssh/known_hosts"), invocation)
            self.assertNotIn("ConnectTimeout", invocation)
            self.assertNotIn("ServerAliveCountMax", invocation)
            self.assertNotIn("save profile", result.stdout.lower())
            self.assertNotIn("alias", result.stdout.lower())
            self.assertNotIn("Advanced", result.stdout)


if __name__ == "__main__":
    unittest.main()
