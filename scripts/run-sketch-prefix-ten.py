#!/usr/bin/env python3
"""Ten staged-QML ordinary-rate probes with per-candidate rollback; explicit scratch consent."""
import argparse,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/prefix-ten'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--safe-state-confirmed',action='store_true');args=p.parse_args()
if not args.safe_state_confirmed:p.error('Owner consent to discard current scratch/restart is required')
connection=['--host','10.11.99.1','--host-key-alias','192.168.1.167','--key','/home/lukasz/.ssh/id_ed25519_remarkable','--known-hosts','/home/lukasz/.ssh/known_hosts']
ssh=['ssh','-F','/dev/null','-i','/home/lukasz/.ssh/id_ed25519_remarkable','-o','IdentitiesOnly=yes','-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6','root@10.11.99.1']
baseline='29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7';rcc='3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1'
basefolder=pathlib.Path('/home/lukasz/Documents/Codex/PaperDesk-sketch-rowspan-20261121')
results=[]
def remote(cmd):return subprocess.run(ssh+[cmd],capture_output=True,text=True,check=True,timeout=90).stdout
def check():
    text=remote('systemctl is-active xochitl; sha256sum /home/root/xovi/extensions.d/papersketch-raster.so; systemctl is-enabled remarkable-fail.service || true')
    assert text.splitlines()[0]=='active' and baseline in text and 'masked' not in text,text
    return text
def probe(folder,directory,candidate):
    cmd=['python3',str(folder/'scripts/test-sketch-device-performance.py'),'--safe-state-confirmed',*connection,'--expected-installed-rcc',rcc,'--repeats','1','--output-dir',str(directory)]
    if candidate:cmd+=['--candidate-probe','--baseline-qml','tests/fixtures/sketch-before-prefix.qml']
    run=subprocess.run(cmd,capture_output=True,text=True,timeout=240,cwd=folder)
    (directory/'controller.log').write_text(run.stdout+run.stderr)
    raw=json.loads((directory/'run-1.json').read_text())
    assert raw['artwork_preserved'] and raw['saved_files_preserved'],'State preservation not verified'
    cases=raw['results']['shading_probe']['cases']
    assert len(cases)==2 and all(c['input_samples']==1260 and c['input_stats'][1:]==[0,0] for c in cases),'Lost/overflow/pending input'
    assert not raw['results']['shading_probe'].get('runtime_errors',[]),'Runtime error'
    return dict(exit_code=run.returncode,passed=json.loads((directory/'summary.json').read_text())['passed'],cases=[dict(id=c['id'],gap_ms=c['max_input_tick_gap_ms'],queue_ms=c['queue_latency']['p95_upper_ms'],tail_ms=c['release_to_drained_ms'],hz=c['achieved_input_hz']) for c in cases])
def save(result):
    results.append(result);(out/'gui-results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
check();save(dict(name='baseline-before',**probe(basefolder,out/'baseline-before',False)))
for item in json.loads((out/'manifest.json').read_text()):
    assert item['compiled'] and item['host_exact_passed']
    name=item['name'];folder=out/name;receipt=folder/'install.json';backup=None
    try:
        check()
        install=subprocess.run(['python3',str(folder/'scripts/install-sketch-charcoal-uat.py'),'--safe-state-confirmed','--baseline','rowspan-20261121',*connection,'--output',str(receipt)],capture_output=True,text=True,timeout=150)
        (folder/'install.log').write_text(install.stdout+install.stderr)
        if receipt.exists():
            r=json.loads(receipt.read_text());backup=r['backup'] if r['status']=='installed_for_uat' else None
        assert install.returncode==0 and backup,'Install failed'
        assert backup.startswith('/home/root/.local/state/sketch-charcoal-uat.') and all(c.isalnum() or c in '/.-_' for c in backup)
        result=dict(name=name,**probe(folder,folder/'gui',True))
    finally:
        if backup:
            (folder/'rollback.log').write_text(remote('set -eu; test "$(systemctl is-enabled remarkable-fail.service)" = static; systemctl mask --runtime remarkable-fail.service; trap "systemctl unmask --runtime remarkable-fail.service" EXIT; sh '+backup+'/rollback.sh'))
        (folder/'restored.log').write_text(check())
    save(result)
save(dict(name='baseline-after',**probe(basefolder,out/'baseline-after',False)));check()
