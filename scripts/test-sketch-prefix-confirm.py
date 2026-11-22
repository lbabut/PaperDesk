#!/usr/bin/env python3
"""Predeclared B/P/A/A/P/B comparison, ordinary then heavy; no production promotion."""
import argparse,hashlib,json,pathlib,shutil,subprocess
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--safe-state-confirmed',action='store_true');a=p.parse_args()
if not a.safe_state_confirmed:p.error('Current scratch discard/UI restart consent required')
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/prefix-confirm';out.mkdir(parents=True,exist_ok=False)
sources={
 'baseline':pathlib.Path('/home/lukasz/Documents/Codex/PaperDesk-sketch-rowspan-20261121'),
 'unmodified':pathlib.Path('/home/lukasz/Documents/Codex/PaperDesk-sketch-native-prefix-20261122'),
 'adaptive4':pathlib.Path('/home/lukasz/Documents/Codex/plan-400/sketch-prefix-ten-study-20261122/prefix-ten/01-minimum4')}
expected={'baseline':'29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7','unmodified':'3989ebc926a32ea77efed3ab9f7501775f41f37fb475e05287d2d3e665e2a8dc','adaptive4':'15926962d6aab9982981123cd6a9b4f90d3d53fd4434c8e1f07e69754475d2a4'}
connection=['--host','10.11.99.1','--host-key-alias','192.168.1.167','--key','/home/lukasz/.ssh/id_ed25519_remarkable','--known-hosts','/home/lukasz/.ssh/known_hosts']
ssh=['ssh','-F','/dev/null','-i','/home/lukasz/.ssh/id_ed25519_remarkable','-o','IdentitiesOnly=yes','-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6','root@10.11.99.1']
rcc='3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1'
for name,source in sources.items():
    dest=out/name
    for folder in ['scripts','tests','product/payload/apps/papersketch']:shutil.copytree(source/folder,dest/folder)
    assert hashlib.sha256((dest/'product/payload/apps/papersketch/native/papersketch-raster.so').read_bytes()).hexdigest()==expected[name]
    qml=hashlib.sha256((dest/'product/payload/apps/papersketch/ui/main.qml').read_bytes()).hexdigest()
    assert qml==('dda3e31c9113bb914afec256926c75858240dd3e5611c36448714f2bb8362819' if name=='baseline' else '34d26fffd8dabf057bd30ebf422b0f1643ef3094262dd9d4408efa82e61946e9')
results=[]
def remote(cmd):return subprocess.run(ssh+[cmd],capture_output=True,text=True,check=True,timeout=90).stdout
def check():
    s=remote('systemctl is-active xochitl; sha256sum /home/root/xovi/extensions.d/papersketch-raster.so; systemctl is-enabled remarkable-fail.service || true')
    assert s.splitlines()[0]=='active' and expected['baseline'] in s and 'masked' not in s,s
    return s
sequence=['baseline','unmodified','adaptive4','adaptive4','unmodified','baseline']
(out/'plan.json').write_text(json.dumps(dict(sequence=sequence,modes=['ordinary','heavy'],expected_modules=expected,interpretation='Selected adaptive4 from screening; not independent discovery. No lifecycle-timer patch included.'),indent=2)+'\n')
for mode in ['ordinary','heavy']:
 for index,name in enumerate(sequence,1):
    folder=out/name;runfolder=out/(mode+'-'+str(index)+'-'+name);runfolder.mkdir();backup=None
    try:
        check()
        if name!='baseline':
            receipt=runfolder/'install.json'
            install=subprocess.run(['python3',str(folder/'scripts/install-sketch-charcoal-uat.py'),'--safe-state-confirmed','--baseline','rowspan-20261121',*connection,'--output',str(receipt)],capture_output=True,text=True,timeout=150)
            (runfolder/'install.log').write_text(install.stdout+install.stderr)
            if receipt.exists():
                r=json.loads(receipt.read_text());backup=r['backup'] if r['status']=='installed_for_uat' else None
            assert install.returncode==0 and backup,'Install failed'
            assert backup.startswith('/home/root/.local/state/sketch-charcoal-uat.') and all(c.isalnum() or c in '/.-_' for c in backup)
        command=['python3',str(folder/'scripts/test-sketch-device-performance.py'),'--safe-state-confirmed',*connection,'--expected-installed-rcc',rcc,'--repeats','1','--output-dir',str(runfolder/'gui')]
        if name!='baseline':command+=['--candidate-probe','--baseline-qml','tests/fixtures/sketch-before-prefix.qml']
        if mode=='heavy':command+=['--high-rate-shading','--tilted-shading','--soft-charcoal']
        run=subprocess.run(command,capture_output=True,text=True,timeout=240,cwd=folder)
        (runfolder/'controller.log').write_text(run.stdout+run.stderr)
        report=json.loads((runfolder/'gui/run-1.json').read_text())
        assert all(report.get(k) is True for k in ['artwork_preserved','saved_files_preserved'])
        probe=report['results']['shading_probe'];assert not probe.get('runtime_errors',[])
        cases=probe['cases'];assert len(cases)==2 and all(c['input_samples']==1260 and c['input_stats'][1:]==[0,0] for c in cases)
        result=dict(mode=mode,index=index,name=name,passed=json.loads((runfolder/'gui/summary.json').read_text())['passed'],cases=[dict(id=c['id'],gap_ms=c['max_input_tick_gap_ms'],queue_ms=c['queue_latency']['p95_upper_ms'],tail_ms=c['release_to_drained_ms'],hz=c['achieved_input_hz']) for c in cases])
    finally:
        if backup:(runfolder/'rollback.log').write_text(remote('set -eu; test "$(systemctl is-enabled remarkable-fail.service)" = static; systemctl mask --runtime remarkable-fail.service; trap "systemctl unmask --runtime remarkable-fail.service" EXIT; sh '+backup+'/rollback.sh'))
        (runfolder/'restored.log').write_text(check())
    results.append(result);(out/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
check()
