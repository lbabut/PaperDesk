import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_tablet as prep


@unittest.skipUnless(os.name == 'posix', 'POSIX preparation fixture requires Linux')
class PreparationShellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home/root'
        for folder in ['home/root','etc/systemd/system','run/systemd/system','sys/devices/soc0','proc/123','tmp','bin']:
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        (self.root / 'sys/devices/soc0/machine').write_text('reMarkable 2.0\n')
        (self.root / 'etc/os-release').write_text('VERSION_ID="3.29.0.149"\n')
        (self.root / 'proc/123/maps').write_text('\n'.join('/home/root/xovi/' + n for n in ['xovi.so','qt-resource-rebuilder.so','appload.so','literm.so']))
        self.bin = self.root / 'bin'
        tools = 'sh bash id cat uname tar gzip sha256sum systemctl systemd-run cp rm mkdir chmod grep sed date mv touch df du awk wget openssl unzip flock wc tr mktemp find readlink timeout pidof kill ln mount umount sleep dirname basename'.split()
        for tool in tools:
            (self.bin / tool).symlink_to(shutil.which(tool) or '/bin/true')
        for tool, body in {
            'id':'echo 0', 'uname':'echo armv7l', 'openssl':'echo ED25519',
            'df':"printf 'Filesystem blocks Used Available Capacity Mounted\\nfixture 900000 1 899999 1%% /\\n'",
            'systemctl':'case "$1" in show) echo 123;; *) exit 0;; esac',
            'systemd-run':'echo Watchdog armed', 'umount':'exit 0', 'sleep':'exit 0',
        }.items():
            self.fake(tool, body)
        self.stage = self.home / ('paperdesk-prepare-' + 'a' * 32)
        self.stage.mkdir()
        self.files = {name: b'fixture' for name in prep.REQUIRED_FILES}
        self.files['xovi/start'] = b'#!/bin/sh\nexit 0\n'
        self.files['xovi/stock'] = b'#!/bin/sh\nexit 0\n'
        self.files['xovi/rebuild_hashtable'] = b'#!/bin/sh\nmkdir -p /home/root/xovi/exthome/qt-resource-rebuilder\necho fixture > /home/root/xovi/exthome/qt-resource-rebuilder/hashtab\n'
        # The production script compares the fixture bytes actually placed on disk.
        self.files = {name: self.rewrite(data.decode()).encode() for name, data in self.files.items()}
        for name, data in self.files.items():
            p = self.stage / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
            p.chmod(0o755 if name in ['xovi/start','xovi/stock','xovi/rebuild_hashtable'] else 0o644)
        (self.stage / 'xovi/exthome/appload').mkdir(parents=True)
        (self.stage / 'restore.sh').write_text(self.rewrite(prep.RESTORE_SCRIPT))
        self.backup = self.home / '.local/share/paperdesk-preparation' / ('a' * 32)

    def fake(self, tool, body):
        p = self.bin / tool
        p.unlink()
        p.write_text('#!/bin/sh\n' + body + '\n')
        p.chmod(0o755)

    def rewrite(self, text):
        # Match absolute tablet paths, not suffixes of an existing fixture path.
        for original, replacement in [('/home/root', str(self.home)), ('/etc/',str(self.root)+'/etc/'),
                                      ('/run/',str(self.root)+'/run/'), ('/sys/',str(self.root)+'/sys/'),
                                      ('/proc/',str(self.root)+'/proc/'), ('/tmp/xovi-hashtab',str(self.root)+'/tmp/xovi-hashtab')]:
            text = re.sub(r'(?<![A-Za-z0-9_/])' + re.escape(original), lambda match: replacement, text)
        return text

    def run_script(self, text):
        return subprocess.run(['/bin/sh','-c',self.rewrite(text)], env={'PATH':str(self.bin)}, capture_output=True, text=True, timeout=10)

    def prepare(self):
        return self.run_script(prep.preparation_script('/home/root/' + self.stage.name, self.files))

    def test_fresh_preparation_commits_and_watchdog_does_not_undo_it(self):
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.backup / 'committed').is_file())
        result = self.run_script('/bin/sh ' + str(self.backup / 'restore.sh'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / 'xovi/extensions.d/literm.so').is_file())

    def test_rebuild_failure_rolls_back_fresh_tablet(self):
        p = self.stage / 'xovi/rebuild_hashtable'
        p.write_text('#!/bin/sh\nexit 1\n')
        self.files['xovi/rebuild_hashtable'] = p.read_bytes()
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / 'xovi').exists())
        self.assertTrue((self.backup / 'restored').is_file())
        self.assertTrue(list(self.backup.glob('failed-xovi-*')))

    def test_failure_restores_existing_tree_and_app_data(self):
        xovi = self.home / 'xovi'
        xovi.mkdir()
        (xovi / 'existing-app-data').write_text('keep me')
        self.fake('systemctl', 'case "$1" in is-active) case "$3" in *.timer) exit 0;; *) exit 1;; esac;; show) echo 123;; *) exit 0;; esac')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((xovi / 'existing-app-data').read_text(), 'keep me')
        self.assertFalse((xovi / 'extensions.d').exists())
        self.assertTrue((self.backup / 'restored').is_file())

    def test_wrong_os_and_model_are_rejected_without_writes(self):
        for target, value in [('etc/os-release','VERSION_ID=3.30.0.1\n'),('sys/devices/soc0/machine','reMarkable 1.0\n')]:
            p = self.root / target
            original = p.read_text()
            p.write_text(value)
            result = self.run_script(prep.eligibility_script())
            self.assertEqual(result.returncode, 22, result.stdout + result.stderr)
            self.assertFalse((self.home / 'xovi').exists())
            self.assertFalse(self.backup.exists())
            p.write_text(original)

    def test_incompatible_existing_dependency_is_never_overwritten(self):
        p = self.home / 'xovi/extensions.d/literm.so'
        p.parent.mkdir(parents=True)
        p.write_text('custom backend')
        result = self.prepare()
        self.assertEqual(result.returncode, 22, result.stdout + result.stderr)
        self.assertEqual(p.read_text(), 'custom backend')
        self.assertFalse(self.backup.exists())

    def test_unknown_extension_is_rejected_without_changing_it(self):
        p = self.home / 'xovi/extensions.d/custom.so'
        p.parent.mkdir(parents=True)
        p.write_text('custom')
        result = self.prepare()
        self.assertEqual(result.returncode,22, result.stdout + result.stderr)
        self.assertEqual(p.read_text(),'custom')

    def test_watchdog_failure_does_not_change_existing_xovi(self):
        xovi = self.home / 'xovi'
        xovi.mkdir()
        (xovi / 'data').write_text('original')
        self.fake('systemd-run', 'exit 1')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((xovi / 'data').read_text(), 'original')
        self.assertFalse((xovi / 'extensions.d').exists())

    def test_recovery_script_restores_interrupted_uncommitted_preparation(self):
        self.backup.mkdir(parents=True)
        (self.backup / 'restore.sh').write_text(self.rewrite(prep.RESTORE_SCRIPT))
        xovi = self.home / 'xovi'
        xovi.mkdir()
        (xovi / 'stock').write_text('#!/bin/sh\nexit 0\n')
        (xovi / 'stock').chmod(0o755)
        result = self.run_script('/bin/sh ' + str(self.backup / 'restore.sh'))
        self.assertEqual(result.returncode,0,result.stdout + result.stderr)
        self.assertFalse(xovi.exists())
        self.assertTrue((self.backup / 'restored').exists())
        result = self.run_script('/bin/sh ' + str(self.backup / 'restore.sh'))
        self.assertEqual(result.returncode,0,result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
