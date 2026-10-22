import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import installer
import prepare_tablet as prep


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.product = Path(self.temp.name)
        for name, data in {'VERSION': b'2.0.2', 'release.json': b'{"version":"2.0.2"}', 'install.sh': b'#!/bin/sh\ntrue'}.items():
            (self.product / name).write_bytes(data)
        (self.product / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in self.product.iterdir()))

    def test_declining_risk_confirmation_never_uploads_or_creates_stage(self):
        client = Mock()
        with patch.object(installer, 'remote', return_value='Supported tablet') as remote, \
             patch.object(prep, 'fetch_assets'), patch.object(prep, 'dependency_files', return_value={}):
            confirm = Mock(return_value=False)
            self.assertFalse(prep.prepare_and_install(client, self.product, confirm, Mock()))
        self.assertIn('accept no responsibility', confirm.call_args.args[1])
        self.assertIn('manual recovery', confirm.call_args.args[1])
        self.assertEqual(remote.call_count, 2)
        client.open_sftp.return_value.putfo.assert_not_called()

    def test_unsupported_tablet_never_downloads_or_uploads(self):
        client = Mock()
        with patch.object(installer, 'remote', side_effect=RuntimeError('Unsupported tablet OS')), \
             patch.object(prep, 'fetch_assets') as fetch:
            with self.assertRaisesRegex(RuntimeError, 'Unsupported'):
                prep.prepare_and_install(client, self.product, Mock(), Mock())
        fetch.assert_not_called()
        client.open_sftp.assert_not_called()

    def test_corrupt_dependency_never_mutates_tablet(self):
        client = Mock()
        with patch.object(installer, 'remote', return_value='Supported') as remote, \
             patch.object(prep, 'fetch_assets', side_effect=ValueError('Dependency checksum failed')):
            with self.assertRaises(ValueError):
                prep.prepare_and_install(client, self.product, Mock(), Mock())
        self.assertEqual(remote.call_count, 1)
        client.open_sftp.return_value.putfo.assert_not_called()

    def test_success_verifies_transfer_before_preparing_then_installs_paperdesk(self):
        client = Mock()
        with patch.object(installer, 'remote', return_value='OK') as remote, \
             patch.object(installer, 'install', return_value=True) as install, \
             patch.object(prep, 'fetch_assets'), patch.object(prep, 'dependency_files', return_value={}):
            self.assertTrue(prep.prepare_and_install(client, self.product, Mock(return_value=True), Mock()))
        commands = [call.args[1] for call in remote.call_args_list]
        self.assertIn('sha256sum -c SHA256SUMS', commands[3])
        self.assertIn('timeout -k 30 310 sh ./prepare.sh', commands[4])
        self.assertTrue(commands[5].startswith('rm -rf -- /home/root/paperdesk-prepare-'))
        install.assert_called_once()

    def test_failed_preparation_never_installs_paperdesk(self):
        with patch.object(installer, 'remote', side_effect=['OK','OK','OK','OK',RuntimeError('Resource rebuild failed'),'OK']), \
             patch.object(installer, 'install') as install, \
             patch.object(prep, 'fetch_assets'), patch.object(prep, 'dependency_files', return_value={}):
            with self.assertRaisesRegex(RuntimeError, 'Resource rebuild'):
                prep.prepare_and_install(Mock(), self.product, Mock(return_value=True), Mock())
        install.assert_not_called()

    def test_post_preparation_failure_explains_dependencies_are_already_installed(self):
        with patch.object(installer, 'remote', return_value='OK'), \
             patch.object(installer, 'install', side_effect=RuntimeError('Upload failed')), \
             patch.object(prep, 'fetch_assets'), patch.object(prep, 'dependency_files', return_value={}):
            with self.assertRaisesRegex(RuntimeError, 'dependencies were prepared'):
                prep.prepare_and_install(Mock(), self.product, Mock(return_value=True), Mock())

    def test_cancel_after_successful_preparation_reports_prepared_only(self):
        with patch.object(installer, 'remote', return_value='OK'), \
             patch.object(installer, 'install', return_value=False), \
             patch.object(prep, 'fetch_assets'), patch.object(prep, 'dependency_files', return_value={}):
            self.assertIsNone(prep.prepare_and_install(Mock(), self.product, Mock(return_value=True), Mock()))

    def test_download_checksum_mismatch_is_rejected(self):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = b'corrupted release'
        with patch.object(prep.urllib.request, 'urlopen', return_value=response):
            with self.assertRaisesRegex(ValueError, 'checksum'):
                prep.fetch_assets()

    def test_archive_contains_only_expected_symlinks_and_verified_recovery_scripts(self):
        stage = '/home/root/paperdesk-prepare-' + 'a' * 32
        data = prep.preparation_archive({'xovi/start': b'#!/bin/sh\ntrue'}, stage)
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            links = {m.name:m.linkname for m in archive if m.issym()}
            self.assertEqual(links, prep.SYMLINKS)
            manifest = archive.extractfile('SHA256SUMS').read().decode()
            for line in manifest.splitlines():
                digest, name = line.split('  ')
                self.assertEqual(hashlib.sha256(archive.extractfile(name).read()).hexdigest(), digest)
            self.assertIn(b'systemd-run', archive.extractfile('prepare.sh').read())
            self.assertIn(b'committed', archive.extractfile('restore.sh').read())


if __name__ == '__main__':
    unittest.main()
