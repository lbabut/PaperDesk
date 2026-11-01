"""Read-only dependency checks performed before any tablet writes."""
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile


def check_windows():
    if sys.platform != 'win32' or sys.getwindowsversion().major < 10:
        raise RuntimeError('This installer requires Windows 10 or 11.')
    if struct.calcsize('P') != 8:
        raise RuntimeError('This installer requires 64-bit Windows.')
    if shutil.disk_usage(tempfile.gettempdir()).free < 64 * 1024 * 1024:
        raise RuntimeError('Not enough space on this computer. Free at least 64 MB in the temporary files folder.')
    # Exercise the bundled crypto provider instead of trusting imports alone.
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    key = Ed25519PrivateKey.generate()
    key.public_key().verify(key.sign(b'PaperDesk dependency check'), b'PaperDesk dependency check')
    destination = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'PaperDesk'
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile(dir=destination) as handle:
        handle.write(b'PaperDesk')


def tablet_check(product):
    """Generate a POSIX script; it only reads files and command availability."""
    payload_kib = sum((p.stat().st_size + 4095) // 4096 * 4
                      for p in product.rglob('*') if p.is_file())
    minimum_kib = payload_kib * 3 + 32768
    return r'''missing=0
problem() { printf 'Missing requirement: %s\n' "$1"; missing=1; }
for tool in sh id cat uname tar gzip sha256sum systemctl systemd-run cp rm mkdir chmod grep sed date mv touch df du awk wget openssl unzip flock wc tr mktemp; do
    command -v "$tool" >/dev/null 2>&1 || problem "tool $tool (ask your administrator to prepare the tablet system)"
done
[ "$missing" = 0 ] || exit 22
[ "$(id -u)" = 0 ] || problem 'tablet administrator access (root)'
case "$(uname -m)" in armv7l) ;; *) problem 'ARMv7 architecture used by reMarkable 2' ;; esac
[ -x /home/root/xovi/start ] || problem 'working XOVI start script'
[ -s /home/root/xovi/extensions.d/appload.so ] || problem 'backend AppLoad (appload.so)'
[ -d /home/root/xovi/exthome/appload ] || problem 'AppLoad apps directory'
[ -s /home/root/xovi/extensions.d/qt-resource-rebuilder.so ] || problem 'qt-resource-rebuilder extension'
[ -d /run/systemd/system ] || problem 'running systemd for Care'
[ -w /home/root ] || problem 'write access for apps and backups in /home/root'
[ -w /etc/systemd/system ] || problem 'write access for Care services in /etc/systemd/system'
openssl list -public-key-algorithms 2>/dev/null | grep -qi ED25519 || problem 'OpenSSL with Ed25519 signature support for Care'
if [ "$missing" = 0 ]; then
    existing=0
    for app in paperdesk paperterminal literm paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperpet shims; do
        if [ -e "/home/root/xovi/exthome/appload/$app" ]; then
            size=$(du -sk "/home/root/xovi/exthome/appload/$app" | awk '{print $1}') || exit 22
            case "$size" in ''|*[!0-9]*) problem 'size information for existing apps';; *) existing=$((existing + size));; esac
        fi
    done
    available=$(df -Pk /home/root | awk 'NR==2 {print $4}')
    case "$available" in ''|*[!0-9]*) problem 'free space information for the tablet';;
        *) required=$((__MINIMUM_KIB__ + existing * 2))
           [ "$available" -ge "$required" ] || problem "free space: $required KB required, $available KB available";;
    esac
fi
[ "$missing" = 0 ] || exit 22
printf 'Tablet requirements: OK\n'
printf 'Tablet system: '
if [ -r /etc/os-release ]; then sed -n 's/^VERSION_ID=//p' /etc/os-release; fi
printf 'VERSION='
cat /home/root/.local/share/paperdesk/current-version 2>/dev/null || true
printf '\n'
for app in __APP_IDS__; do
    if [ -e "/home/root/xovi/exthome/appload/$app" ]; then printf 'APP=%s\n' "$app"; fi
done
true
'''.replace('__MINIMUM_KIB__', str(minimum_kib)).replace('__APP_IDS__',
    'paperdesk paperterminal literm paperweb paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperpet shims')
