"""Manual assistant safety tests. Uses disposable files and a fake SSH endpoint."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'windows'))
from manual_wizard import compatibility_script, prepare_session, steps

ROOT = Path(__file__).resolve().parents[1]


class ManualWizardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="paperdesk-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.product = self.base / 'product'
        self.product.mkdir()
        files = {
            'VERSION': b'1.2.3\n',
            'release.json': json.dumps(dict(version='1.2.3', testedWith=dict(
                remarkableOS='3.29.0.149', xovi='0.3.3'))).encode(),
            'install.sh': b'#!/bin/sh\nexit 0\n'
        }
        for name, data in files.items():
            (self.product / name).write_bytes(data)
        (self.product / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256(data).hexdigest() + '  ' + name + '\n' for name, data in files.items()))

    def test_corrupt_package_creates_no_session(self):
        before = set(self.base.iterdir())
        (self.product / 'install.sh').write_text('corrupt')
        with self.assertRaises(ValueError):
            prepare_session(self.product, self.base)
        self.assertEqual(set(self.base.iterdir()), before)

    def test_sessions_are_unique_and_archive_digest_matches(self):
        first = prepare_session(self.product, self.base)
        second = prepare_session(self.product, self.base)
        self.assertNotEqual(first['folder'], second['folder'])
        self.assertNotEqual(first['token'], second['token'])
        self.assertEqual(hashlib.sha256((first['folder'] / 'paperdesk-tablet.tar.gz').read_bytes()).hexdigest(),
                         first['digest'])
        self.assertEqual((first['folder'] / 'check-tablet.sh').read_text(),
                         compatibility_script(self.product))

    def test_rejects_ssh_options_and_shell_injection(self):
        session = prepare_session(self.product, self.base)
        for host in ('-oProxyCommand=evil', 'a;touch pwn', 'root@host', 'host\nwhoami',
                     'host:22', 'a$(id)', "a'b", ''):
            with self.subTest(host=host), self.assertRaises(ValueError):
                steps(session, host)

    def test_both_platform_plans_keep_operations_separate(self):
        session = prepare_session(self.product, self.base)
        for windows in (False, True):
            plan = steps(session, '10.11.99.1', windows)
            self.assertEqual(len(plan), 5)
            self.assertIn('PAPERDESK_COMPATIBILITY_OK', plan[0][1])
            self.assertNotIn('install.sh', plan[0][2])
            self.assertIn('backup.sha256', plan[1][2])
            self.assertIn('ComputeHash' if windows else 'sha256sum -c backup.sha256', plan[1][2])
            self.assertIn('sha256sum -c SHA256SUMS', plan[2][2])
            self.assertNotIn('/xovi/start', plan[3][2])
            self.assertIn('/xovi/start', plan[4][2])
            for _, _, commands, acknowledgement in plan:
                self.assertTrue(acknowledgement)
                for forbidden in ('systemctl enable', 'rm -rf', 'curl ', 'wget ', 'license', 'payment'):
                    self.assertNotIn(forbidden, commands)

    @unittest.skipUnless(os.name == 'posix', 'POSIX shell integration')
    def test_paths_with_quotes_and_spaces_reach_ssh_as_literal_arguments(self):
        destination = self.base / "user's folder"
        destination.mkdir()
        session = prepare_session(self.product, destination)
        commands = steps(session, 'tablet.local')[0][2]
        executable = self.base / 'ssh'
        audit = self.base / 'received'
        executable.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$AUDIT"\ncat > "$AUDIT.stdin"\n')
        executable.chmod(0o700)
        result = subprocess.run(['sh', '-c', commands], capture_output=True, text=True,
                                env=dict(os.environ, PATH=str(self.base) + ':' + os.environ['PATH'],
                                         AUDIT=str(audit)), timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(audit.read_text().splitlines()[-2:], ['root@tablet.local', 'sh -s'])
        self.assertEqual(Path(str(audit) + '.stdin').read_text(), compatibility_script(self.product))

    @unittest.skipUnless(os.name == 'posix', 'POSIX shell syntax')
    def test_all_generated_remote_scripts_parse(self):
        session = prepare_session(self.product, self.base)
        plan = steps(session, '10.11.99.1')
        scripts = [compatibility_script(self.product)]
        for _, _, commands, _ in plan[1:]:
            for line in commands.splitlines():
                if line.startswith('ssh '):
                    scripts.append(shlex.split(line)[-1])
        for script in scripts:
            result = subprocess.run(['sh', '-n'], input=script, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(os.name == 'posix', 'POSIX fault injection')
    def test_backup_failure_stops_before_checksum_and_existing_backup_is_preserved(self):
        session = prepare_session(self.product, self.base)
        remote = shlex.split(steps(session, '10.11.99.1')[1][2].splitlines()[0])[-1]
        backup = self.base / 'backup'
        script = remote.replace('/home/root/paperdesk-backup-' + session['token'], str(backup))
        tools = self.base / 'bin'
        tools.mkdir()
        tar = tools / 'tar'
        tar.write_text('#!/bin/sh\nexit 42\n')
        tar.chmod(0o700)
        env = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'])
        result = subprocess.run(['sh', '-c', script], env=env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 42)
        self.assertFalse((backup / 'backup.sha256').exists())
        sentinel = backup / 'keep'
        sentinel.write_text('original')
        result = subprocess.run(['sh', '-c', script], env=env, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_text(), 'original')


    @unittest.skipUnless(os.name == 'nt', 'Windows PowerShell integration')
    def test_powershell_backup_verification_rejects_corruption_with_quoted_paths(self):
        destination = self.base / "user's folder"
        destination.mkdir()
        session = prepare_session(self.product, destination)
        folder = session['folder']
        payload = b'backup-test-only'
        (folder / 'tablet-backup.tar.gz').write_bytes(payload)
        (folder / 'backup.sha256').write_text(hashlib.sha256(payload).hexdigest() + '  tablet-backup.tar.gz\n')
        script = steps(session, '10.11.99.1', True)[1][2].split('\n\n')[-1]
        def verify():
            return subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command',
                                   "$ErrorActionPreference = 'Stop'; " + script],
                                  capture_output=True, text=True, timeout=20)
        result = verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Backup checksum: OK', result.stdout)
        (folder / 'tablet-backup.tar.gz').write_bytes(b'corrupted')
        self.assertNotEqual(verify().returncode, 0)

    @unittest.skipUnless(os.name == 'nt', 'Windows PowerShell integration')
    def test_powershell_check_passes_crlf_normalization_as_one_ssh_argument(self):
        from manual_wizard import shell_quote
        destination = self.base / "user's folder"
        destination.mkdir()
        session = prepare_session(self.product, destination)
        captured = self.base / 'ssh-argument.txt'
        prefix = ("function ssh { $args[-1] | Set-Content -LiteralPath "
                  + shell_quote(captured, True) + "; $input | Out-Null }; ")
        script = prefix + steps(session, '10.11.99.1', True)[0][2]
        result = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(captured.read_text().strip(), "tr -d '\\r' | sh -s")

    @unittest.skipUnless(os.name == 'posix', 'POSIX bundle builder')
    def test_linux_bundle_contains_runnable_shared_wizard_and_excludes_local_config(self):
        import shutil
        import tarfile
        for name in ['PaperDesk-Installer.sh', 'scripts/build-linux-installer.sh', 'INSTALL-DESKTOP.md',
                     'windows/manual_wizard.py', 'windows/package_core.py', 'windows/preflight.py']:
            target = self.base / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        (self.product / 'paperdesk.local.conf').write_text('SECRET')
        result = subprocess.run(['sh', 'scripts/build-linux-installer.sh'], cwd=self.base,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(self.base / 'dist/paperdesk-linux-installer-1.2.3.tar.gz') as bundle:
            names = bundle.getnames()
            prefix = 'paperdesk-linux-installer-1.2.3/'
            for name in ('wizard/manual_wizard.py', 'wizard/package_core.py', 'wizard/preflight.py',
                         'product/install.sh', 'INSTALL-DESKTOP.md', 'PaperDesk-Installer.sh'):
                self.assertIn(prefix + name, names)
            self.assertFalse(any('paperdesk.local.conf' in name for name in names))
            self.assertTrue(bundle.getmember(prefix + 'PaperDesk-Installer.sh').mode & 0o111)

    def test_windows_zip_contains_manual_assistant_and_rebuildable_source(self):
        import shutil
        import zipfile
        files = ['windows/package_installer.py', 'windows/package_core.py', 'windows/manual_wizard.py',
                 'windows/preflight.py', 'windows/requirements.txt', 'scripts/build-windows-installer.ps1',
                 'INSTALL-WINDOWS.md', 'tests/test_manual_wizard.py']
        for name in files:
            target = self.base / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        exe = self.base / 'dist/windows/1.2.3-prepare/PaperDesk-Installer.exe'
        exe.parent.mkdir(parents=True)
        exe.write_bytes(b'packaging-fixture-only')
        result = subprocess.run([sys.executable, 'windows/package_installer.py'], cwd=self.base,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.base / 'dist/paperdesk-windows-installer-1.2.3.zip') as bundle:
            for name in ['source/windows/manual_wizard.py', 'source/windows/package_core.py',
                         'source/tests/test_manual_wizard.py', 'PaperDesk-Installer.exe']:
                self.assertIn(name, bundle.namelist())

    @unittest.skipUnless(os.name == 'posix', 'POSIX firmware check')
    def test_firmware_check_uses_img_version_and_does_not_confuse_codex_version(self):
        model = self.base / 'model'
        model.write_text('reMarkable 2.0')
        release = self.base / 'os-release'
        preamble = compatibility_script(self.product).split('missing=0', 1)[0]
        preamble = preamble.replace('/sys/devices/soc0/machine', str(model))
        preamble = preamble.replace('/etc/os-release', str(release))
        for content, expected in [
                ('VERSION_ID=6.0.106\nIMG_VERSION="3.29.0.149"\n', 0),
                ('VERSION_ID="3.29.0.149"\n', 0),
                ('VERSION_ID=6.0.106\nIMG_VERSION="3.29.0.153"\n', 22)]:
            release.write_text(content)
            result = subprocess.run(['sh'], input=preamble, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    @unittest.skipUnless(os.name == 'posix', 'POSIX release-specific firmware check')
    def test_hardware_verified_firmware_is_allowed_only_for_the_validated_release(self):
        model = self.base / 'model'
        model.write_text('reMarkable 2.0')
        release = self.base / 'os-release'
        release.write_text('VERSION_ID=6.0.106\nIMG_VERSION="3.29.0.153"\n')
        metadata_path = self.product / 'release.json'
        metadata = json.loads(metadata_path.read_text())
        for version, expected in [('1.2.3', 22), ('3.0.3', 0), ('3.0.4', 22)]:
            metadata['version'] = version
            metadata_path.write_text(json.dumps(metadata))
            script = compatibility_script(self.product).split('missing=0', 1)[0]
            script = script.replace('/sys/devices/soc0/machine', str(model)).replace('/etc/os-release', str(release))
            result = subprocess.run(['sh'], input=script, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
