#!/usr/bin/env python3
"""Guarded reMarkable regression for rapid 1+1+... contacts.

Runs a separate AppLoad app with isolated calculator settings and restores the
launcher configuration on exit. Tests sensor-frame handoffs, overlapping fingers,
single-slot reuse, 50 presses/s and a deliberately busy GUI. No optical timing.
"""
import argparse,hashlib,io,json,shlex,subprocess,tarfile,tempfile,time
from pathlib import Path
import shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
KEYS=Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/keys')
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--host',default='10.11.99.1')
parser.add_argument('--host-key-alias')
parser.add_argument('--output',default='work/papercalc-repeat-device.json')
a=parser.parse_args()
SSH=['ssh','-F','/dev/null','-i',str(KEYS/'remarkable2_ed25519'),'-o','UserKnownHostsFile='+str(KEYS/'known_hosts'),'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8']
if a.host_key_alias:SSH+=['-o','HostKeyAlias='+a.host_key_alias]
SSH+=['root@'+a.host]
APP='papercalc-repeat-probe'
def remote(cmd,data=None):
    r=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=40)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace') or r.stdout.decode(errors='replace'))
    return r.stdout
remote('set -eu; test -d /home/root/xovi/exthome/appload; ! systemctl is-active --quiet paperdesk-update.service; test -z "$(pidof paperdesk-rm-touchd || true)"; test ! -e /home/root/xovi/exthome/appload/'+APP)
# Fail before mutating device state if a reboot left XOVI inactive.
remote('set -eu; pid=$(pidof xochitl); grep -q /home/root/xovi/xovi.so /proc/$pid/maps')
backup=remote('mktemp -d /home/root/.local/state/papercalc-qa.XXXXXX').decode().strip()
assert backup.startswith('/home/root/.local/state/papercalc-qa.')
b=shlex.quote(backup);original=None;masked=False
source=ROOT/'product/payload/apps/papercalc'
report={'backup':backup,'inputs':[],'log':'','physicalTouchTested':False,'opticalLatencyMeasured':False,'source_hashes':{str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file() and p.suffix in ('.qml','.js')}}
def save_report():
    output=ROOT/a.output;output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
