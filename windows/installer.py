"""PaperDesk Windows installer; credentials stay in process memory."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import queue
import re
import shlex
import sys
import tarfile
import threading
import time
import uuid
import paramiko
from preflight import check_windows, tablet_check
from prepare_tablet import prepare_and_install, RISK_NOTICE

def product_path():
    return Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parents[1])) / 'product'


from package_core import verified_files, archive


def fingerprint(key):
    return 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')


class TrustPolicy(paramiko.MissingHostKeyPolicy):
    def __init__(self, path, confirm):
        self.path, self.confirm = path, confirm

    def missing_host_key(self, client, hostname, key):
        if not self.confirm('First connection', f'Tablet: {hostname}\nSSH fingerprint: {fingerprint(key)}\n\nCompare this fingerprint with a trusted source. Trust this device?'):
            raise RuntimeError('Device trust cancelled.')
        self.path.parent.mkdir(parents=True, exist_ok=True)
        client.get_host_keys().add(hostname, key.get_name(), key)
        client.save_host_keys(str(self.path))


def connect(host, password, confirm):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.:-]{0,252}', host):
        raise ValueError('Invalid tablet address.')
    if not password:
        raise ValueError('Enter the USB management code.')
    client = paramiko.SSHClient()
    keys = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'PaperDesk' / 'known_hosts'
    if keys.exists():
        client.load_host_keys(str(keys))
    client.set_missing_host_key_policy(TrustPolicy(keys, confirm))
    try:
        client.connect(host, username='root', password=password, look_for_keys=False,
                       allow_agent=False, timeout=12, banner_timeout=12, auth_timeout=12)
        return client
    except Exception:
        client.close()
        raise


def remote(client, command, timeout=180):
    channel = client.get_transport().open_session(timeout=12)
    try:
        channel.exec_command(command)
        output = bytearray()
        deadline = time.monotonic() + timeout
        while True:
            for ready, receive in ((channel.recv_ready, channel.recv), (channel.recv_stderr_ready, channel.recv_stderr)):
                while ready():
                    output.extend(receive(65536))
                    if len(output) > 2_000_000:
                        raise RuntimeError('The tablet response is too large.')
            if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                break
            if time.monotonic() > deadline:
                raise TimeoutError('The tablet did not finish the operation within the time limit.')
            time.sleep(0.02)
        if channel.recv_exit_status() != 0:
            raise RuntimeError('The operation on the tablet failed.\n' + output.decode('utf-8', 'replace')[-4000:])
        return output.decode('utf-8', 'replace')
    finally:
        channel.close()


def install(client, product, confirm, progress):
    payload, version = archive(product)
    progress('Checking tablet requirements…')
    check = remote(client, tablet_check(product))
    try:
        sftp = client.open_sftp()
        sftp.close()
    except Exception as exc:
        raise RuntimeError('SFTP file transfer is unavailable on the tablet. Ask your administrator to enable SFTP access. Installation has not started.') from exc
    if not confirm('Install PaperDesk ' + version, check + '\nExisting matching apps will be backed up and replaced.\nRestarting XOVI will close open apps. Continue?'):
        return False
    stage = '/home/root/paperdesk-install-windows-' + uuid.uuid4().hex
    quoted = shlex.quote(stage)
    remote(client, 'mkdir -m 700 ' + quoted)
    try:
        progress('Uploading the verified package…')
        sftp = client.open_sftp()
        try:
            sftp.putfo(io.BytesIO(payload), stage + '/package.tar.gz', file_size=len(payload))
        finally:
            sftp.close()
        expected = hashlib.sha256(payload).hexdigest()
        remote(client, f'cd {quoted} && echo "{expected}  package.tar.gz" | sha256sum -c - && tar -xzf package.tar.gz && sha256sum -c SHA256SUMS')
        progress('Installing apps and creating backups…')
        remote(client, f'cd {quoted} && sh ./install.sh', timeout=600)
        installed = remote(client, 'cat /home/root/.local/share/paperdesk/current-version').strip()
        if installed != version:
            raise RuntimeError('The tablet reported a different version after installation.')
        progress('Restarting XOVI…')
        remote(client, '/home/root/xovi/start', timeout=60)
        return True
    finally:
        try:
            remote(client, 'rm -rf -- ' + quoted, timeout=30)
        except Exception:
            pass


def english_dialog(root, title, body, question=False, acknowledgement=False):
    """Keep button labels in English regardless of the Windows display language."""
    import tkinter as tk
    from tkinter import ttk
    dialog = tk.Toplevel(root)
    dialog.title(title)
    dialog.transient(root)
    dialog.resizable(False, False)
    frame = ttk.Frame(dialog, padding=24)
    frame.pack(fill='both', expand=True)
    if len(body) > 650:
        content = ttk.Frame(frame)
        content.pack(fill='both', expand=True)
        scrollbar = ttk.Scrollbar(content)
        scrollbar.pack(side='right', fill='y')
        text = tk.Text(content, width=68, height=16, wrap='word', font=('Segoe UI', 10),
                       yscrollcommand=scrollbar.set, padx=8, pady=8)
        text.insert('1.0', body)
        text.configure(state='disabled')
        text.pack(side='left', fill='both', expand=True)
        scrollbar.configure(command=text.yview)
    else:
        ttk.Label(frame, text=body, wraplength=520, justify='left').pack(anchor='w')
    accepted = tk.BooleanVar(value=False)
    if acknowledgement:
        ttk.Checkbutton(frame, text='I have backed up my data and understand and accept these risks.',
                        variable=accepted, command=lambda: proceed.configure(
                            state='normal' if accepted.get() else 'disabled')).pack(anchor='w', pady=(16, 0))
    buttons = ttk.Frame(frame)
    buttons.pack(fill='x', pady=(20, 0))
    answer = False

    def close(value=False):
        nonlocal answer
        answer = value
        dialog.destroy()

    if question:
        proceed = ttk.Button(buttons, text='Prepare and install' if acknowledgement else 'Continue',
                             command=lambda: close(True) if not acknowledgement or accepted.get() else None)
        proceed.pack(side='right')
        if acknowledgement:
            proceed.configure(state='disabled')
        default = ttk.Button(buttons, text='Cancel', command=close)
    else:
        default = ttk.Button(buttons, text='OK', command=close)
    default.pack(side='right', padx=(0, 8))
    dialog.protocol('WM_DELETE_WINDOW', close)
    dialog.bind('<Escape>', lambda event: close())
    dialog.bind('<Return>', lambda event: default.invoke())
    dialog.update_idletasks()
    left = max(0, min(root.winfo_rootx() + 20, root.winfo_screenwidth() - dialog.winfo_reqwidth()))
    top = max(0, min(root.winfo_rooty() + 30, root.winfo_screenheight() - dialog.winfo_reqheight() - 60))
    dialog.geometry(f'+{left}+{top}')
    dialog.grab_set()
    default.focus_set()
    root.wait_window(dialog)
    return answer


def main(smoke=False):
    from manual_wizard import main as manual_main
    manual_main(product_path(), smoke=smoke)


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        check_windows()
        data, version = archive(product_path())
        # Windowed executables have no console; report via a requested file.
        result = f'PaperDesk {version} package OK {len(data)} bytes'
        if '--check-dependencies' in sys.argv:
            raise SystemExit('Automatic dependency downloads are disabled. Use the manual USB/SSH assistant.')
        if '--report' in sys.argv:
            Path(sys.argv[sys.argv.index('--report') + 1]).write_text(result)
        elif sys.stdout:
            print(result)
    else:
        main(smoke='--ui-smoke' in sys.argv)
