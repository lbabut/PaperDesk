import hashlib
import io
import json
from pathlib import Path
import socket
import sys
import tarfile
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import installer as app
import paramiko


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.product = Path(self.temp.name)
        for name, data in {'VERSION': b'2.0.1\n', 'release.json': b'{"version":"2.0.1"}',
                           'install.sh': b'#!/bin/sh\necho OK\n', 'payload/tool': b'binary'}.items():
            path = self.product / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.manifest()

    def manifest(self):
        lines = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  ./{p.relative_to(self.product).as_posix()}'
                 for p in self.product.rglob('*') if p.is_file() and p.name != 'SHA256SUMS']
        (self.product / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')

    def test_archive_preserves_bytes_and_excludes_local_secrets(self):
        (self.product / 'paperdesk.local.conf').write_text('SECRET')
        data, version = app.archive(self.product)
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            self.assertNotIn('paperdesk.local.conf', tar.getnames())
            self.assertEqual(tar.extractfile('install.sh').read(), b'#!/bin/sh\necho OK\n')
            self.assertEqual(tar.getmember('install.sh').mode, 0o755)
        self.assertEqual(version, '2.0.1')

    def test_corrupt_package_rejected_before_connection_or_mutation(self):
        (self.product / 'install.sh').write_text('modified')
        with patch.object(app, 'remote') as remote:
            with self.assertRaises(ValueError):
                app.install(Mock(), self.product, Mock(), Mock())
            remote.assert_not_called()

    def test_missing_file(self):
        (self.product / 'install.sh').unlink()
        with self.assertRaises(ValueError):
            app.archive(self.product)

    def test_path_traversal(self):
        for name in ('../secret', '/etc/passwd', 'C:/secret', '..\\secret'):
            (self.product / 'SHA256SUMS').write_text('0' * 64 + '  ' + name)
            with self.assertRaises(ValueError):
                app.archive(self.product)

    def test_version_mismatch(self):
        (self.product / 'release.json').write_text('{"version":"1.0.0"}')
        self.manifest()
        with self.assertRaises(ValueError):
            app.archive(self.product)

    def test_secret_in_manifest_rejected(self):
        (self.product / 'paperdesk.local.conf').write_text('secret')
        self.manifest()
        with self.assertRaises(ValueError):
            app.archive(self.product)

    def test_cancel_does_not_upload(self):
        client = Mock()
        with patch.object(app, 'remote', return_value='VERSION=1.0.0') as remote:
            self.assertFalse(app.install(client, self.product, lambda *args: False, Mock()))
        client.open_sftp.return_value.putfo.assert_not_called()
        self.assertEqual(remote.call_count, 1)

    def test_success_and_remote_checksum_before_install(self):
        commands = []
        def remote(client, command, **kwargs):
            commands.append(command)
            return '2.0.1\n' if command.startswith('cat ') else 'OK'
        client = Mock()
        with patch.object(app, 'remote', side_effect=remote):
            self.assertTrue(app.install(client, self.product, lambda *a: True, Mock()))
        self.assertIn('sha256sum -c SHA256SUMS', commands[2])
        self.assertIn('sh ./install.sh', commands[3])
        self.assertEqual(commands[-2], '/home/root/xovi/start')
        self.assertRegex(commands[-1], r'^rm -rf -- /home/root/paperdesk-install-windows-[a-f0-9]{32}$')
        self.assertEqual(client.open_sftp.return_value.close.call_count, 2)

    def test_missing_tablet_dependency_never_confirms_or_uploads(self):
        client, confirm = Mock(), Mock()
        with patch.object(app, 'remote', side_effect=RuntimeError('Brak wymagania: LiTerm')):
            with self.assertRaisesRegex(RuntimeError, 'LiTerm'):
                app.install(client, self.product, confirm, Mock())
        confirm.assert_not_called()
        client.open_sftp.assert_not_called()

    def test_missing_sftp_never_confirms_or_creates_stage(self):
        client, confirm = Mock(), Mock()
        client.open_sftp.side_effect = OSError('missing subsystem')
        with patch.object(app, 'remote', return_value='Wymagania tabletu: OK') as remote:
            with self.assertRaisesRegex(RuntimeError, 'SFTP'):
                app.install(client, self.product, confirm, Mock())
        confirm.assert_not_called()
        self.assertEqual(remote.call_count, 1)

    def test_failed_upload_cleans_stage_and_never_restarts(self):
        client = Mock()
        client.open_sftp.return_value.putfo.side_effect = OSError('upload failed')
        with patch.object(app, 'remote', return_value='OK') as remote:
            with self.assertRaises(OSError):
                app.install(client, self.product, lambda *a: True, Mock())
        self.assertNotIn('/home/root/xovi/start', [c.args[1] for c in remote.call_args_list])
        self.assertTrue(remote.call_args.args[1].startswith('rm -rf -- /home/root/paperdesk-install-windows-'))

    def test_remote_verification_failure_never_installs(self):
        with patch.object(app, 'remote', side_effect=['OK', 'OK', RuntimeError('bad checksum'), 'OK']) as remote:
            with self.assertRaises(RuntimeError):
                app.install(Mock(), self.product, lambda *a: True, Mock())
        self.assertFalse(any('sh ./install.sh' in c.args[1] for c in remote.call_args_list))

    def test_invalid_host_and_empty_password(self):
        for host in ('-option', 'host;command', 'host/user', ''):
            with self.assertRaises(ValueError):
                app.connect(host, 'secret', Mock())
        with self.assertRaises(ValueError):
            app.connect('10.11.99.1', '', Mock())

    def test_declined_key_never_saved(self):
        client = Mock()
        key = paramiko.RSAKey.generate(1024)
        with self.assertRaises(RuntimeError):
            app.TrustPolicy(self.product / 'known_hosts', lambda *a: False).missing_host_key(client, 'tablet', key)
        client.save_host_keys.assert_not_called()

    def test_changed_key_not_silently_accepted(self):
        client = Mock()
        client.connect.side_effect = paramiko.BadHostKeyException('tablet', paramiko.RSAKey.generate(1024), paramiko.RSAKey.generate(1024))
        confirm = Mock()
        with patch.object(app.paramiko, 'SSHClient', return_value=client):
            with self.assertRaises(paramiko.BadHostKeyException):
                app.connect('tablet', 'secret', confirm)
        confirm.assert_not_called()
        client.close.assert_called_once()

    def test_real_package(self):
        files, version = app.verified_files(app.product_path())
        self.assertGreater(len(files), 50)
        self.assertEqual(version, (app.product_path() / 'VERSION').read_text().strip())
        self.assertFalse(any('payload/apps/paperpet/' in name for name in files))
        self.assertFalse((app.product_path() / 'payload/apps/paperpet').exists())

    def test_retired_pet_is_backed_up_before_removal(self):
        script = (app.product_path() / 'install.sh').read_text()
        self.assertIn('cp -R "$TARGET/paperpet" "$BACKUP/apps/paperpet"', script)
        self.assertLess(script.index('cp -R "$TARGET/paperpet" "$BACKUP/apps/paperpet"'),
                        script.index('rm -rf "$TARGET/paperpet"'))
        required = script.split('for required in ', 1)[1].split('; do', 1)[0]
        self.assertNotIn('paperpet', required)


class SSHWireTests(unittest.TestCase):
    def test_real_ssh_password_channel_output_and_failure(self):
        """Actual loopback SSH transport, no tablet or production writes."""
        key = paramiko.RSAKey.generate(2048)
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(10)
        errors = []
        class Server(paramiko.ServerInterface):
            def check_auth_password(self, username, password):
                return paramiko.AUTH_SUCCESSFUL if (username, password) == ('root', 'test-only') else paramiko.AUTH_FAILED
            def get_allowed_auths(self, username):
                return 'password'
            def check_channel_request(self, kind, chanid):
                return paramiko.OPEN_SUCCEEDED
            def check_channel_exec_request(self, channel, command):
                def respond():
                    channel.send(b'wire output\n')
                    channel.send_stderr(b'wire stderr\n')
                    channel.send_exit_status(22 if command == b'fail' else 0)
                threading.Thread(target=respond, daemon=True).start()
                return True
        def serve():
            transport = None
            channels = []
            try:
                conn, _ = listener.accept()
                transport = paramiko.Transport(conn)
                transport.add_server_key(key)
                transport.start_server(server=Server())
                while transport.is_active():
                    channel = transport.accept(timeout=1)
                    if channel:
                        channels.append(channel)
            except Exception as exc:
                errors.append(exc)
            finally:
                if transport:
                    transport.close()
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        client = paramiko.SSHClient()
        client.get_host_keys().add(f'[127.0.0.1]:{listener.getsockname()[1]}', key.get_name(), key)
        try:
            client.connect('127.0.0.1', port=listener.getsockname()[1], username='root', password='test-only', look_for_keys=False, allow_agent=False, timeout=5)
            self.assertIn('wire output', app.remote(client, 'pass', timeout=5))
            with self.assertRaisesRegex(RuntimeError, 'wire stderr'):
                app.remote(client, 'fail', timeout=5)
        finally:
            client.close()
            listener.close()
            thread.join(3)
        self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()