save_report()
try:
    driver=ROOT/'work/calc-burst-input-arm'
    arm=Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/arm-toolchain/root')
    import os
    subprocess.run([str(arm/'usr/bin/arm-linux-gnueabihf-gcc-12'),'--sysroot='+str(arm),'-O2',str(ROOT/'tests/device/calc-burst-input.c'),'-o',str(driver)],env=dict(os.environ,LD_LIBRARY_PATH=str(arm/'usr/lib/x86_64-linux-gnu')),check=True)
    remote('cat > '+b+'/input-driver; chmod 700 '+b+'/input-driver',driver.read_bytes())
    with tempfile.TemporaryDirectory() as tmp:
        stage=Path(tmp)/APP;stage.mkdir()
        shutil.copytree(source,stage/'subject',ignore=shutil.ignore_patterns('resources.rcc'))
        main=stage/'subject/ui/main.qml'
        main.write_text(main.read_text().replace('property string mode:"Desk"','property var probeKeys:[];property string mode:"Desk"').replace('function officeKey(k){','function officeKey(k){probeKeys.push(k);'))
        (stage/'main.qml').write_text((ROOT/'tests/device/calc-repeat.qml').read_text().replace('CONFIG',backup))
        tree=ET.Element('RCC');q=ET.SubElement(tree,'qresource',prefix='/');ET.SubElement(q,'file').text='main.qml'
        for e in ET.parse(stage/'subject/application.qrc').findall('.//file'):ET.SubElement(q,'file').text='subject/'+e.text
        (stage/'application.qrc').write_text(ET.tostring(tree,encoding='unicode'))
        (stage/'manifest.json').write_text(json.dumps({'id':APP,'name':'Paper Calc QA','entry':'/main.qml','supportsScaling':True,'loadsBackend':False,'icon':'icon.png'}))
        shutil.copy2(source/'icon.png',stage/'icon.png')
        subprocess.run(['/home/lukasz/Documents/Codex/2026-09-25/m-2/work/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc','--binary','application.qrc','-o','resources.rcc'],cwd=stage,check=True)
        buf=io.BytesIO()
        with tarfile.open(fileobj=buf,mode='w') as t:t.add(stage,arcname=APP)
        remote('mkdir '+b+'/stage; tar -xf - -C '+b+'/stage',buf.getvalue())
    mask=remote('systemctl is-enabled remarkable-fail.service || true').decode().strip()
    if mask not in ('masked','masked-runtime'):remote('systemctl mask --runtime remarkable-fail.service');masked=True
    remote('systemctl stop xochitl')
    original=remote('cat /home/root/.config/remarkable/xochitl.conf')
    remote('cp -p /home/root/.config/remarkable/xochitl.conf '+b+'/xochitl.conf; mv '+b+'/stage/'+APP+' /home/root/xovi/exthome/appload/'+APP)
    rows=[];skip=False
    for line in original.decode().splitlines():
        if line.strip()=='[PaperDeskE2E]':skip=True;continue
        if line.startswith('['):skip=False
        if not skip:rows.append(line)
    remote('cat > /home/root/.config/remarkable/xochitl.conf', ('\n'.join(rows)+'\n[PaperDeskE2E]\nautostart=true\napplicationId='+APP+'\n').encode())
    remote('systemctl reset-failed xochitl; systemctl start xochitl')
    pid=remote('pidof xochitl').decode().split()[0];done=set();deadline=time.monotonic()+240
    while time.monotonic()<deadline:
        log=remote('journalctl -u xochitl _PID='+pid+' --no-pager').decode(errors='replace');report['log']=log
        if 'CALC_PROBE_ACTIVATE' in log and 'activation' not in report:
            report['activation']=json.loads(remote(shlex.join([backup+'/input-driver','120','80']),b'702 1471\n'))
        for line in log.splitlines():
            if 'CALC_PROBE_TARGET ' not in line:continue
            raw=line.split('CALC_PROBE_TARGET ',1)[1];r=json.loads(raw[:raw.rfind('}')+1])
            if r['id'] in done:continue
            data=''.join(str(p[0])+' '+str(p[1])+'\n' for p in r['points']).encode()
            event=json.loads(remote(shlex.join([backup+'/input-driver',str(r['interval']),str(r['hold']),str(r.get('slots',2)),str(r.get('grouped',0))]),data))
            event['id']=r['id'];report['inputs'].append(event);done.add(r['id'])
        if 'CALC_PROBE_RESULT ' in log:
            raw=next(l for l in log.splitlines() if 'CALC_PROBE_RESULT ' in l).split('CALC_PROBE_RESULT ',1)[1];report['result']=json.loads(raw[:raw.rfind('}')+1]);break
        time.sleep(.2)
    if not report.get('result',{}).get('passed'):raise RuntimeError('Probe failed: '+log[-3500:])
finally:
    # Keep recovery coordinates even if Wi-Fi vanishes during cleanup.
    save_report()
    errors=[]
    if original is not None:
        try:
            remote('systemctl stop xochitl; cp -p '+b+'/xochitl.conf /home/root/.config/remarkable/xochitl.conf; if test -d /home/root/xovi/exthome/appload/'+APP+'; then mv /home/root/xovi/exthome/appload/'+APP+' '+b+'/tested; fi; systemctl reset-failed xochitl; systemctl start xochitl')
        except Exception as error:errors.append(str(error))
    if masked:
        try:remote('systemctl unmask --runtime remarkable-fail.service')
        except Exception as error:errors.append(str(error))
    report['recovery_complete']=not errors;report['recovery_errors']=errors;save_report()
    if errors:raise RuntimeError('Device recovery incomplete; saved backup and details in '+a.output)
print(json.dumps({k:v for k,v in report.items() if k not in ('log','source_hashes')},indent=2))
