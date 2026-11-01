import os
import hashlib
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "product/payload/apps/paperrdp-profile/profile-manager"


def hex_text(value: str) -> str:
    return value.encode("utf-8").hex()


class RdpProfileManagerTests(unittest.TestCase):
    def run_manager(self, config: Path, *args: str, extra_env=None) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env["PAPERDESK_RDP_CONFIG_DIR"] = str(config)
        env.update(extra_env or {})
        return subprocess.run(
            [str(MANAGER), *args], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )

    def save(self, config: Path, index: int, host: str, user: str,
             password: str = "", scale: int = 75, depth: int = 8):
        return self.run_manager(
            config, "--save", str(index), hex_text(host), hex_text(user), "",
            "3389", hex_text(password), str(scale), str(depth), "v1",
        )

    def test_add_edit_delete_are_atomic_private_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            for number in range(10):
                result = self.save(config, -1, f"host-{number}", "user")
                self.assertEqual(result.returncode, 0, result.stderr)

            profiles = config / "profiles"
            lines = profiles.read_text().splitlines()
            self.assertEqual(len(lines), 8)
            self.assertIn(hex_text("host-9"), lines[0])
            self.assertEqual(stat.S_IMODE(profiles.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o700)

            result = self.save(config, 1, "edited", "admin", "secret", 50, 16)
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = profiles.read_text().splitlines()
            self.assertIn(hex_text("edited"), lines[1])
            self.assertIn(hex_text("secret"), lines[1])

            result = self.run_manager(config, "--delete", "1")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(hex_text("edited"), profiles.read_text())
            self.assertEqual(len(profiles.read_text().splitlines()), 7)

    def test_mixed_legacy_and_landscape_profiles_survive_crud(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            config.mkdir()
            old = "v1\t686f7374\t75736572\t\t3389\t\t75\t8\n"
            (config / "profiles").write_text(old)
            result = self.run_manager(config, "--save", "-1", hex_text("wide"),
                hex_text("user"), "", "3389", "", "50", "16", "landscape", "v2")
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = (config / "profiles").read_text().splitlines()
            self.assertTrue(lines[0].endswith("\tlandscape"))
            self.assertEqual(lines[1] + "\n", old)
            before = (config / "profiles").read_bytes()
            invalid = self.run_manager(config, "--save", "0", hex_text("wide"),
                hex_text("user"), "", "3389", "", "50", "16", "upside-down", "v2")
            self.assertNotEqual(invalid.returncode, 0)
            self.assertEqual((config / "profiles").read_bytes(), before)
            self.assertEqual(self.save(config, 1, "edited-old", "user").returncode, 0)
            lines = (config / "profiles").read_text().splitlines()
            self.assertTrue(lines[0].endswith("\tlandscape"))
            self.assertTrue(lines[1].endswith("\tportrait"))
            self.assertEqual(self.run_manager(config, "--delete", "0").returncode, 0)
            self.assertEqual((config / "profiles").read_text().splitlines(), [lines[1]])

    def test_invalid_or_stale_requests_do_not_replace_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            self.assertEqual(self.save(config, -1, "safe", "user").returncode, 0)
            before = (config / "profiles").read_bytes()

            invalid = self.run_manager(
                config, "--save", "0", "not-hex", hex_text("user"), "",
                "3389", "", "75", "8", "v1",
            )
            self.assertNotEqual(invalid.returncode, 0)
            self.assertEqual((config / "profiles").read_bytes(), before)

            stale = self.run_manager(config, "--delete", "7")
            self.assertNotEqual(stale.returncode, 0)
            self.assertEqual((config / "profiles").read_bytes(), before)

    def operation_result(self, config, token):
        raw = (config / "operations" / (token + ".result")).read_text()
        header, body = raw.split("\n", 1)
        fields = header.split("\t")
        self.assertEqual(fields[:3], ["PaperDeskProfileResult", "1", token])
        self.assertEqual(len(fields), 7)
        return dict(action=fields[3], status=fields[4], revision=fields[5], code=fields[6], body=body)

    def read_operation(self, config, token="read-00000001"):
        run = self.run_manager(config, "--read", token)
        self.assertEqual(run.returncode, 0, run.stderr)
        result = self.operation_result(config, token)
        self.assertEqual(result["status"], "ok")
        return result

    def save_args(self, index, host, password=""):
        return ["--save", str(index), hex_text(host), hex_text("user"), "", "3389",
                hex_text(password), "75", "8", "portrait", "v2"]

    def test_ack_matches_token_action_revision_and_exact_private_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            first = self.read_operation(config)
            self.assertEqual(first["revision"], "absent")
            self.assertEqual(first["body"], "")
            token = "save-00000001"
            run = self.run_manager(config, "--request", token, "absent", *self.save_args(-1, "new", "fixture-password"))
            self.assertEqual(run.returncode, 0, run.stderr)
            result = self.operation_result(config, token)
            profiles = (config / "profiles").read_bytes()
            self.assertEqual(result["action"], "save")
            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["revision"], hashlib.sha256(profiles).hexdigest())
            self.assertEqual(result["body"].encode(), profiles)
            self.assertNotIn("fixture-password", run.stdout + run.stderr)
            self.assertEqual(stat.S_IMODE((config / "operations").stat().st_mode), 0o700)
            for path in (config / "operations").iterdir():
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertFalse(list(config.glob("*.tmp.*")))
            self.assertFalse(list(config.glob("*.read.*")))

    def test_stale_save_and_delete_do_not_modify_old_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            self.assertEqual(self.save(config, -1, "first", "user", "old-password").returncode, 0)
            old = self.read_operation(config)
            self.assertEqual(self.save(config, -1, "second", "user").returncode, 0)
            before = (config / "profiles").read_bytes()
            for number, args in enumerate([self.save_args(0, "wrong-row"), ["--delete", "0"]]):
                token = f"stale-0000000{number}"
                run = self.run_manager(config, "--request", token, old["revision"], *args)
                self.assertNotEqual(run.returncode, 0)
                result = self.operation_result(config, token)
                self.assertEqual((result["status"], result["code"]), ("error", "stale"))
                self.assertEqual(result["body"], "")
                self.assertEqual((config / "profiles").read_bytes(), before)

    def test_lock_error_correlated_retry_and_reused_token_are_independent(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            old = self.read_operation(config)
            lock = config / ".profile-manager.lock"
            lock.mkdir()
            token = "locked-000001"
            run = self.run_manager(config, "--request", token, old["revision"], *self.save_args(-1, "first"))
            self.assertEqual(run.returncode, 75)
            self.assertTrue(lock.is_dir(), "A refused operation must never remove another process lock")
            self.assertEqual(self.operation_result(config, token)["code"], "locked")
            lock.rmdir()
            new_token = "retry-0000001"
            run = self.run_manager(config, "--request", new_token, old["revision"], *self.save_args(-1, "first"))
            self.assertEqual(run.returncode, 0, run.stderr)
            before = (config / "profiles").read_bytes()
            result_before = (config / "operations" / (new_token + ".result")).read_bytes()
            reused = self.run_manager(config, "--request", new_token, old["revision"], *self.save_args(-1, "must-not-replay"))
            self.assertEqual(reused.returncode, 0)
            self.assertEqual((config / "profiles").read_bytes(), before)
            self.assertEqual((config / "operations" / (new_token + ".result")).read_bytes(), result_before)
            self.assertEqual(self.operation_result(config, token)["code"], "locked")

    def test_two_concurrent_requests_have_separate_results_and_only_one_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            self.assertEqual(self.save(config, -1, "original", "user").returncode, 0)
            revision = self.read_operation(config)["revision"]
            env = dict(os.environ, PAPERDESK_RDP_CONFIG_DIR=str(config))
            tokens = ["parallel-00001", "parallel-00002"]
            processes = [subprocess.Popen([str(MANAGER), "--request", token, revision,
                *self.save_args(0, f"winner-{i}")], env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE) for i, token in enumerate(tokens)]
            for process in processes:
                process.communicate(timeout=15)
            results = [self.operation_result(config, token) for token in tokens]
            self.assertEqual(sum(result["status"] == "ok" for result in results), 1)
            self.assertEqual(sum(result["code"] in ("locked", "stale") for result in results), 1)
            winner = next(i for i, result in enumerate(results) if result["status"] == "ok")
            self.assertIn(hex_text(f"winner-{winner}"), (config / "profiles").read_text())
            self.assertEqual(len((config / "profiles").read_text().splitlines()), 1)

    def test_precommit_write_failure_preserves_password_and_retry_can_opt_out(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            self.assertEqual(self.save(config, -1, "original", "user", "old-password").returncode, 0)
            revision = self.read_operation(config)["revision"]
            before = (config / "profiles").read_bytes()
            fake_bin = Path(directory) / "bin"
            fake_bin.mkdir()
            fake_mv = fake_bin / "mv"
            fake_mv.write_text('#!/bin/sh\ncase "$1" in */profiles.tmp.*) exit 1;; esac\nexec /bin/mv "$@"\n')
            fake_mv.chmod(0o700)
            run = self.run_manager(config, "--request", "write-failure01", revision, *self.save_args(0, "edited"),
                extra_env={"PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]})
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(self.operation_result(config, "write-failure01")["code"], "write")
            self.assertEqual((config / "profiles").read_bytes(), before)
            retry = self.run_manager(config, "--request", "write-retry001", revision, *self.save_args(0, "edited"))
            self.assertEqual(retry.returncode, 0, retry.stderr)
            self.assertEqual(self.operation_result(config, "write-retry001")["status"], "ok")
            self.assertNotIn(hex_text("old-password"), (config / "profiles").read_text())
            self.assertEqual((config / "profiles").read_text().split("\t")[5], "")

    def test_postcommit_read_failure_is_unknown_and_fresh_read_recovers(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            self.assertEqual(self.save(config, -1, "original", "user").returncode, 0)
            revision = self.read_operation(config)["revision"]
            fake_bin = Path(directory) / "bin"
            fake_bin.mkdir()
            fake_cp = fake_bin / "cp"
            counter = Path(directory) / "cp-counter"
            fake_cp.write_text('#!/bin/sh\nif [ -e "$PAPERDESK_TEST_CP_COUNTER" ]; then exit 1; fi\n'
                ': > "$PAPERDESK_TEST_CP_COUNTER"\nexec /bin/cp "$@"\n')
            fake_cp.chmod(0o700)
            run = self.run_manager(config, "--request", "read-failure001", revision, *self.save_args(0, "committed"),
                extra_env={"PATH": str(fake_bin) + os.pathsep + os.environ["PATH"], "PAPERDESK_TEST_CP_COUNTER": str(counter)})
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(self.operation_result(config, "read-failure001")["code"], "unknown")
            recovered = self.read_operation(config, "recovery-read001")
            self.assertIn(hex_text("committed"), recovered["body"])
            self.assertNotEqual(recovered["revision"], revision)

    def test_read_failure_and_corrupt_records_cannot_become_a_successful_empty_list(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            config.mkdir()
            profiles = config / "profiles"
            profiles.mkdir()
            run = self.run_manager(config, "--read", "bad-read-00001")
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(self.operation_result(config, "bad-read-00001")["code"], "read")
            profiles.rmdir()
            bad = "v1\tzz\t75736572\t\t3389\t\t75\t8\n" + "v1\t686f7374\t75736572\t\t3389\t\t75\t8\n"
            profiles.write_text(bad)
            run = self.run_manager(config, "--request", "bad-record0001", hashlib.sha256(bad.encode()).hexdigest(), "--delete", "0")
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(self.operation_result(config, "bad-record0001")["code"], "corrupt")
            self.assertEqual(profiles.read_text(), bad)

    def test_result_retention_is_bounded_and_tokens_cannot_escape_private_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "paperrdp"
            for number in range(20):
                self.read_operation(config, f"bounded-{number:08d}")
            results = list((config / "operations").glob("*.result"))
            self.assertLessEqual(len(results), 16)
            self.assertTrue((config / "operations" / "bounded-00000019.result").is_file())
            before = sorted(path.name for path in results)
            for token in ["../escape-token", "x" * 65, "UPPERCASE", "short"]:
                run = self.run_manager(config, "--read", token)
                self.assertNotEqual(run.returncode, 0)
            self.assertEqual(sorted(path.name for path in (config / "operations").glob("*.result")), before)
            self.assertFalse((Path(directory) / "escape-token.result").exists())


if __name__ == "__main__":
    unittest.main()
