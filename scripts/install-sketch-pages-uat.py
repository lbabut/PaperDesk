#!/usr/bin/env python3
"""Pinned, reversible page-capacity UAT. No notebook migration or deletion."""
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
p.add_argument('--safe-state-confirmed', action='store_true')
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
if not a.safe_state_confirmed:
    p.error('Save and close the current drawing before restarting the interface')
root = Path(__file__).resolve().parents[1]
app = '/home/root/xovi/exthome/appload/papersketch/'
source = root / 'product/payload/apps/papersketch'
targets = {
    '/home/root/xovi/extensions.d/papersketch-raster.so': ('native/papersketch-raster.so', '29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7'),
    app+'native/papersketch-raster.so': ('native/papersketch-raster.so', 'e84e1271f9398200a789355562a682244c247cc1662f501cd1d7bcfd29481d9a'),
    app+'resources.rcc': ('resources.rcc', '3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1'),
    app+'ui/main.qml': ('ui/main.qml', 'dda3e31c9113bb914afec256926c75858240dd3e5611c36448714f2bb8362819'),
    app+'engine.js': ('engine.js', '34c3c14f08ae7a0f52716e77f54aec3ea7533d2668cd76aebacfac931dd3814f'),
}
ink = '/home/root/xovi/extensions.d/papersketch-ink.so'
ink_hash = '5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7'
ssh = ['ssh','-F','/dev/null','-i','/home/lukasz/.ssh/id_ed25519_remarkable',
       '-o','IdentitiesOnly=yes','-o','UserKnownHostsFile=/home/lukasz/.ssh/known_hosts',
       '-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes',
       '-o','BatchMode=yes','-o','ConnectTimeout=8','root@192.168.1.167']
def remote(command, data=None):
    return subprocess.run(ssh+[command],input=data,capture_output=True,check=True,timeout=90).stdout
def digest(path):
    return remote('sha256sum '+shlex.quote(path)).decode().split()[0]
def artwork():
    return remote('for f in /home/root/.local/share/paperdesk/sketch/cache-9b902d93d14b-*; do test -f "$f" || continue; sha256sum "$f"; done')
remote('set -eu; systemctl is-active --quiet xochitl; '
       'grep -q \'^IMG_VERSION="3.29.0.153"$\' /etc/os-release; '
       'test "$(cat /tmp/papersketch-ink)" = off; '
       '! systemctl is-active --quiet paperdesk-update.service')
assert digest(ink)==ink_hash, 'Preview baseline changed'
for path, (_, expected) in targets.items():
    assert digest(path)==expected, 'Baseline changed: '+path
payload={str(i):(source/relative).read_bytes() for i, (relative,_) in enumerate(targets.values())}
assert payload['0'][:5]==b'\x7fELF\x01' and int.from_bytes(payload['0'][18:20],'little')==40
backup=remote('mktemp -d /home/root/.local/state/sketch-pages-uat.XXXXXX').decode().strip()
assert backup.startswith('/home/root/.local/state/sketch-pages-uat.')
b=shlex.quote(backup)
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode='w') as archive:
    for name,data in payload.items():
        info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644
        archive.addfile(info,io.BytesIO(data))
remote('mkdir '+b+'/candidate; tar -xf - -C '+b+'/candidate',buf.getvalue())
expected_new={path:hashlib.sha256(payload[str(i)]).hexdigest() for i,path in enumerate(targets)}
for i,path in enumerate(targets):
    assert digest(backup+'/candidate/'+str(i))==expected_new[path]
mask=remote('systemctl is-enabled remarkable-fail.service || true').decode().strip()
owned_mask=mask not in ('masked','masked-runtime')
result={'status':'failed','backup':backup,'expected_new':expected_new,'owner_safe_state_confirmed':True}
backed_up=False
try:
    if owned_mask:remote('systemctl mask --runtime remarkable-fail.service')
    remote('systemctl stop xochitl')
    before=artwork();result['artwork_before_sha256']=hashlib.sha256(before).hexdigest()
    result['artwork_file_count']=len(before.splitlines())
    remote('set -eu; mkdir '+b+'/artwork; cp -p /home/root/.config/remarkable/xochitl.conf '+b+'/xochitl.conf; '
           'for f in /home/root/.local/share/paperdesk/sketch/cache-9b902d93d14b-*; do test -f "$f" || continue; cp -p "$f" '+b+'/artwork/; done')
    for line in before.decode().splitlines():
        sha,path=line.split(None,1)
        assert digest(backup+'/artwork/'+Path(path).name)==sha, 'Artwork backup mismatch'
    for i,(path,(_,expected)) in enumerate(targets.items()):
        remote('cp -p '+shlex.quote(path)+' '+b+'/previous-'+str(i))
        assert digest(backup+'/previous-'+str(i))==expected
    backed_up=True
    rollback='#!/bin/sh\nset -eu\nsystemctl stop xochitl\n'
    rollback+=''.join('cp -p '+b+'/previous-'+str(i)+' '+shlex.quote(path)+'\n' for i,path in enumerate(targets))
    rollback+='systemctl start xochitl\n'
    remote('cat > '+b+'/rollback-software.sh; chmod 700 '+b+'/rollback-software.sh',rollback.encode())
    for i,path in enumerate(targets):
        q=shlex.quote(path)
        remote('set -eu; cp '+b+'/candidate/'+str(i)+' '+q+'.pages-new; mv '+q+'.pages-new '+q)
        assert digest(path)==expected_new[path]
    remote('systemctl start xochitl');time.sleep(8)
    remote('systemctl is-active --quiet xochitl')
    assert digest(ink)==ink_hash
    after=artwork();assert after==before, 'User sketchbook changed during installation'
    result.update(status='installed_for_uat',artwork_preserved=True,artwork_after_sha256=hashlib.sha256(after).hexdigest())
except BaseException:
    if backed_up:
        remote('systemctl stop xochitl')
        for i,path in enumerate(targets):
            remote('cp -p '+b+'/previous-'+str(i)+' '+shlex.quote(path))
        result['status']='rolled_back'
    remote('systemctl start xochitl')
    raise
finally:
    if owned_mask:remote('systemctl unmask --runtime remarkable-fail.service')
    result['checked_at']=time.time()
    a.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
