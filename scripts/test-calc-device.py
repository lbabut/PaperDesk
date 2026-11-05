#!/usr/bin/env python3
"""Isolated reMarkable Graph checks and guarded real-input Science bursts.

Preserves installed apps and user calculator settings. Does not measure optical
panel latency or use screenshots. Graph checks activate real control handlers;
Science uses two evdev touch streams, including overlapping fingers.
"""
import hashlib,io,json,shlex,subprocess,tarfile,tempfile,time
from pathlib import Path
import shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
KEYS=Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/keys')
SSH=['ssh','-F','/dev/null','-i',str(KEYS/'remarkable2_ed25519'),'-o','UserKnownHostsFile='+str(KEYS/'known_hosts'),'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','root@10.11.99.1']
APP='papercalc-science-graph-probe'
def remote(cmd,data=None):
    r=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=40)
    if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace') or r.stdout.decode(errors='replace'))
    return r.stdout
remote('set -eu; test -d /home/root/xovi/exthome/appload; ! systemctl is-active --quiet paperdesk-update.service; test -z "$(pidof paperdesk-rm-touchd || true)"; test ! -e /home/root/xovi/exthome/appload/'+APP)
backup=remote('mktemp -d /home/root/.local/state/papercalc-qa.XXXXXX').decode().strip()
assert backup.startswith('/home/root/.local/state/papercalc-qa.')
b=shlex.quote(backup);original=None;masked=False
source=ROOT/'product/payload/apps/papercalc'
report={'backup':backup,'inputs':[],'log':'','physicalTouchTested':False,'opticalLatencyMeasured':False,'source_hashes':{str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file() and p.suffix in ('.qml','.js')}}
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
        main.write_text(main.read_text().replace('property string mode:"Desk"','property var probeKeys:[];property string mode:"Desk"').replace('function key(value) {','function key(value) {probeKeys.push(value);'))
        (stage/'main.qml').write_text((ROOT/'tests/device/calc-science-graph.qml').read_text().replace('CONFIG',backup))
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
    pid=remote('pidof xochitl').decode().split()[0];done=set();deadline=time.monotonic()+150
    while time.monotonic()<deadline:
        log=remote('journalctl -u xochitl _PID='+pid+' --no-pager').decode(errors='replace');report['log']=log
        if 'CALC_PROBE_ACTIVATE' in log and 'activation' not in report:
            report['activation']=json.loads(remote(shlex.join([backup+'/input-driver','120','80']),b'702 1471\n'))
        for line in log.splitlines():
            if 'CALC_PROBE_TARGET ' not in line:continue
            raw=line.split('CALC_PROBE_TARGET ',1)[1];r=json.loads(raw[:raw.rfind('}')+1])
            if r['id'] in done:continue
            data=''.join(str(p[0])+' '+str(p[1])+'\n' for p in r['points']).encode()
            event=json.loads(remote(shlex.join([backup+'/input-driver',str(r['interval']),str(r['hold'])]),data))
            event['id']=r['id'];report['inputs'].append(event);done.add(r['id'])
        if 'CALC_PROBE_RESULT ' in log:
            raw=next(l for l in log.splitlines() if 'CALC_PROBE_RESULT ' in l).split('CALC_PROBE_RESULT ',1)[1];report['result']=json.loads(raw[:raw.rfind('}')+1]);break
        time.sleep(.2)
    if not report.get('result',{}).get('passed'):raise RuntimeError('Probe failed: '+log[-3500:])
finally:
    if original is not None:
        remote('systemctl stop xochitl; cp -p '+b+'/xochitl.conf /home/root/.config/remarkable/xochitl.conf; if test -d /home/root/xovi/exthome/appload/'+APP+'; then mv /home/root/xovi/exthome/appload/'+APP+' '+b+'/tested; fi; systemctl reset-failed xochitl; systemctl start xochitl')
    if masked:remote('systemctl unmask --runtime remarkable-fail.service')
    (ROOT/'work/papercalc-science-graph-device.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ('log','source_hashes')},indent=2))
