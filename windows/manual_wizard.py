"""Manual USB/SSH installation assistant. Never executes tablet commands."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import sys
import tempfile
import uuid

from package_core import archive
from preflight import tablet_check

# USB hardware validation: docs/INSTALLER-BUILD-2026-10-29.md
EXTRA_TESTED_FIRMWARE = {'3.0.3': ('3.29.0.153',)}


def shell_quote(value, windows=False):
    return "'" + str(value).replace("'", "''") + "'" if windows else shlex.quote(str(value))


def compatibility_script(product):
    metadata = json.loads((product / 'release.json').read_text())
    expected = metadata['testedWith']['remarkableOS']
    if not re.fullmatch(r'[0-9.]+', expected):
        raise ValueError('Invalid tested OS in release metadata.')
    supported = [expected] + list(EXTRA_TESTED_FIRMWARE.get(metadata['version'], ()))
    return r"""set -eu
model=$(cat /sys/devices/soc0/machine 2>/dev/null | tr -d '\000\r\n' || true)
if [ -z "$model" ]; then model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\000\r\n' || true); fi
[ "$model" = 'reMarkable 2.0' ] || { echo "STOP: unsupported tablet model: $model"; exit 22; }
version=$(sed -n 's/^IMG_VERSION=//p' /etc/os-release | tr -d '"\r\n')
if [ -z "$version" ]; then version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"\r\n'); fi
case "$version" in __OS__) ;; *) echo "STOP: unsupported OS: $version"; exit 22;; esac
""".replace('__OS__', '|'.join(supported)) + tablet_check(product) + "\nprintf 'PAPERDESK_COMPATIBILITY_OK\\n'\n"


def prepare_session(product, destination=None):
    """Verify first, then write only into a new private computer-side directory."""
    product = Path(product)
    payload, version = archive(product)
    check = compatibility_script(product)
    metadata = json.loads((product / 'release.json').read_text())
    tested = dict(metadata['testedWith'])
    extra = EXTRA_TESTED_FIRMWARE.get(version, ())
    if extra:
        tested['additionalHardwareTestedOS'] = ', '.join(extra)
    folder = Path(tempfile.mkdtemp(prefix='paperdesk-manual-', dir=destination))
    token = uuid.uuid4().hex
    package = folder / 'paperdesk-tablet.tar.gz'
    package.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    (folder / 'package.sha256').write_text(digest + '  paperdesk-tablet.tar.gz\n')
    (folder / 'check-tablet.sh').write_text(check, encoding='utf-8', newline='\n')
    return dict(folder=folder, version=version, token=token, digest=digest,
                tested=tested)


def steps(session, host, windows=False):
    # No options, userinfo, whitespace, quotes, shell syntax or IPv6 ambiguity.
    if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?', host):
        raise ValueError('Use an IPv4 address or DNS name, without a port or SSH options.')
    folder = session['folder']
    quote = lambda value: shell_quote(value, windows)
    target = 'root@' + host
    ssh = 'ssh -o StrictHostKeyChecking=ask -o ConnectTimeout=12 ' + target + ' '
    scp = 'scp -o StrictHostKeyChecking=ask -o ConnectTimeout=12 '
    stage = '/home/root/paperdesk-manual-' + session['token']
    backup = '/home/root/paperdesk-backup-' + session['token']
    checkfile = quote(folder / 'check-tablet.sh')
    check = ('Get-Content -Raw -LiteralPath ' + checkfile + ' | ' + ssh + quote("tr -d '\\r' | sh -s")
             if windows else ssh + quote('sh -s') + ' < ' + checkfile)
    backup_command = (
        'set -eu; umask 077; mkdir ' + backup + '; '
        'set -- xovi; '
        'if [ -d /home/root/.local/share/paperdesk ]; then set -- "$@" .local/share/paperdesk; fi; '
        'tar -czf ' + backup + '/tablet-backup.tar.gz -C /home/root "$@"; '
        'tar -tzf ' + backup + '/tablet-backup.tar.gz >/dev/null; '
        'cd ' + backup + '; sha256sum tablet-backup.tar.gz > backup.sha256; '
        'sha256sum -c backup.sha256')
    copy_backup = scp + target + ':' + backup + '/tablet-backup.tar.gz ' + quote(folder / 'tablet-backup.tar.gz')
    copy_hash = scp + target + ':' + backup + '/backup.sha256 ' + quote(folder / 'backup.sha256')
    verify_backup = (
        '$expected = ((Get-Content -LiteralPath ' + quote(folder / 'backup.sha256') + " -Raw).Trim() -split '\\s+')[0]\n"
        '$stream = [IO.File]::OpenRead(' + quote(folder / 'tablet-backup.tar.gz') + ')\n'
        '$sha = [Security.Cryptography.SHA256]::Create()\n'
        "try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') } "
        'finally { $stream.Dispose(); $sha.Dispose() }\n'
        "if ($actual -ne $expected) { throw 'STOP: backup checksum mismatch' }\n"
        "Write-Output 'Backup checksum: OK'"
        if windows else 'cd ' + quote(folder) + '\nsha256sum -c backup.sha256')
    digest = session['digest']
    verify = (
        'set -eu; cd ' + stage + '; '
        "printf '%s  package.tar.gz\\n' " + digest + ' | sha256sum -c -; '
        'tar -xzf package.tar.gz; sha256sum -c SHA256SUMS')
    install = 'set -eu; cd ' + stage + '; sha256sum -c SHA256SUMS; sh ./install.sh'
    tested = ', '.join(key + ': ' + str(value) for key, value in session['tested'].items())
    return [
        ('1. Compatibility', 'Connect a USB data cable and enable the tablet USB interface. '
         'Sync/export notebooks separately. Save open work. In the terminal, verify the SSH fingerprint '
         'against an independent trusted source; stop if it changes. Enter the device SSH password '
         'only at the terminal prompt.\n\nRun the check below. All requirements must pass and the final line '
         'must be PAPERDESK_COMPATIBILITY_OK. Confirm the installed dependency versions separately: '
         + tested + '. Missing or different dependencies require manual preparation; stop here.\n\n'
         'The check reads tablet state; it does not install or enable anything.',
         check, 'I checked the fingerprint, compatibility output and dependency versions.'),
        ('2. Backup', 'Run EACH command separately. Stop on any failure. The first command creates a new '
         'backup of XOVI (including AppLoad apps and their data) and existing PaperDesk state. '
         'It is not a full tablet/notebook backup. Copy it to this computer and verify the checksum. '
         'Keep both copies. A failed or partial backup must not be used to continue.\n\n'
         'Backup directory on tablet: ' + backup,
         ssh + quote(backup_command) + '\n\n' + copy_backup + '\n\n' + copy_hash + '\n\n' + verify_backup,
         'Notebook backup/sync is complete; the computer backup checksum is OK.'),
        ('3. Transfer and verify', 'The package was verified locally. Run each command separately. '
         'The new staging directory must not exist. Never delete an earlier attempt to make this pass. '
         'Every checksum must say OK before proceeding.',
         ssh + quote('mkdir -m 700 ' + stage) + '\n\n'
         + scp + quote(folder / 'paperdesk-tablet.tar.gz') + ' ' + target + ':' + stage + '/package.tar.gz'
         + '\n\n' + ssh + quote(verify),
         'Upload and all archive/package checksum checks succeeded.'),
        ('4. Manual installation', 'This step changes the tablet. Run the install command only after the '
         'compatibility, backup and transfer steps succeeded. Existing matching apps are backed up and '
         'replaced by product/install.sh. Keep all backup and staging directories after any failure. '
         'XOVI startup at boot is not enabled. The assistant does not start XOVI.',
         ssh + quote(install) + '\n\n' + ssh + quote('cat /home/root/.local/share/paperdesk/current-version'),
         'Installation succeeded and the tablet reports version ' + session['version'] + '.'),
        ('5. Verify and keep backups', 'You may start XOVI manually with the first command below after saving '
         'work; it restarts the tablet interface. Open and close the PaperDesk apps and check your notebooks. '
         'After a tablet reboot, start XOVI manually again. No boot autostart is configured.\n\n'
         'If something failed, stop and retain backups/logs. Inspect product/MANUAL-INSTALL.md before recovery. '
         'The assistant does not automatically restore or remove files. Backups cannot guarantee recovery.',
         ssh + quote('/home/root/xovi/start') + '\n\n'
         + '# Optional return to the stock interface:\n' + ssh + quote('/home/root/xovi/stock'),
         'I verified the apps and notebooks and kept the backups.')
    ]


def main(product=None, smoke=False):
    import tkinter as tk
    from tkinter import ttk, messagebox
    if product is None:
        product = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parents[1])) / 'product'
    root = tk.Tk()
    root.title('PaperDesk — Manual USB/SSH installation')
    root.geometry('900x760')
    frame = ttk.Frame(root, padding=20)
    frame.pack(fill='both', expand=True)
    ttk.Label(frame, text='PaperDesk — manual USB/SSH installation', font=('', 18)).pack(anchor='w')
    ttk.Label(frame, text='Run commands yourself in PowerShell (Windows) or a terminal (Linux). '
              'No device password is collected by this assistant.', wraplength=840).pack(anchor='w', pady=8)
    row = ttk.Frame(frame)
    row.pack(fill='x')
    ttk.Label(row, text='Tablet IPv4 address or DNS name:').pack(side='left')
    address = ttk.Entry(row, width=32)
    address.insert(0, '10.11.99.1')
    address.pack(side='left', padx=10)
    status = tk.StringVar(value='Verify the package to begin. No tablet commands run automatically.')
    ttk.Label(frame, textvariable=status, wraplength=840).pack(anchor='w', pady=8)
    title = tk.StringVar(value='Before you start')
    ttk.Label(frame, textvariable=title, font=('', 14)).pack(anchor='w', pady=6)
    body = tk.StringVar(value='You need OpenSSH ssh/scp and a terminal. Back up your notebooks before making '
                        'changes. Only the model, firmware and dependencies in this package are supported.')
    ttk.Label(frame, textvariable=body, wraplength=840, justify='left').pack(anchor='w', pady=6)
    area = ttk.Frame(frame)
    area.pack(fill='both', expand=True)
    scrollbar = ttk.Scrollbar(area)
    scrollbar.pack(side='right', fill='y')
    commands = tk.Text(area, height=12, wrap='word', yscrollcommand=scrollbar.set)
    commands.pack(fill='both', expand=True)
    scrollbar.config(command=commands.yview)
    accepted = tk.BooleanVar(value=False)
    acknowledgement = ttk.Checkbutton(frame, variable=accepted)
    acknowledgement.pack(anchor='w', pady=10)
    controls = ttk.Frame(frame)
    controls.pack(fill='x')
    pages, index = [], -1

    def show():
        heading, explanation, text, label = pages[index]
        title.set(heading)
        body.set(explanation)
        commands.configure(state='normal')
        commands.delete('1.0', 'end')
        commands.insert('1.0', text)
        commands.configure(state='disabled')
        accepted.set(False)
        acknowledgement.configure(text=label)
        next_button.configure(text='Finish' if index == len(pages) - 1 else 'Next', state='disabled')

    def advance():
        nonlocal pages, index
        try:
            if index < 0:
                missing = [tool for tool in ('ssh', 'scp') if not shutil.which(tool)]
                if missing:
                    raise RuntimeError('Install OpenSSH first. Missing: ' + ', '.join(missing))
                # Validate before writing local session files.
                steps(dict(folder=Path('.'), token='0'*32, digest='0'*64, version='0', tested={}), address.get().strip())
                session = prepare_session(product)
                pages = steps(session, address.get().strip(), sys.platform == 'win32')
                report = '\n\n'.join(h + '\n' + b + '\n\n' + c + '\n\nConfirm: ' + a for h,b,c,a in pages)
                (session['folder'] / 'MANUAL-STEPS.txt').write_text(report, encoding='utf-8')
                status.set('Verified PaperDesk ' + session['version'] + '. Files and instructions: ' + str(session['folder']))
                address.configure(state='disabled')
            elif not accepted.get():
                return
            elif index == len(pages) - 1:
                root.destroy()
                return
            index += 1
            show()
        except Exception as exc:
            messagebox.showerror('PaperDesk — stopped', str(exc), parent=root)

    def copy():
        root.clipboard_clear()
        root.clipboard_append(commands.get('1.0', 'end-1c'))

    acknowledgement.configure(command=lambda: next_button.configure(state='normal' if accepted.get() else 'disabled'))
    ttk.Button(controls, text='Copy commands', command=copy).pack(side='left')
    ttk.Button(controls, text='Close', command=root.destroy).pack(side='right')
    next_button = ttk.Button(controls, text='Verify package and begin', command=advance)
    next_button.pack(side='right', padx=10)
    if smoke:
        root.after(1000, root.destroy)
    root.mainloop()


if __name__ == '__main__':
    main(smoke='--ui-smoke' in sys.argv)
