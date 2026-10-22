"""Optional, pinned dependency bootstrap for reMarkable 2 / OS 3.29.0.149."""
import hashlib
import io
from pathlib import PurePosixPath
import shlex
import tarfile
import urllib.request
import uuid

SUPPORTED_OS = '3.29.0.149'
RISK_NOTICE = (
    'This installs unofficial XOVI, AppLoad, LiTerm and qt-resource-rebuilder components '
    'inside the tablet interface, then installs PaperDesk.\n\n'
    'Risks include crashes, loss of unsaved work or data, an unusable interface, and '
    'manual recovery of the tablet. An interruption or incompatible modification can '
    'leave a partial installation. Backups and automatic recovery cannot guarantee recovery.\n\n'
    'Back up or sync your notebooks first, save open work, and keep USB connected. '
    'Unlock the tablet when prompted during preparation.\n\n'
    'Use at your own risk. PaperDesk authors and contributors accept no responsibility '
    'for problems, data loss or damage resulting from this operation, to the extent '
    'permitted by applicable law. This is not supported by reMarkable.\n\n'
    'Automatic preparation supports only reMarkable 2 with OS 3.29.0.149. '
    'It does not enable XOVI to start automatically at boot.'
)
ASSETS = {
    'xovi': ('https://github.com/asivery/rm-xovi-extensions/releases/download/v19-23052026/xovi-arm32.tar.gz',
             '9aa00537ad41e9be0c3151992bfc25106465318cf5bb4c41cf59b3ddd4866377'),
    'appload': ('https://github.com/asivery/rm-appload/releases/download/v0.6.0/appload-arm32.tar.gz',
                '25aa54735742ea63c0a043cba5496987dd4ca742d8b3fc26a21b7368372bf44f'),
    'literm': ('https://github.com/asivery/rm-literm/releases/download/v0.1.7/literm-arm32.so',
               '6e64d3dba3c05e56c8c883e29f6767f713ddcc9cc679909a537cc1cbc4cb8c6c'),
}
SYMLINKS = {
    'xovi/services/xochitl.service/exthome': '/home/root/xovi/exthome',
    'xovi/services/xochitl.service/extensions.d': '/home/root/xovi/extensions.d',
}
REQUIRED_FILES = {
    'xovi/xovi.so', 'xovi/start', 'xovi/stock', 'xovi/rebuild_hashtable', 'xovi/debug',
    'xovi/extensions.d/qt-resource-rebuilder.so', 'xovi/extensions.d/appload.so',
    'xovi/extensions.d/literm.so',
    'xovi/services/xochitl.service/qt-resource-rebuilder.conf',
    'xovi/scripts/debug/qt-resource-rebuilder.sh',
}


