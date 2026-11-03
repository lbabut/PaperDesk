"""Fault-injected installer runs against a disposable filesystem, never a tablet."""
import os
import hashlib
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPS = 'paperdesk paperterminal literm paperweb paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks papersketch shims'.split()


class InstallerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.product = self.base / 'product'
        shutil.copytree(ROOT / 'product', self.product, symlinks=True)
        # These tests exercise file installation and rollback. A small test-only
        # native payload keeps them independent of the cross-compiler output.
        native = self.product / 'payload/apps/paperterminal/native'
        native.mkdir(parents=True, exist_ok=True)
        (native / 'qmldir').write_text('module PaperTerminalNative\nplugin paperterminal_native\n')
        (native / 'libpaperterminal_native.so').write_bytes(b'installer fixture')
        (native / 'paperterminal-askpass').write_bytes(b'installer fixture')
        self.refresh_checksums()
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
        self.tool('uname', 'echo armv7l\n')
        os_release = self.base / 'etc/os-release'
        os_release.write_text('IMG_VERSION=3.29.0.153\n')
        # Force identical timestamps so the backup uniqueness test is meaningful.
        self.tool('date', 'echo 20261018-120000\n')
        self.tool('cp', 'if [ "${AUDIT_FAIL_STAGE:-0}" = 1 ] && [ "$1" = -R ] && '
                  '[ "$2" = "$AUDIT_PRODUCT/payload/apps/." ]; then exit 42; fi\n'
                  'exec ' + shlex.quote(shutil.which('cp')) + ' "$@"\n')
        self.tool('mv', 'if [ "${AUDIT_FAIL_RENAME:-0}" = 1 ]; then\n'
                  'case "$1" in */.paperdesk-install.*/paperterminal) exit 43;; esac\nfi\n'
                  'if [ "${AUDIT_SIGNAL_RENAME:-0}" = 1 ]; then\n'
                  'case "$2" in */previous-paperterminal) ' + shlex.quote(shutil.which('mv')) + ' "$@"; kill -TERM "$PPID"; exit 0;; esac\nfi\n'
                  'if [ "${AUDIT_SIGNAL_RETIRE:-0}" = 1 ]; then\n'
                  'case "$2" in */legacy-literm) ' + shlex.quote(shutil.which('mv')) + ' "$@"; kill -TERM "$PPID"; exit 0;; esac\nfi\n'
                  'if [ "${AUDIT_FAIL_RETIRE:-0}" = 1 ]; then\n'
                  'case "$2" in */legacy-literm) exit 44;; esac\nfi\n'
                  'exec ' + shlex.quote(shutil.which('mv')) + ' "$@"\n')
        self.tool('mv', 'case "$1" in */.papersketch-ink.*)\n'
                  'if [ "${AUDIT_FAIL_INK_RENAME:-0}" = 1 ]; then exit 45; fi\n'
                  'if [ "${AUDIT_SIGNAL_INK_RENAME:-0}" = 1 ]; then ' + shlex.quote(shutil.which('mv')) +
                  ' "$@"; kill -TERM "$PPID"; exit 0; fi;; esac\n'
                  + (self.bin / 'mv').read_text().removeprefix('#!/bin/sh\n'))
        script = (ROOT / 'product/install.sh').read_text()
        script = script.replace('SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
                                'SCRIPT_DIR=' + shlex.quote(str(self.product)))
        script = script.replace('/home/root', str(self.home)).replace('/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        script = script.replace('/etc/os-release', str(self.base / 'etc/os-release'))
        script = script.replace('/run/paperdesk-install.lock', str(self.base / 'install.lock'))
        self.script = self.base / 'run-install.sh'
        self.script.write_text(script)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        AUDIT_SERVICE_LOG=str(self.log), AUDIT_PRODUCT=str(self.product))

    def refresh_checksums(self):
        manifest = self.product / 'SHA256SUMS'
        files = sorted(p for p in self.product.rglob('*') if p.is_file() and p != manifest)
        manifest.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ./'+
                                   p.relative_to(self.product).as_posix() + '\n' for p in files))

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

    def test_preview_payload_required_before_installation(self):
        (self.product / 'payload/apps/papersketch/native/papersketch-ink.so').unlink()
        self.refresh_checksums()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing Paper Sketch fast pen preview', result.stderr)
        self.assert_previous_apps_untouched()
        self.assertFalse(self.log.exists())

    def previous_modules(self):
        extensions = self.home / 'xovi/extensions.d'
        for name in ['papersketch-raster.so', 'papersketch-ink.so']:
            (extensions / name).write_bytes(('previous ' + name).encode())
        return extensions

    def assert_modules_restored(self, extensions):
        for name in ['papersketch-raster.so', 'papersketch-ink.so']:
            self.assertEqual((extensions / name).read_bytes(), ('previous ' + name).encode())
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')
        self.assertEqual(list(extensions.glob('.papersketch*')), [])

    def test_preview_install_failure_restores_both_previous_modules(self):
        extensions = self.previous_modules()
        result = self.run_installer(AUDIT_FAIL_INK_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_modules_restored(extensions)

    def test_signal_after_preview_replacement_restores_both_modules(self):
        extensions = self.previous_modules()
        result = self.run_installer(AUDIT_SIGNAL_INK_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_modules_restored(extensions)

    def test_preview_install_failure_removes_new_modules_when_none_existed(self):
        result = self.run_installer(AUDIT_FAIL_INK_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        extensions = self.home / 'xovi/extensions.d'
        self.assertFalse((extensions / 'papersketch-ink.so').exists())
        self.assertFalse((extensions / 'papersketch-raster.so').exists())

    def test_managed_preview_installs_and_uninstalls_to_original_after_upgrades(self):
        extensions = self.previous_modules()
        for _ in range(2):
            result = self.run_installer()
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in ['papersketch-raster.so', 'papersketch-ink.so']:
                self.assertEqual((extensions / name).read_bytes(),
                    (self.product / 'payload/apps/papersketch/native' / name).read_bytes())
        script = (ROOT / 'product/uninstall.sh').read_text().replace('/home/root', str(self.home)).replace(
            '/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        result = subprocess.run(['sh', '-c', script], env=self.env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ['papersketch-raster.so', 'papersketch-ink.so']:
            self.assertEqual((extensions / name).read_bytes(), ('previous ' + name).encode())

    def test_bad_checksum_is_rejected_before_any_service_or_app_write(self):
        (self.product / 'payload/apps/paperweb/ui/main.qml').write_text('corrupt')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_apps_untouched()
        self.assertFalse(self.log.exists())

    def test_incomplete_terminal_plugin_is_rejected_before_writes(self):
        for name in ['qmldir', 'libpaperterminal_native.so', 'paperterminal-askpass']:
            path = self.product / 'payload/apps/paperterminal/native' / name
            original = path.read_bytes()
            path.unlink()
            self.refresh_checksums()
            result = self.run_installer()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('missing Paper Terminal', result.stderr)
            self.assert_previous_apps_untouched()
            self.assertFalse(self.log.exists())
            self.assertFalse((self.state / 'backups').exists())
            path.write_bytes(original)
        self.refresh_checksums()

    def test_failed_staging_copy_keeps_all_installed_apps(self):
        result = self.run_installer(AUDIT_FAIL_STAGE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_apps_untouched()
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
        self.assertFalse(self.log.exists())

    def test_failed_app_rename_restores_that_app_and_keeps_backup(self):
        result = self.run_installer(AUDIT_FAIL_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'paperterminal/old.txt').read_text(), 'previous paperterminal')
        backups = list((self.state / 'backups').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'apps/paperterminal/old.txt').read_text(), 'previous paperterminal')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')

    def test_successful_installs_keep_distinct_backups_at_the_same_timestamp(self):
        for _ in range(2):
            result = self.run_installer()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((self.state / 'backups').iterdir())), 2)
        self.assertEqual((self.state / 'current-version').read_text(), (self.product / 'VERSION').read_text())
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
        self.assertTrue((self.target / 'paperbooks/resources.rcc').is_file())

    def test_upgrade_retires_legacy_frontend_and_keeps_all_connection_data(self):
        settings = self.home / '.config/literm/settings.ini'
        settings.parent.mkdir(parents=True)
        settings.write_text('user settings')
        profiles = self.home / '.config/rmssh/profiles'
        profiles.parent.mkdir(parents=True)
        profiles.write_text('saved profiles')
        hosts = profiles.with_name('hosts')
        hosts.write_text('saved aliases')
        extension = self.home / 'xovi/extensions.d/literm.so'
        extension.write_text('separate user backend')
        profile = self.home / '.profile'
        profile.write_text('export KEEP=1\n# RMSSH-BEGIN\nold menu hook\n# RMSSH-END\n')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.target / 'literm').exists())
        self.assertTrue((self.target / 'paperterminal/native/libpaperterminal_native.so').exists())
        self.assertEqual(settings.read_text(), 'user settings')
        self.assertEqual(profiles.read_text(), 'saved profiles')
        self.assertEqual(hosts.read_text(), 'saved aliases')
        self.assertEqual(extension.read_text(), 'separate user backend')
        self.assertEqual(profile.read_text(), 'export KEEP=1\n')
        backup = Path((self.state / 'last-backup').read_text().strip())
        self.assertEqual((backup / 'apps/literm/old.txt').read_text(), 'previous literm')
        self.assertEqual((backup / 'system/literm-settings.ini').read_text(), 'user settings')
        self.assertEqual((backup / 'system/rmssh-profiles').read_text(), 'saved profiles')
        self.assertEqual((backup / 'system/rmssh-hosts').read_text(), 'saved aliases')

    def test_failed_retirement_keeps_legacy_app_and_previous_version_marker(self):
        result = self.run_installer(AUDIT_FAIL_RETIRE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'literm/old.txt').read_text(), 'previous literm')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])

    def test_signal_during_legacy_retirement_restores_the_old_frontend(self):
        result = self.run_installer(AUDIT_SIGNAL_RETIRE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'literm/old.txt').read_text(), 'previous literm')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])

    def test_uninstall_restores_original_legacy_app_without_replacing_a_user_app(self):
        original = self.state / 'original/apps/literm'
        original.mkdir(parents=True)
        (original / 'original.txt').write_text('pre-PaperDesk terminal')
        (self.state / 'original-recorded').touch()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        script = (ROOT / 'product/uninstall.sh').read_text()
        script = script.replace('/home/root', str(self.home)).replace('/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        for user_app in (False, True):
            if user_app:
                shutil.rmtree(self.target / 'literm')
                (self.target / 'literm').mkdir()
                (self.target / 'literm/user.txt').write_text('installed separately')
            result = subprocess.run(['sh', '-c', script], env=self.env,
                                    text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((self.target / 'paperterminal').exists())
            if user_app:
                self.assertEqual((self.target / 'literm/user.txt').read_text(), 'installed separately')
                self.assertFalse((self.target / 'literm/original.txt').exists())
            else:
                self.assertEqual((self.target / 'literm/original.txt').read_text(), 'pre-PaperDesk terminal')

    def test_signal_during_rename_restores_the_displaced_app(self):
        result = self.run_installer(AUDIT_SIGNAL_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.target / 'paperterminal/old.txt').read_text(), 'previous paperterminal')
        self.assertEqual(list(self.target.glob('.paperdesk-install.*')), [])
