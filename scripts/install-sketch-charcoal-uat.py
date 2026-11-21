#!/usr/bin/env python3
"""Reversible USB UAT of ONLY the two Sketch native modules; never a release."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shlex
import subprocess
import tarfile
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--host', default='10.11.99.1')
p.add_argument('--key', required=True)
p.add_argument('--known-hosts', required=True)
p.add_argument('--host-key-alias')
p.add_argument('--safe-state-confirmed', action='store_true')
p.add_argument('--output', required=True, type=Path)
p.add_argument('--baseline', choices=['original','charcoal-20261121','input24-20261121'], default='original')
a = p.parse_args()
if not a.safe_state_confirmed:
    p.error('Owner must permit the UI restart; save/close personal work first')
root = Path(__file__).resolve().parents[1]
names = ['papersketch-raster.so', 'papersketch-ink.so']
expected = dict(zip(names, [
    'e84e1271f9398200a789355562a682244c247cc1662f501cd1d7bcfd29481d9a',
    '2643b947f47a4b3cb27b241fe0da6f4f5b8f89db6da70374cc902a2c17e14bc5']))
if a.baseline=='charcoal-20261121':
    expected=dict(zip(names,[
        '227dd2ffedc7c1f867080d08ace59c40f545c09c333efd60537b4c8120f3e975',
        '5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7']))
if a.baseline=='input24-20261121':
    expected=dict(zip(names,[
        'be89afb13593bdb2fbcf193d22fc972c3208ae776e878fb7739561f5035e4858',
        '5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7']))
modules = root / 'product/payload/apps/papersketch/native'
payload = {n: (modules / n).read_bytes() for n in names}
for n, data in payload.items():
    if data[:5] != b'\x7fELF\x01' or int.from_bytes(data[18:20], 'little') != 40:
        p.error(n + ' is not a 32-bit ARM ELF')
ssh = ['ssh', '-F', '/dev/null', '-i', a.key, '-o', 'IdentitiesOnly=yes',
       '-o', 'UserKnownHostsFile=' + a.known_hosts, '-o', 'StrictHostKeyChecking=yes',
       '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8']
if a.host_key_alias:
    ssh += ['-o', 'HostKeyAlias=' + a.host_key_alias]
ssh += ['root@' + a.host]
def remote(cmd, data=None):
    return subprocess.run(ssh + [cmd], input=data, capture_output=True, check=True,
                          timeout=90).stdout.decode()
base = '/home/root/xovi/extensions.d/'
remote('set -eu; systemctl is-active --quiet xochitl; '
       'grep -q \'^IMG_VERSION="3.29.0.153"$\' /etc/os-release; '
       'test "$(stat -c %t:%T /dev/input/event2)" = d:42; '
       'test -z "$(pidof paperdesk-rm-touchd || true)"; '
       '! systemctl is-active --quiet paperdesk-update.service')
for n in names:
    actual = remote('sha256sum ' + base + n).split()[0]
    if actual != expected[n]:
        raise RuntimeError('Installed baseline changed: ' + n)
backup = remote('mktemp -d /home/root/.local/state/sketch-charcoal-uat.XXXXXX').strip()
if not backup.startswith('/home/root/.local/state/sketch-charcoal-uat.'):
    raise RuntimeError('Unexpected backup path')
b = shlex.quote(backup)
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode='w') as tf:
    for n, data in payload.items():
        info = tarfile.TarInfo(n); info.size = len(data); info.mode = 0o755
        tf.addfile(info, io.BytesIO(data))
remote('mkdir ' + b + '/candidate; tar -xf - -C ' + b + '/candidate', buf.getvalue())
rollback = ('#!/bin/sh\nset -eu\nsystemctl stop xochitl\n' + ''.join(
    'cp -p ' + b + '/previous-' + n + ' ' + base + n + '\n' for n in names) +
    'systemctl start xochitl\n')
remote('tee ' + b + '/rollback.sh >/dev/null; chmod 700 ' + b + '/rollback.sh', rollback.encode())
masked = remote('systemctl is-enabled remarkable-fail.service || true').strip()
owned_mask = masked not in ('masked', 'masked-runtime')
result = {'status': 'failed', 'backup': backup,
          'candidate_sha256': {n: hashlib.sha256(v).hexdigest() for n, v in payload.items()},
          'baseline_sha256': expected, 'scope': 'shared native modules only; installed app/resources and saved data untouched'}
copied = False
try:
    if owned_mask:
        remote('systemctl mask --runtime remarkable-fail.service')
    remote('systemctl stop xochitl')
    # Back up both originals before replacing either. No config or notebook writes.
    remote('set -eu; ' + '; '.join('cp -p ' + base + n + ' ' + b + '/previous-' + n for n in names))
    copied = True
    for n in names:
        remote('set -eu; cp ' + b + '/candidate/' + n + ' ' + base + n + '.uat-new; mv ' + base + n + '.uat-new ' + base + n)
    remote('systemctl start xochitl')
    time.sleep(8)
    remote('systemctl is-active --quiet xochitl')
    for n in names:
        if remote('sha256sum ' + base + n).split()[0] != result['candidate_sha256'][n]:
            raise RuntimeError('Post-install hash mismatch: ' + n)
    result['status'] = 'installed_for_uat'
except BaseException:
    if copied:
        remote('sh ' + b + '/rollback.sh')
        result['status'] = 'rolled_back'
    else:
        remote('systemctl start xochitl')
    raise
finally:
    if owned_mask:
        remote('systemctl unmask --runtime remarkable-fail.service')
    result['checked_at'] = time.time()
    a.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
