#!/usr/bin/env python3
"""Install Paper Calc on an authenticated tablet; --test runs an isolated probe.

Never invokes screenshot utilities. Test input uses the existing guarded evdev
injector and restores Xochitl settings, removes the probe, then restarts Xochitl.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import time

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--host',required=True)
p.add_argument('--key',required=True)
p.add_argument('--known-hosts',required=True)
p.add_argument('--host-key-alias')
p.add_argument('--test',action='store_true')
p.add_argument('--output',default='work/papercalc-device.json')
a=p.parse_args()
if a.test:p.error('--test requires an updated device probe; use scripts/test-calc.sh for host tests')
root=Path(__file__).resolve().parents[1]
source=root/'product/payload/apps/papercalc'
cache=Path(os.environ.get('PAPERDESK_TOOLCACHE','/home/lukasz/Documents/Codex/2026-09-25/m-2/work'))
ssh=['ssh','-F','/dev/null','-i',a.key,'-o','UserKnownHostsFile='+a.known_hosts,'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8']
if a.host_key_alias:ssh+=['-o','HostKeyAlias='+a.host_key_alias]
ssh+=['root@'+a.host]
def remote(command,data=None):
    r=subprocess.run(ssh+[command],input=data,capture_output=True,timeout=60)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace') or r.stdout.decode(errors='replace'))
    return r.stdout
app_id='papercalc-probe' if a.test else 'papercalc'
remote('set -eu; test -d /home/root/xovi/exthome/appload; ! systemctl is-active --quiet paperdesk-update.service; test -z "$(pidof paperdesk-rm-touchd || true)"')
backup=remote('mktemp -d /home/root/.local/state/papercalc-dev.XXXXXX').decode().strip()
assert backup.startswith('/home/root/.local/state/papercalc-dev.')
b=shlex.quote(backup)
mask=remote('systemctl is-enabled remarkable-fail.service || true').decode().strip()
mask_here=mask not in ('masked','masked-runtime')
original=None
success=False
report={'source_qml_sha256':hashlib.sha256((source/'ui/main.qml').read_bytes()).hexdigest(),'engine_sha256':hashlib.sha256((source/'calc.js').read_bytes()).hexdigest(),'backup':backup}
try:
    with tempfile.TemporaryDirectory() as d:
        stage=Path(d)/app_id;stage.mkdir()
        import shutil
        if a.test:
            shutil.copytree(source,stage/'subject',ignore=shutil.ignore_patterns('resources.rcc'))
            qml=stage/'subject/ui/main.qml'
            qml.write_text(qml.read_text().replace('category: "PaperCalc"','category: "PaperCalcProbe'+str(time.time_ns())+'"'))
            shutil.copy2(root/'tests/device/papercalc.qml',stage/'main.qml')
            import xml.etree.ElementTree as ET
            resource=ET.Element('RCC');qresource=ET.SubElement(resource,'qresource',prefix='/')
            ET.SubElement(qresource,'file').text='main.qml'
            for entry in ET.parse(source/'application.qrc').findall('.//file'):
                ET.SubElement(qresource,'file').text='subject/'+entry.text
            (stage/'application.qrc').write_text(ET.tostring(resource,encoding='unicode'))
            manifest=json.loads((source/'manifest.json').read_text());manifest.update(id=app_id,name='Paper Calc test',entry='/main.qml')
            (stage/'manifest.json').write_text(json.dumps(manifest))
            shutil.copy2(source/'icon.png',stage/'icon.png')
            subprocess.run([str(cache/'qt-rcc-pkg/root/usr/lib/qt5/bin/rcc'),'--binary','application.qrc','-o','resources.rcc'],cwd=stage,check=True)
            arm=cache/'arm-toolchain/root';driver=Path(d)/'input-driver'
            subprocess.run([str(arm/'usr/bin/arm-linux-gnueabihf-gcc-12'),'--sysroot='+str(arm),'-O2',str(root/'tests/device/papersketch-input-driver.c'),'-o',str(driver)],env=dict(os.environ,LD_LIBRARY_PATH=str(arm/'usr/lib/x86_64-linux-gnu')),check=True)
            remote('cat > '+b+'/input-driver; chmod 700 '+b+'/input-driver',driver.read_bytes())
        else:
            for name in ['resources.rcc','manifest.json','icon.png']:shutil.copy2(source/name,stage/name)
        stream=io.BytesIO()
        with tarfile.open(fileobj=stream,mode='w') as archive:archive.add(stage,arcname=app_id)
        remote('mkdir '+b+'/stage; tar -xf - -C '+b+'/stage',stream.getvalue())
        report['resource_sha256']=hashlib.sha256((stage/'resources.rcc').read_bytes()).hexdigest()
    if mask_here:remote('systemctl mask --runtime remarkable-fail.service')
    remote('systemctl stop xochitl')
    original=remote('cat /home/root/.config/remarkable/xochitl.conf')
    remote('cp -p /home/root/.config/remarkable/xochitl.conf '+b+'/xochitl.conf; if test -d /home/root/xovi/exthome/appload/'+app_id+'; then mv /home/root/xovi/exthome/appload/'+app_id+' '+b+'/previous; fi; mv '+b+'/stage/'+app_id+' /home/root/xovi/exthome/appload/'+app_id)
    rows=[];skip=False
    for line in original.decode().splitlines():
        if line.strip()=='[PaperDeskE2E]':skip=True;continue
        if line.startswith('['):skip=False
        if not skip:rows.append(line)
    remote('cat > /home/root/.config/remarkable/xochitl.conf', ('\n'.join(rows)+'\n[PaperDeskE2E]\nautostart=true\napplicationId='+app_id+'\n').encode())
    remote('systemctl reset-failed xochitl; systemctl start xochitl')
    pid=remote('pidof xochitl').decode().split()[0]
    injected=set();deadline=time.monotonic()+(120 if a.test else 85)
    while time.monotonic()<deadline:
        logs=remote('journalctl -u xochitl _PID='+pid+' --no-pager').decode(errors='replace')
        if not a.test and 'PaperCalc ready offline' in logs:success=True;break
        for line in logs.splitlines():
            if 'CALC_INPUT ' not in line:continue
            raw=line.split('CALC_INPUT ',1)[1];request=json.loads(raw[:raw.rfind('}')+1])
            if request['id'] in injected:continue
            mode=request['mode'];points=request['start']+request['end']
            if mode=='finger':points=[points[0],1871-points[1],points[2],1871-points[3]]
            elif mode=='pen':points=[20966-points[1]*20966/1872,points[0]*15725/1404,20966-points[3]*20966/1872,points[2]*15725/1404]
            else:raise RuntimeError('Unknown input mode')
            event=json.loads(remote(shlex.join([backup+'/input-driver',mode]+[str(round(v)) for v in points]+[request['pattern']])))
            event['id']=request['id'];report.setdefault('input',[]).append(event);injected.add(request['id'])
        if 'CALC_RESULT ' in logs:
            line=next(l for l in logs.splitlines() if 'CALC_RESULT ' in l);raw=line.split('CALC_RESULT ',1)[1]
            report['results']=json.loads(raw[:raw.rfind('}')+1]);success=report['results']['passed'];break
        time.sleep(1)
    report['log']=logs
    if not success:raise RuntimeError('Paper Calc did not pass: '+logs[-6000:])
    report['installed_hash']=remote('sha256sum /home/root/xovi/exthome/appload/'+app_id+'/resources.rcc').decode().split()[0]
    assert report['installed_hash']==report['resource_sha256']
finally:
    if original is not None and (a.test or not success):
        remote('systemctl stop xochitl; cp -p '+b+'/xochitl.conf /home/root/.config/remarkable/xochitl.conf; if test -d /home/root/xovi/exthome/appload/'+app_id+'; then mv /home/root/xovi/exthome/appload/'+app_id+' '+b+'/tested; fi; if test -d '+b+'/previous; then mv '+b+'/previous /home/root/xovi/exthome/appload/'+app_id+'; fi; systemctl reset-failed xochitl; systemctl start xochitl')
    remote('systemctl is-active --quiet xochitl || { systemctl reset-failed xochitl; systemctl start xochitl; }')
    if mask_here:remote('systemctl unmask --runtime remarkable-fail.service')
    report['success']=success
    output=root/a.output;output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='log'},indent=2,ensure_ascii=False))
