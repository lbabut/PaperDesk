import os
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
    def run_manager(self, config: Path, *args: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env["PAPERDESK_RDP_CONFIG_DIR"] = str(config)
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


if __name__ == "__main__":
    unittest.main()
