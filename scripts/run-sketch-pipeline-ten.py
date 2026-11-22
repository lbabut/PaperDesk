#!/usr/bin/env python3
"""Owner-approved disposable scratch only. Guarded GUI probes, rollback each."""
import pathlib,subprocess,json,time,argparse,os
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/pipeline-ten'
parser=argparse.ArgumentParser();parser.add_argument('--safe-state-confirmed',action='store_true');parser.add_argument('--only',nargs='*');parser.add_argument('--label',default='');parser.add_argument('--skip-baselines',action='store_true');args=parser.parse_args()
assert args.safe_state_confirmed,'Current scratch must be owner-approved disposable'
connection=['--host','10.11.99.1','--host-key-alias','192.168.1.167','--key','/home/lukasz/.ssh/id_ed25519_remarkable','--known-hosts','/home/lukasz/.ssh/known_hosts']
ssh=['ssh','-F','/dev/null','-i','/home/lukasz/.ssh/id_ed25519_remarkable','-o','IdentitiesOnly=yes','-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6','root@10.11.99.1']
baseline='29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7'
rcc='3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1'
results=[]
def remote(command):return subprocess.run(ssh+[command],capture_output=True,text=True,check=True).stdout
def check_baseline():
 text=remote('systemctl is-active xochitl; sha256sum /home/root/xovi/extensions.d/papersketch-raster.so; systemctl is-enabled remarkable-fail.service || true')
 assert text.splitlines()[0]=='active' and baseline in text and 'masked' not in text,text
 return text
def run_probe(folder,directory):
 p=subprocess.run(['python3',str(folder/'scripts/test-sketch-device-performance.py'),'--safe-state-confirmed','--high-rate-shading','--tilted-shading','--soft-charcoal',*connection,'--expected-installed-rcc',rcc,'--repeats','1','--output-dir',str(directory)],capture_output=True,text=True)
 (directory/'controller.log').write_text(p.stdout+p.stderr)
 raw=json.loads((directory/'run-1.json').read_text())
 assert raw['artwork_preserved'] and raw['saved_files_preserved'],'Saved-state preservation failed'
 cases=raw['results']['shading_probe']['cases']
 assert len(cases)==2 and all(c['input_samples']==1260 and c['input_stats'][1:]==[0,0] for c in cases),'Missing/overflowed inputs'
 return dict(exit_code=p.returncode,cases=[dict(id=c['id'],gap_ms=c['max_input_tick_gap_ms'],queue_ms=c['queue_latency']['p95_upper_ms'],tail_ms=c['release_to_drained_ms'],hz=c['achieved_input_hz'],native=c['native_latency']) for c in cases])
def smoke(folder,name):
 include=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/papersketch-qt-sdk/root/usr/include/x86_64-linux-gnu/qt6')
 batch=int(name.split('batch')[1]) if 'batch' in name else 24
 test=folder/'tests/test-sketch-input-fidelity.cpp'
 text=test.read_text().replace('batch.size()<=24','batch.size()<='+str(batch))
 text=text.replace('queue["batches"].toUInt()==26','queue["batches"].toUInt()=='+str((601+batch-1)//batch))
 test.write_text(text)
 log=[]
 for target in ['input-fidelity','material-integration']:
  command=['g++','-std=c++17','-O2','-fPIC','-pthread','-I'+str(folder/'work/papersketch-native-ink'),'-I'+str(include)]
  command+=['-I'+str(include/m) for m in ['QtCore','QtGui','QtQml','QtQuick']]
  binary=folder/('smoke-'+target)
  command += [str(folder/('tests/test-sketch-'+target+'.cpp')),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-ldl','-lz','-o',str(binary)]
  p=subprocess.run(command,capture_output=True,text=True);log.append(p.stdout+p.stderr)
  if p.returncode:break
  p=subprocess.run([str(binary)],env=dict(os.environ,QT_QPA_PLATFORM='offscreen'),capture_output=True,text=True);log.append(p.stdout+p.stderr)
  if p.returncode:break
 (folder/'smoke.log').write_text('\n'.join(log))
 return p.returncode==0
check_baseline()
basefolder=root
for position in ([] if args.skip_baselines else ['before']):
 directory=out/('baseline-'+position+args.label)
 result=dict(name='baseline-'+position,**run_probe(basefolder,directory));results.append(result)
 (out/('gui-results'+args.label+'.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
for item in json.loads((out/'manifest.json').read_text()):
 name=item['name']
 if args.only and name not in args.only:continue
 folder=out/name;directory=folder/('gui'+args.label)
 print('SMOKE '+name,flush=True)
 if not smoke(folder,name):
  result=dict(name=name,smoke_passed=False,installed=False);results.append(result)
  (out/('gui-results'+args.label+'.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True);continue
 receipt=folder/'install.json';backup=None
 try:
  check_baseline()
  p=subprocess.run(['python3',str(folder/'scripts/install-sketch-charcoal-uat.py'),'--safe-state-confirmed','--baseline','rowspan-20261121',*connection,'--output',str(receipt)],capture_output=True,text=True)
  (folder/'install.log').write_text(p.stdout+p.stderr)
  if receipt.exists():
   installed=json.loads(receipt.read_text());backup=installed['backup'] if installed['status']=='installed_for_uat' else None
  assert p.returncode==0 and backup,'Install did not complete'
  assert backup.startswith('/home/root/.local/state/sketch-charcoal-uat.') and all(c.isalnum() or c in '/.-_' for c in backup)
  result=dict(name=name,**run_probe(folder,directory))
 finally:
  if backup:
   command='set -eu; test "$(systemctl is-enabled remarkable-fail.service)" = static; systemctl mask --runtime remarkable-fail.service; trap "systemctl unmask --runtime remarkable-fail.service" EXIT; sh '+backup+'/rollback.sh'
   (folder/'rollback.log').write_text(remote(command))
  (folder/'restored.log').write_text(check_baseline())
 results.append(result);(out/('gui-results'+args.label+'.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
if not args.skip_baselines:
 directory=out/('baseline-after'+args.label)
 result=dict(name='baseline-after',**run_probe(basefolder,directory));results.append(result)
 (out/('gui-results'+args.label+'.json')).write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(result),flush=True)
check_baseline()