def fetch_assets():
    result = {}
    for name, (url, digest) in ASSETS.items():
        request = urllib.request.Request(url, headers={'User-Agent': 'PaperDesk-Windows-Installer/2.0.2'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(32 * 1024 * 1024 + 1)
        except Exception as exc:
            raise RuntimeError('Could not download ' + name + '. Check the computer internet connection. The tablet has not been changed.') from exc
        if len(data) > 32 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != digest:
            raise ValueError('Dependency checksum failed: ' + name + '. The tablet has not been changed.')
        result[name] = data
    return result


def dependency_files(assets):
    """Normalize trusted archives; only the required files and explicit links survive."""
    for name, (_, digest) in ASSETS.items():
        if hashlib.sha256(assets[name]).hexdigest() != digest:
            raise ValueError('Dependency checksum failed: ' + name)
    files = {}
    for asset, mapping in [('xovi', None), ('appload', {'appload.so': 'xovi/extensions.d/appload.so'})]:
        with tarfile.open(fileobj=io.BytesIO(assets[asset]), mode='r:gz') as archive:
            seen = set()
            for member in archive:
                path = PurePosixPath(member.name)
                if path.is_absolute() or '..' in path.parts or '\\' in member.name or ':' in member.name:
                    raise ValueError('Unsafe dependency archive path.')
                name = path.as_posix()
                if name in seen:
                    raise ValueError('Duplicate dependency archive path.')
                seen.add(name)
                if member.issym():
                    if asset != 'xovi' or SYMLINKS.get(name) != member.linkname:
                        raise ValueError('Unexpected dependency symlink.')
                    continue
                if not member.isfile() and not member.isdir():
                    raise ValueError('Unexpected dependency archive entry.')
                target = mapping.get(name) if mapping is not None else name
                if member.isfile() and target in REQUIRED_FILES:
                    if member.size > 32 * 1024 * 1024:
                        raise ValueError('Dependency file is too large.')
                    files[target] = archive.extractfile(member).read()
    files['xovi/extensions.d/literm.so'] = assets['literm']
    if set(files) != REQUIRED_FILES:
        raise ValueError('Incomplete dependency package.')
    for name in ['xovi/xovi.so', 'xovi/extensions.d/qt-resource-rebuilder.so',
                 'xovi/extensions.d/appload.so', 'xovi/extensions.d/literm.so']:
        data = files[name]
        if data[:6] != b'\x7fELF\x01\x01' or data[18:20] != b'\x28\x00':
            raise ValueError('Dependency is not an ARM32 ELF: ' + name)
    return files


def eligibility_script(minimum_kib=131072):
    return r'''set -eu
for tool in sh bash id cat uname tar gzip sha256sum systemctl systemd-run cp rm mkdir chmod grep sed date mv touch df du awk wget openssl unzip flock wc tr mktemp find readlink timeout pidof kill ln mount umount sleep dirname basename; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 22; }
done
[ "$(id -u)" = 0 ] || { echo 'Tablet administrator access (root) is required.'; exit 22; }
[ "$(uname -m)" = armv7l ] || { echo 'Automatic preparation supports ARMv7 reMarkable 2 only.'; exit 22; }
model=$(cat /sys/devices/soc0/machine 2>/dev/null | tr -d '\000\r\n' || true)
if [ -z "$model" ]; then model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\000\r\n' || true); fi
[ "$model" = 'reMarkable 2.0' ] || { echo "Unsupported tablet model: $model"; exit 22; }
version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"\r\n')
[ "$version" = '3.29.0.149' ] || { echo "Unsupported tablet OS: $version. Automatic preparation requires 3.29.0.149."; exit 22; }
[ -d /run/systemd/system ] && [ -w /home/root ] && [ -w /etc/systemd/system ] || { echo 'systemd and writable tablet storage are required.'; exit 22; }
openssl list -public-key-algorithms 2>/dev/null | grep -qi ED25519 || { echo 'OpenSSL Ed25519 support is required for Care.'; exit 22; }
[ ! -e /tmp/xovi-hashtab ] || { echo 'Another hashtable operation or leftover directory exists. Ask your administrator to check /tmp/xovi-hashtab.'; exit 22; }
existing=0
if [ -e /home/root/xovi ]; then
    [ -d /home/root/xovi ] && [ ! -L /home/root/xovi ] || { echo 'Unsupported XOVI directory.'; exit 22; }
    existing=$(du -sk /home/root/xovi | awk '{print $1}')
fi
available=$(df -Pk /home/root | awk 'NR==2 {print $4}')
case "$available:$existing" in *[!0-9:]*|:*|*:) echo 'Could not measure tablet storage.'; exit 22;; esac
required=$((__MINIMUM_KIB__ + existing * 3))
[ "$available" -ge "$required" ] || { echo "Not enough space: $required KB required, $available KB available."; exit 22; }
printf 'Tablet: %s\nOS: %s\nAvailable: %s KB\n' "$model" "$version" "$available"
'''.replace('__MINIMUM_KIB__', str(minimum_kib))


def compatibility_script(files):
    commands = [eligibility_script()]
    # Reject symlink redirection, incompatible binaries and unknown executable hooks.
    commands.append(r'''
if [ -d /home/root/xovi ]; then
    links=$(find /home/root/xovi -type l)
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        case "$link" in
          /home/root/xovi/services/xochitl.service/exthome) expected=/home/root/xovi/exthome;;
          /home/root/xovi/services/xochitl.service/extensions.d) expected=/home/root/xovi/extensions.d;;
          *) echo "Unsupported XOVI symlink: $link"; exit 22;;
        esac
        [ "$(readlink "$link")" = "$expected" ] || { echo "Unexpected XOVI link target: $link"; exit 22; }
    done <<EOF
$links
EOF
    for file in /home/root/xovi/extensions.d/*.so; do
        [ -e "$file" ] || continue
        case "$file" in */appload.so|*/literm.so|*/qt-resource-rebuilder.so) ;; *) echo "Another active extension needs administrator review: $file"; exit 22;; esac
    done
    for hook in pre-start post-start pre-stock post-stock; do
        if [ -d "/home/root/xovi/scripts/$hook" ] && [ -n "$(find "/home/root/xovi/scripts/$hook" -type f)" ]; then
            echo "Custom XOVI hooks need administrator review: $hook"; exit 22
        fi
    done
    for service in /home/root/xovi/services/*; do
        [ -e "$service" ] || continue
        [ "$service" = /home/root/xovi/services/xochitl.service ] || { echo "Another XOVI service needs administrator review: $service"; exit 22; }
    done
    for config in /home/root/xovi/services/xochitl.service/*; do
        [ -e "$config" ] || continue
        case "$config" in */exthome|*/extensions.d|*/qt-resource-rebuilder.conf) ;; *) echo "Another XOVI service setting needs administrator review: $config"; exit 22;; esac
    done
fi
''')
    for name, data in sorted(files.items()):
        path = '/home/root/' + name
        quoted = shlex.quote(path)
        digest = hashlib.sha256(data).hexdigest()
        commands.append(f'if [ -e {quoted} ]; then [ -f {quoted} ] && [ "$(sha256sum {quoted} | awk \'{{print $1}}\')" = {digest} ] || {{ echo "Existing dependency differs: {path}. Use Install PaperDesk for an already prepared tablet, or ask your administrator."; exit 22; }}; fi')
    commands.append("echo 'Pinned XOVI 0.3.3 / resources v19, AppLoad 0.6.0 and LiTerm 0.1.7: compatible.'")
    return '\n'.join(commands)


RESTORE_SCRIPT = r'''#!/bin/sh
set -eu
backup=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$backup" in /home/root/.local/share/paperdesk-preparation/[a-f0-9]*) ;; *) echo 'Invalid preparation backup path.'; exit 1;; esac
exec 9>"$backup/restore.lock"
flock 9
[ ! -f "$backup/committed" ] && [ ! -f "$backup/restored" ] || exit 0
echo 'Restoring the tablet after failed preparation.'
if [ -x /home/root/xovi/stock ]; then timeout 30 /home/root/xovi/stock || true; fi
systemctl stop xochitl || true
umount -q /etc/systemd/system/xochitl.service.d || true
if [ -e /home/root/xovi ]; then mv /home/root/xovi "$backup/failed-xovi-$(date +%s)-$$"; fi
if [ -f "$backup/had-xovi" ]; then cp -a "$backup/xovi" /home/root/xovi; fi
systemctl daemon-reload
systemctl start xochitl
if [ -L /tmp/xovi-hashtab/extensions.d/qt-resource-rebuilder.so ] && [ "$(readlink /tmp/xovi-hashtab/extensions.d/qt-resource-rebuilder.so)" = /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]; then
    rm -rf -- /tmp/xovi-hashtab
fi
touch "$backup/restored"
echo "Stock interface restored. Preparation backup: $backup"
'''


def preparation_script(stage, files):
    token = stage.rsplit('-', 1)[-1]
    if len(token) != 32 or any(c not in '0123456789abcdef' for c in token):
        raise ValueError('Invalid preparation identifier.')
    backup = '/home/root/.local/share/paperdesk-preparation/' + token
    unit = 'paperdesk-prepare-rollback-' + token
    return 'set -eu\nexec 8>/home/root/.paperdesk-preparation.lock\nflock -n 8 || { echo "Another tablet preparation is running."; exit 1; }\n' + compatibility_script(files) + '\n' + r'''
stage=__STAGE__
backup=__BACKUP__
unit=__UNIT__
mkdir -p /home/root/.local/share/paperdesk-preparation
mkdir -m 700 "$backup"
cp "$stage/restore.sh" "$backup/restore.sh"
chmod 700 "$backup/restore.sh"
if [ -d /home/root/xovi ]; then cp -a /home/root/xovi "$backup/xovi"; touch "$backup/had-xovi"; fi
systemd-run --unit="$unit" --on-active=360s /bin/sh "$backup/restore.sh"
systemctl is-active --quiet "$unit.timer" || { echo 'Recovery watchdog could not be armed.'; exit 1; }
trap 'result=$?; if [ "$result" != 0 ]; then /bin/sh "$backup/restore.sh" || echo "Automatic recovery failed. Keep backup: $backup"; fi' 0
trap 'exit 1' HUP INT TERM
mkdir -p /home/root/xovi
cp -a "$stage/xovi/." /home/root/xovi/
echo 'Building UI resources. Unlock your tablet if its screen asks for a code.'
if ! printf '\n' | timeout 180 /bin/bash /home/root/xovi/rebuild_hashtable >"$backup/hashtable.log" 2>&1; then
    echo "Resource rebuilding failed or timed out. See $backup/hashtable.log"; exit 1
fi
[ -s /home/root/xovi/exthome/qt-resource-rebuilder/hashtab ] || { echo 'The resource hashtable was not created.'; exit 1; }
timeout 60 /bin/bash /home/root/xovi/start
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    pid=$(systemctl show --property=MainPID --value xochitl)
    case "$pid" in ''|0|*[!0-9]*) sleep 1; continue;; esac
    if systemctl is-active --quiet xochitl && [ -r "/proc/$pid/maps" ]; then
        ready=1
        for library in xovi.so qt-resource-rebuilder.so appload.so literm.so; do
            grep -Fq "/$library" "/proc/$pid/maps" || ready=0
        done
        [ "$ready" = 1 ] && break
    fi
    sleep 1
done
[ "$ready" = 1 ] || { echo 'XOVI dependencies did not load into the tablet interface.'; exit 1; }
touch "$backup/committed"
systemctl stop "$unit.timer" || true
trap - 0 HUP INT TERM
printf 'Preparation complete. Backup: %s\n' "$backup"
'''.replace('__STAGE__', shlex.quote(stage)).replace('__BACKUP__', shlex.quote(backup)).replace('__UNIT__', shlex.quote(unit))


def preparation_archive(files, stage):
    contents = dict(files)
    contents['prepare.sh'] = preparation_script(stage, files).encode()
    contents['restore.sh'] = RESTORE_SCRIPT.encode()
    contents['SHA256SUMS'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(contents.items())).encode()
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as archive:
        for name, content in sorted(contents.items()):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o755 if name in ['xovi/start', 'xovi/stock', 'xovi/debug', 'xovi/rebuild_hashtable'] or name.endswith('.sh') else 0o644
            archive.addfile(info, io.BytesIO(content))
        for name in ['xovi/exthome/appload', 'xovi/exthome/qt-resource-rebuilder', 'xovi/services/xochitl.service']:
            info = tarfile.TarInfo(name)
            info.type, info.mode = tarfile.DIRTYPE, 0o755
            archive.addfile(info)
        for name, target in SYMLINKS.items():
            info = tarfile.TarInfo(name)
            info.type, info.linkname, info.mode = tarfile.SYMTYPE, target, 0o777
            archive.addfile(info)
    return data.getvalue()


def prepare_and_install(client, product, confirm, progress):
    # Lazy import avoids an installer/module import cycle and reuses the proven transport.
    from installer import archive, install, remote
    archive(product)  # Reject corrupt PaperDesk before downloading or changing anything.
    progress('Checking tablet model, OS and preparation requirements…')
    remote(client, eligibility_script())
    try:
        client.open_sftp().close()
    except Exception as exc:
        raise RuntimeError('SFTP is unavailable. Tablet preparation has not started.') from exc
    progress('Downloading and verifying pinned tablet dependencies…')
    files = dependency_files(fetch_assets())
    check = remote(client, compatibility_script(files))
    if not confirm('Prepare tablet and install PaperDesk', check + '\n\n' + RISK_NOTICE + '\n\nProceed with tablet preparation?'):
        return False
    stage = '/home/root/paperdesk-prepare-' + uuid.uuid4().hex
    payload = preparation_archive(files, stage)
    quoted = shlex.quote(stage)
    remote(client, 'mkdir -m 700 ' + quoted)
    try:
        progress('Uploading verified dependencies…')
        sftp = client.open_sftp()
        try:
            sftp.putfo(io.BytesIO(payload), stage + '/dependencies.tar.gz', file_size=len(payload))
        finally:
            sftp.close()
        digest = hashlib.sha256(payload).hexdigest()
        remote(client, f'cd {quoted} && echo "{digest}  dependencies.tar.gz" | sha256sum -c - && tar -xzf dependencies.tar.gz && sha256sum -c SHA256SUMS')
        progress('Preparing tablet. Keep USB connected; unlock the tablet if prompted…')
        remote(client, f'cd {quoted} && timeout -k 30 310 sh ./prepare.sh', timeout=350)
    finally:
        try:
            remote(client, 'rm -rf -- ' + quoted, timeout=30)
        except Exception:
            pass
    progress('Tablet prepared. Checking PaperDesk installation requirements…')
    try:
        return True if install(client, product, confirm, progress) else None
    except Exception as exc:
        raise RuntimeError('Tablet dependencies were prepared, but PaperDesk installation did not complete. Keep the backups and use Install PaperDesk to retry.\n' + str(exc)) from exc
