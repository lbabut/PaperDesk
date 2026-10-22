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


def verified_files(product):
    files = []
    for line in (product / 'SHA256SUMS').read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match:
            raise ValueError('Invalid SHA256SUMS manifest.')
        digest, name = match.groups()
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name or ':' in name:
            raise ValueError('Unsafe path in the package.')
        path = product.joinpath(*relative.parts)
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(product.resolve()):
            raise ValueError('Missing package file: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('Corrupt package file: ' + name)
        name = relative.as_posix()
        if name in files or name == 'paperdesk.local.conf':
            raise ValueError('Invalid file in the manifest.')
        files.append(name)
    if not {'install.sh', 'VERSION', 'release.json'}.issubset(files):
        raise ValueError('Incomplete package.')
    version = (product / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Invalid version.')
    if json.loads((product / 'release.json').read_text())['version'] != version:
        raise ValueError('Package version mismatch.')
    return files, version


def archive(product):
    files, version = verified_files(product)
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as tar:
        for name in files + ['SHA256SUMS']:
            content = (product / name).read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o755 if name.endswith('.sh') or name.startswith('payload/system/') else 0o644
            tar.addfile(info, io.BytesIO(content))
    return data.getvalue(), version


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
    import tkinter as tk
    from tkinter import ttk
    root = tk.Tk()
    root.title('PaperDesk — Windows Installer')
    root.geometry('590x450')
    root.resizable(False, False)
    frame = ttk.Frame(root, padding=24)
    frame.pack(fill='both', expand=True)
    ttk.Label(frame, text='PaperDesk for reMarkable 2', font=('Segoe UI', 18)).pack(anchor='w')
    ttk.Label(frame, text='Connect the tablet by USB and enable the USB web interface.\nUse Install PaperDesk if XOVI, AppLoad and LiTerm are ready.\nUse Prepare tablet to install missing dependencies (OS 3.29.0.149 only).', wraplength=540).pack(anchor='w', pady=12)
    ttk.Label(frame, text='Tablet address').pack(anchor='w')
    host = ttk.Entry(frame)
    host.insert(0, '10.11.99.1')
    host.pack(fill='x')
    ttk.Label(frame, text='USB management code from the tablet settings').pack(anchor='w', pady=(10, 0))
    password = ttk.Entry(frame, show='•')
    password.pack(fill='x')
    status = tk.StringVar(value='Ready to install')
    ttk.Label(frame, textvariable=status, wraplength=520).pack(anchor='w', pady=14)
    events = queue.Queue()
    busy = False

    def confirm(title, body):
        answer = queue.Queue()
        events.put(('confirm', (title, body, answer)))
        return answer.get()

    def worker(address, code, prepare=False):
        client = None
        try:
            check_windows()
            verified_files(product_path())
            events.put(('status', 'Connecting to the tablet…'))
            client = connect(address, code, confirm)
            code = None
            action = prepare_and_install if prepare else install
            done = action(client, product_path(), confirm, lambda text: events.put(('status', text)))
            events.put(('done', done))
        except Exception as exc:
            events.put(('error', str(exc)))
        finally:
            code = None
            if client:
                client.close()

    def start(prepare=False):
        nonlocal busy
        if busy:
            return
        if prepare and not english_dialog(root, 'Tablet preparation — risks and responsibility',
                                          RISK_NOTICE, question=True, acknowledgement=True):
            status.set('Tablet preparation cancelled. The tablet has not been changed.')
            return
        address, code = host.get().strip(), password.get()
        password.delete(0, 'end')
        busy = True
        button.configure(state='disabled')
        prepare_button.configure(state='disabled')
        host.configure(state='disabled')
        password.configure(state='disabled')
        threading.Thread(target=worker, args=(address, code, prepare), daemon=True).start()

    def poll():
        nonlocal busy
        while not events.empty():
            kind, value = events.get()
            if kind == 'confirm':
                title, body, answer = value
                answer.put(english_dialog(root, title, body, question=True))
            elif kind == 'status':
                status.set(value)
            else:
                busy = False
                button.configure(state='normal')
                prepare_button.configure(state='normal')
                host.configure(state='normal')
                password.configure(state='normal')
                if kind == 'error':
                    status.set('Installation did not complete.')
                    english_dialog(root, 'PaperDesk — Installation error', value)
                elif value:
                    status.set('PaperDesk installed. XOVI started.')
                    english_dialog(root, 'PaperDesk', 'Open AppLoad and check the PaperDesk apps.')
                elif value is None:
                    status.set('Tablet prepared. PaperDesk installation cancelled; dependencies remain installed.')
                else:
                    status.set('Installation cancelled.')
        root.after(100, poll)

    button = ttk.Button(frame, text='Install PaperDesk', command=start)
    button.pack(anchor='e')
    prepare_button = ttk.Button(frame, text='Prepare tablet and install PaperDesk', command=lambda: start(True))
    prepare_button.pack(anchor='e', pady=(10, 0))
    root.protocol('WM_DELETE_WINDOW', lambda: english_dialog(root, 'PaperDesk', 'Please wait until the operation finishes.') if busy else root.destroy())
    poll()
    if smoke:
        root.after(1000, root.destroy)
    root.mainloop()


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        check_windows()
        data, version = archive(product_path())
        # Windowed executables have no console; report via a requested file.
        result = f'PaperDesk {version} package OK {len(data)} bytes'
        if '--check-dependencies' in sys.argv:
            from prepare_tablet import dependency_files, fetch_assets
            dependencies = dependency_files(fetch_assets())
            result += f'\nDependency download and verification OK: {len(dependencies)} files'
        if '--report' in sys.argv:
            Path(sys.argv[sys.argv.index('--report') + 1]).write_text(result)
        elif sys.stdout:
            print(result)
    else:
        main(smoke='--ui-smoke' in sys.argv)
