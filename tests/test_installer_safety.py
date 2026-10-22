"""Fault-injected installer runs against a disposable filesystem, never a tablet."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPS = 'paperdesk literm paperweb paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks shims'.split()


class InstallerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.product = self.base / 'product'
        shutil.copytree(ROOT / 'product', self.product, symlinks=True)
        self.home = self.base / 'home/root'
        self.target = self.home / 'xovi/exthome/appload'
        for name in APPS:
            folder = self.target / name
            folder.mkdir(parents=True)
            (folder / 'old.txt').write_text('previous ' + name)
        extension = self.home / 'xovi/extensions.d/qt-resource-rebuilder.so'
        extension.parent.mkdir(parents=True)
        extension.write_text('fixture')
        self.state = self.home / '.local/share/paperdesk'
        self.state.mkdir(parents=True)
        (self.state / 'current-version').write_text('0.9.0\n')
        (self.base / 'etc/systemd/system').mkdir(parents=True)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.log = self.base / 'service-calls'
        for name in ('systemctl', 'systemd-run'):
            self.tool(name, 'printf "%s\\n" "$*" >> "$AUDIT_SERVICE_LOG"\nexit 0\n')
        self.tool('id', 'echo 0\n')
        # Force identical timestamps so the backup uniqueness test is meaningful.
        self.tool('date', 'echo 20261018-120000\n')
        self.tool('cp', 'if [ "${AUDIT_FAIL_STAGE:-0}" = 1 ] && [ "$1" = -R ] && '
                  '[ "$2" = "$AUDIT_PRODUCT/payload/apps/." ]; then exit 42; fi\n'
                  'exec ' + shlex.quote(shutil.which('cp')) + ' "$@"\n')
        self.tool('mv', 'if [ "${AUDIT_FAIL_RENAME:-0}" = 1 ]; then\n'
                  'case "$1" in */.paperdesk-install.*/literm) exit 43;; esac\nfi\n'
                  'if [ "${AUDIT_SIGNAL_RENAME:-0}" = 1 ]; then\n'
                  'case "$2" in */previous-literm) ' + shlex.quote(shutil.which('mv')) + ' "$@"; kill -TERM "$PPID"; exit 0;; esac\nfi\n'
                  'exec ' + shlex.quote(shutil.which('mv')) + ' "$@"\n')
        script = (ROOT / 'product/install.sh').read_text()
        script = script.replace('SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
                                'SCRIPT_DIR=' + shlex.quote(str(self.product)))
        script = script.replace('/home/root', str(self.home)).replace('/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        script = script.replace('/run/paperdesk-install.lock', str(self.base / 'install.lock'))
        self.script = self.base / 'run-install.sh'
        self.script.write_text(script)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        AUDIT_SERVICE_LOG=str(self.log), AUDIT_PRODUCT=str(self.product))

    def tool(self, name, script):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + script)
        path.chmod(0o700)

    def run_installer(self, **env):
        return subprocess.run(['sh', str(self.script)], env=dict(self.env, **env),
                              text=True, capture_output=True, timeout=20)

    def assert_previous_apps_untouched(self):
        for name in APPS:
            self.assertEqual((self.target / name / 'old.txt').read_text(), 'previous ' + name)

    def test_bad_checksum_is_rejected_before_any_service_or_app_write(self):
        (self.product / 'payload/apps/paperweb/ui/main.qml').write_text('corrupt')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_apps_untouched()
        self.assertFalse(self.log.exists())

    def test_failed_staging_copy_keeps_all_installed_apps(self):
        result = self.run_installer(AUDIT_FAIL_STAGE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_apps_untouched()
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
        self.assertFalse(self.log.exists())

    def test_failed_app_rename_restores_that_app_and_keeps_backup(self):
        result = self.run_installer(AUDIT_FAIL_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'literm/old.txt').read_text(), 'previous literm')
        backups = list((self.state / 'backups').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'apps/literm/old.txt').read_text(), 'previous literm')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')

    def test_successful_installs_keep_distinct_backups_at_the_same_timestamp(self):
        for _ in range(2):
            result = self.run_installer()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((self.state / 'backups').iterdir())), 2)
        self.assertEqual((self.state / 'current-version').read_text(), (self.product / 'VERSION').read_text())
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
        self.assertTrue((self.target / 'paperbooks/resources.rcc').is_file())

    def test_signal_during_rename_restores_the_displaced_app(self):
        result = self.run_installer(AUDIT_SIGNAL_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'literm/old.txt').read_text(), 'previous literm')
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
