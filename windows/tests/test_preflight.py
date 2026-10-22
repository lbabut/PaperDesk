from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import preflight


class WindowsPreflightTests(unittest.TestCase):
    def test_rejects_non_windows(self):
        with patch.object(preflight.sys, 'platform', 'linux'):
            with self.assertRaisesRegex(RuntimeError, 'Windows'):
                preflight.check_windows()

    @unittest.skipUnless(sys.platform == 'win32', 'Windows host required')
    def test_rejects_low_disk_space_before_tablet_connection(self):
        with patch.object(preflight.shutil, 'disk_usage', return_value=type('Usage', (), {'free':0})()):
            with self.assertRaisesRegex(RuntimeError, '64 MB'):
                preflight.check_windows()

    @unittest.skipUnless(sys.platform == 'win32', 'Windows host required')
    def test_rejects_32_bit_runtime(self):
        with patch.object(preflight.struct, 'calcsize', return_value=4):
            with self.assertRaisesRegex(RuntimeError, '64-bit'):
                preflight.check_windows()


@unittest.skipUnless(os.name == 'posix', 'POSIX shell fixture is run on Nostalgiczny')
class TabletShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.product = self.root / 'product'
        self.product.mkdir()
        self.home = self.root / 'home/root'
        for folder in ['xovi/extensions.d', 'xovi/exthome/appload', '.local/share/paperdesk']:
            (self.home / folder).mkdir(parents=True, exist_ok=True)
        for name in ['appload.so', 'literm.so', 'qt-resource-rebuilder.so']:
            (self.home / 'xovi/extensions.d' / name).write_text('fixture')
        (self.home / 'xovi/start').write_text('#!/bin/sh\nexit 0\n')
        (self.home / 'xovi/start').chmod(0o755)
        (self.root / 'etc/systemd/system').mkdir(parents=True)
        (self.root / 'run/systemd/system').mkdir(parents=True)
        (self.root / 'etc/os-release').write_text('VERSION_ID=3.29.0.149\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        tools = 'sh id cat uname tar gzip sha256sum systemctl systemd-run cp rm mkdir chmod grep sed date mv touch df du awk wget openssl unzip flock wc tr mktemp'.split()
        for tool in tools:
            (self.bin / tool).symlink_to(shutil.which(tool) or '/bin/true')
        for tool, output in [('uname','armv7l'), ('id','0'), ('df','Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 900000 1 899999 1% /'), ('openssl','ED25519')]:
            (self.bin / tool).unlink()
            (self.bin / tool).write_text('#!/bin/sh\nprintf "%b\\n" '+repr(output)+'\n')
            (self.bin / tool).chmod(0o755)
        self.script = preflight.tablet_check(self.product).replace('/home/root', str(self.home)).replace('/etc/',str(self.root)+'/etc/').replace('/run/',str(self.root)+'/run/')

    def run_check(self):
        return subprocess.run(['/bin/sh','-c',self.script], env={'PATH':str(self.bin)},capture_output=True,text=True)

    def test_all_requirements_pass_and_no_files_changed(self):
        before = sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob('*'))
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Tablet requirements: OK', result.stdout)
        self.assertEqual(before, sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob('*')))

    def test_missing_backend_is_reported(self):
        for backend in ['literm.so','appload.so','qt-resource-rebuilder.so']:
            path = self.home / 'xovi/extensions.d' / backend
            data = path.read_bytes(); path.unlink()
            result = self.run_check()
            self.assertEqual(result.returncode, 22)
            self.assertIn('Missing requirement:',result.stdout)
            path.write_bytes(data)

    def test_missing_tool_is_reported(self):
        (self.bin / 'tar').unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 22)
        self.assertIn('tool tar',result.stdout)

    def test_low_space_is_reported(self):
        (self.bin / 'df').write_text('#!/bin/sh\nprintf "Filesystem blocks Used Available Capacity Mounted\\nfixture 100 99 1 99%% /\\n"\n')
        result = self.run_check()
        self.assertEqual(result.returncode, 22)
        self.assertIn('free space',result.stdout)

    def test_unsupported_architecture_is_reported(self):
        (self.bin / 'uname').write_text('#!/bin/sh\necho aarch64\n')
        result = self.run_check()
        self.assertEqual(result.returncode,22)
        self.assertIn('ARMv7',result.stdout)

    def test_crypto_without_ed25519_is_reported(self):
        (self.bin / 'openssl').write_text('#!/bin/sh\necho RSA\n')
        result = self.run_check()
        self.assertEqual(result.returncode,22)
        self.assertIn('Ed25519',result.stdout)


if __name__ == '__main__':
    unittest.main()
