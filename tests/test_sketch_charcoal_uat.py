"""Fault-injected UAT deployment checks: never connect to a device."""
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/install-sketch-charcoal-uat.py'
OLD = {'papersketch-raster.so': 'e84e1271f9398200a789355562a682244c247cc1662f501cd1d7bcfd29481d9a',
       'papersketch-ink.so': '2643b947f47a4b3cb27b241fe0da6f4f5b8f89db6da70374cc902a2c17e14bc5'}

class UatSafety(unittest.TestCase):
    def exercise(self, confirmed=True, mismatch=False, fail_install=False, baseline='original'):
        self.calls = []
        self.failed = False
        self.installed = set()
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / 'receipt.json'
            argv = [str(SCRIPT), '--key', 'test-key', '--known-hosts', 'test-hosts', '--output', str(out)]
            argv += ['--baseline', baseline]
            before = OLD if baseline == 'original' else {
                'papersketch-raster.so': '227dd2ffedc7c1f867080d08ace59c40f545c09c333efd60537b4c8120f3e975',
                'papersketch-ink.so': '5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7'}
            if confirmed:
                argv.append('--safe-state-confirmed')
            def fake(args, **kwargs):
                self.calls.append(args[-1])
                self.assertEqual(args[:3], ['ssh', '-F', '/dev/null'])
                self.assertIn('StrictHostKeyChecking=yes', args)
                cmd = args[-1]
                data = b''
                if cmd.startswith('sha256sum '):
                    name = cmd.rsplit('/', 1)[1]
                    value = hashlib.sha256((ROOT / 'product/payload/apps/papersketch/native' / name).read_bytes()).hexdigest() if name in self.installed else before[name]
                    data = ((('0' * 64) if mismatch else value) + '  module\n').encode()
                elif cmd.startswith('mktemp '):
                    data = b'/home/root/.local/state/sketch-charcoal-uat.TEST01\n'
                elif cmd.startswith('systemctl is-enabled'):
                    data = b'static\n'
                elif '.uat-new; mv ' in cmd:
                    if fail_install and not self.failed:
                        self.failed = True
                        raise subprocess.CalledProcessError(1, args)
                    self.installed.add(cmd.rsplit('/', 1)[1])
                return subprocess.CompletedProcess(args, 0, stdout=data, stderr=b'')
            error = None
            with patch.object(sys, 'argv', argv), patch('subprocess.run', side_effect=fake), patch('time.sleep'):
                try:
                    runpy.run_path(str(SCRIPT), run_name='__main__')
                except (RuntimeError, SystemExit, subprocess.CalledProcessError) as e:
                    error = e
            return error, json.loads(out.read_text()) if out.exists() else None

    def test_requires_restart_consent_before_ssh(self):
        error, receipt = self.exercise(confirmed=False)
        self.assertIsInstance(error, SystemExit)
        self.assertEqual(self.calls, [])
        self.assertIsNone(receipt)

    def test_baseline_mismatch_never_stops_ui(self):
        error, receipt = self.exercise(mismatch=True)
        self.assertIsInstance(error, RuntimeError)
        self.assertFalse(any('stop xochitl' in c or c.startswith('mktemp') for c in self.calls))
        self.assertIsNone(receipt)

    def test_success_verifies_hashes_and_retains_recovery(self):
        error, receipt = self.exercise()
        self.assertIsNone(error)
        self.assertEqual(receipt['status'], 'installed_for_uat')
        self.assertEqual(len(self.installed), 2)
        self.assertTrue(any('/rollback.sh' in c and c.startswith('tee ') for c in self.calls))
        self.assertTrue(any('unmask --runtime' in c for c in self.calls))
        self.assertFalse(any('xochitl.conf' in c or 'Documents' in c or 'rm -' in c for c in self.calls))

    def test_failure_rolls_back_and_unmasks(self):
        error, receipt = self.exercise(fail_install=True)
        self.assertIsInstance(error, subprocess.CalledProcessError)
        self.assertEqual(receipt['status'], 'rolled_back')
        self.assertTrue(any(c.startswith('sh ') and c.endswith('/rollback.sh') for c in self.calls))
        self.assertTrue(any('unmask --runtime' in c for c in self.calls))

    def test_upgrade_from_pinned_charcoal_uat(self):
        error, receipt = self.exercise(baseline='charcoal-20261121')
        self.assertIsNone(error)
        self.assertEqual(receipt['status'], 'installed_for_uat')
        self.assertEqual(receipt['baseline_sha256']['papersketch-raster.so'],
                         '227dd2ffedc7c1f867080d08ace59c40f545c09c333efd60537b4c8120f3e975')

if __name__ == '__main__':
    unittest.main()
