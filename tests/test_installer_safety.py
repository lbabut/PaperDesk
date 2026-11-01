"""Fault-injected installer runs against a disposable filesystem, never a tablet."""
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APPS = 'paperdesk literm paperweb paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks papersketch shims'.split()


class InstallerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.product = self.base / 'product'
        shutil.copytree(ROOT / 'product', self.product, symlinks=True)
        # Unit fixtures verify the copied payload, independent of generated
        # release checksums while another agent is editing the source tree.
        checksum_paths = sorted(path for path in self.product.rglob('*')
                                if path.is_file() and path.name != 'SHA256SUMS')
        (self.product / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256(path.read_bytes()).hexdigest() + '  ./' +
            path.relative_to(self.product).as_posix() + '\n' for path in checksum_paths))
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
        self.os_release = self.base / 'etc/os-release'
        self.os_release.write_text('VERSION_ID="6.0.106"\nIMG_VERSION="3.29.0.149"\n')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.log = self.base / 'service-calls'
        for name in ('systemctl', 'systemd-run'):
            self.tool(name, 'printf "%s\\n" "$*" >> "$AUDIT_SERVICE_LOG"\nexit 0\n')
        self.tool('id', 'echo 0\n')
        self.tool('uname', 'echo armv7l\n')
        self.tool('mkdir', 'if [ "${AUDIT_FAIL_AFTER_NATIVE:-0}" = 1 ]; then\n'
                  'for arg in "$@"; do case "$arg" in */.local/share/paperdesk/sketch) exit 44;; esac; done\nfi\n'
                  'exec ' + shlex.quote(shutil.which('mkdir')) + ' "$@"\n')
        # Force identical timestamps so the backup uniqueness test is meaningful.
        self.tool('date', 'echo 20261018-120000\n')
        self.tool('cp', 'if [ "${AUDIT_FAIL_NATIVE_RESTORE:-0}" = 1 ]; then\n'
                  'for arg in "$@"; do case "$arg" in */.papersketch-uninstall.*) exit 47;; esac; done\nfi\n'
                  'if [ "${AUDIT_FAIL_NATIVE_STAGE:-0}" = 1 ]; then\n'
                  'case "$2" in */.papersketch-raster.*) exit 45;; esac\nfi\n'
                  'if [ "${AUDIT_FAIL_STAGE:-0}" = 1 ] && [ "$1" = -R ] && '
                  '[ "$2" = "$AUDIT_PRODUCT/payload/apps/." ]; then exit 42; fi\n'
                  'exec ' + shlex.quote(shutil.which('cp')) + ' "$@"\n')
        self.tool('mv', 'if [ "${AUDIT_FAIL_NATIVE_RENAME:-0}" = 1 ]; then\n'
                  'case "$1" in */.papersketch-raster.*) exit 46;; esac\nfi\n'
                  'if [ "${AUDIT_FAIL_RENAME:-0}" = 1 ]; then\n'
                  'case "$1" in */.paperdesk-install.*/literm) exit 43;; esac\nfi\n'
                  'if [ "${AUDIT_SIGNAL_RENAME:-0}" = 1 ]; then\n'
                  'case "$2" in */previous-literm) ' + shlex.quote(shutil.which('mv')) + ' "$@"; kill -TERM "$PPID"; exit 0;; esac\nfi\n'
                  'exec ' + shlex.quote(shutil.which('mv')) + ' "$@"\n')
        script = (ROOT / 'product/install.sh').read_text()
        script = script.replace('SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
                                'SCRIPT_DIR=' + shlex.quote(str(self.product)))
        script = script.replace('/home/root', str(self.home)).replace('/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        script = script.replace('/etc/os-release', str(self.os_release))
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

    def native_module(self):
        return self.home / 'xovi/extensions.d/papersketch-raster.so'

    def run_uninstaller(self, **env):
        script = (ROOT / 'product/uninstall.sh').read_text()
        script = script.replace('/home/root', str(self.home)).replace(
            '/etc/systemd/system', str(self.base / 'etc/systemd/system'))
        path = self.base / 'run-uninstall.sh'
        path.write_text(script)
        return subprocess.run(['sh', str(path)], env=dict(self.env, **env), text=True,
                              capture_output=True, timeout=20)

    def test_unlisted_firmware_is_rejected_before_any_service_or_app_write(self):
        self.os_release.write_text('VERSION_ID="6.0.106"\nIMG_VERSION="3.30.0.1"\n')
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('3.29.0.149 or 3.29.0.153', result.stderr)
        self.assert_previous_apps_untouched()
        self.assertFalse(self.log.exists())
        self.assertFalse(self.native_module().exists())

    def test_img_version_accepts_the_separately_validated_sketch_firmware(self):
        self.os_release.write_text('VERSION_ID="6.0.106"\nIMG_VERSION="3.29.0.153"\n')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.native_module().read_bytes(),
                         (self.product / 'payload/apps/papersketch/native/papersketch-raster.so').read_bytes())
        self.assertFalse((self.native_module().parent / 'papersketch-ink.so').exists())

    def test_failure_after_native_rename_restores_existing_renderer(self):
        self.native_module().write_bytes(b'previous-renderer')
        result = self.run_installer(AUDIT_FAIL_AFTER_NATIVE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.native_module().read_bytes(), b'previous-renderer')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')
        self.assertEqual(list(self.native_module().parent.glob('.papersketch-raster.*')), [])

    def test_failure_after_native_rename_removes_a_new_renderer(self):
        result = self.run_installer(AUDIT_FAIL_AFTER_NATIVE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.native_module().exists())

    def test_v3_upgrade_preserves_development_sketch_and_original_module(self):
        (self.state / 'original-recorded').touch()
        self.native_module().write_bytes(b'original-development-renderer')
        data = self.state / 'sketch'
        data.mkdir()
        (data / 'artwork.material').write_bytes(b'user-artwork')
        for _ in range(2):
            result = self.run_installer()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_uninstaller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.native_module().read_bytes(), b'original-development-renderer')
        self.assertEqual((self.target / 'papersketch/old.txt').read_text(), 'previous papersketch')
        self.assertEqual((data / 'artwork.material').read_bytes(), b'user-artwork')

    def test_uninstall_removes_new_renderer_and_keeps_artwork(self):
        data = self.state / 'sketch'
        data.mkdir()
        (data / 'artwork.material').write_bytes(b'user-artwork')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_uninstaller()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.native_module().exists())
        self.assertEqual((data / 'artwork.material').read_bytes(), b'user-artwork')

    def test_failed_native_staging_keeps_apps_renderer_and_services_untouched(self):
        self.native_module().write_bytes(b'previous-renderer')
        result = self.run_installer(AUDIT_FAIL_NATIVE_STAGE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_apps_untouched()
        self.assertEqual(self.native_module().read_bytes(), b'previous-renderer')
        self.assertFalse(self.log.exists())
        self.assertEqual(list(self.native_module().parent.glob('.papersketch-raster.*')), [])

    def test_failed_native_rename_preserves_previous_renderer(self):
        self.native_module().write_bytes(b'previous-renderer')
        result = self.run_installer(AUDIT_FAIL_NATIVE_RENAME='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.native_module().read_bytes(), b'previous-renderer')
        self.assertEqual((self.state / 'current-version').read_text(), '0.9.0\n')
        self.assertEqual(list(self.native_module().parent.glob('.papersketch-raster.*')), [])

    def test_failed_uninstall_restore_keeps_the_complete_installed_renderer(self):
        self.native_module().write_bytes(b'original-development-renderer')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = self.native_module().read_bytes()
        result = self.run_uninstaller(AUDIT_FAIL_NATIVE_RESTORE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.native_module().read_bytes(), installed)
        self.assertEqual((self.state / 'original/system/papersketch-raster.so').read_bytes(),
                         b'original-development-renderer')
        self.assertEqual(list(self.native_module().parent.glob('.papersketch-uninstall.*')), [])
