#!/usr/bin/env python3
"""Install only the tested prefix QML/RCC for limited UAT; retain UI rollback."""
import argparse,hashlib,io,json,pathlib,shlex,subprocess,tarfile,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--safe-state-confirmed',action='store_true')
p.add_argument('--host',default='10.11.99.1');p.add_argument('--host-key-alias')
p.add_argument('--key',required=True);p.add_argument('--known-hosts',required=True)
p.add_argument('--output',required=True,type=pathlib.Path)
a=p.parse_args()
if not a.safe_state_confirmed:p.error('Explicit safe UI restart confirmation required')
root=pathlib.Path(__file__).resolve().parents[1]
base='/home/root/xovi/exthome/appload/papersketch/'
expected={'ui/main.qml':'dda3e31c9113bb914afec256926c75858240dd3e5611c36448714f2bb8362819','resources.rcc':'3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1'}
payload={n:(root/'product/payload/apps/papersketch'/n).read_bytes() for n in expected}
ssh=['ssh','-F','/dev/null','-i',a.key,'-o','IdentitiesOnly=yes','-o','UserKnownHostsFile='+a.known_hosts,'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8']
if a.host_key_alias:ssh+=['-o','HostKeyAlias='+a.host_key_alias]
ssh+=['root@'+a.host]
def remote(cmd,data=None):return subprocess.run(ssh+[cmd],input=data,capture_output=True,check=True,timeout=90).stdout.decode()
remote('set -eu; systemctl is-active --quiet xochitl; ! systemctl is-active --quiet paperdesk-update.service; test -z "$(pidof paperdesk-rm-touchd || true)"')
checks={base+n:h for n,h in expected.items()}
checks.update({'/home/root/xovi/extensions.d/papersketch-raster.so':'3989ebc926a32ea77efed3ab9f7501775f41f37fb475e05287d2d3e665e2a8dc','/home/root/xovi/extensions.d/papersketch-ink.so':'5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7',base+'engine.js':'34c3c14f08ae7a0f52716e77f54aec3ea7533d2668cd76aebacfac931dd3814f'})
for n,h in checks.items():
    if remote('sha256sum '+shlex.quote(n)).split()[0]!=h:raise RuntimeError('Baseline mismatch: '+n)
backup=remote('mktemp -d /home/root/.local/state/sketch-prefix-ui.XXXXXX').strip()
if not backup.startswith('/home/root/.local/state/sketch-prefix-ui.'):raise RuntimeError('Invalid backup path')
b=shlex.quote(backup)
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode='w') as tf:
    for n,data in payload.items():
        info=tarfile.TarInfo(n);info.size=len(data);info.mode=0o644;tf.addfile(info,io.BytesIO(data))
remote('mkdir -p '+b+'/candidate; tar -xf - -C '+b+'/candidate',buf.getvalue())
rollback='#!/bin/sh\nset -eu\nsystemctl stop xochitl\n'+''.join('cp -p '+b+'/previous-'+n.replace('/','-')+' '+base+n+'\n' for n in expected)+'systemctl start xochitl\n'
remote('tee '+b+'/rollback.sh >/dev/null; chmod 700 '+b+'/rollback.sh',rollback.encode())
owned=remote('systemctl is-enabled remarkable-fail.service || true').strip() not in ('masked','masked-runtime')
receipt={'status':'failed','backup':backup,'baseline_sha256':expected,'candidate_sha256':{n:hashlib.sha256(data).hexdigest() for n,data in payload.items()},'scope':'UI/RCC only; native rollback is separate; no user library writes'}
copied=False
try:
    if owned:remote('systemctl mask --runtime remarkable-fail.service')
    remote('systemctl stop xochitl')
    remote('set -eu; '+'; '.join('cp -p '+base+n+' '+b+'/previous-'+n.replace('/','-') for n in expected));copied=True
    for n in expected:remote('set -eu; cp '+b+'/candidate/'+n+' '+base+n+'.uat-new; mv '+base+n+'.uat-new '+base+n)
    remote('systemctl start xochitl');time.sleep(8)
    remote('systemctl is-active --quiet xochitl')
    for n,h in receipt['candidate_sha256'].items():
        if remote('sha256sum '+base+n).split()[0]!=h:raise RuntimeError('Post-install mismatch: '+n)
    receipt['status']='installed_for_limited_uat'
except BaseException:
    if copied:remote('sh '+b+'/rollback.sh');receipt['status']='rolled_back'
    else:remote('systemctl start xochitl')
    raise
finally:
    if owned:remote('systemctl unmask --runtime remarkable-fail.service')
    receipt['checked_at']=time.time();a.output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
