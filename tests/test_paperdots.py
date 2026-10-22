import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DotsRulesTests(unittest.TestCase):
    def test_rules_tactics_replay_and_bounded_ai(self):
        node = shutil.which("node") or shutil.which("nodejs")
        self.assertIsNotNone(node, "Node.js is required to exercise the pure JavaScript game engine")
        result = subprocess.run(
            [node, str(ROOT / "tests/paperdots-engine.cjs")],
            capture_output=True, text=True, timeout=40,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("18 engine scenarios passed", result.stdout)
