#!/usr/bin/env python3
import argparse,hashlib,json,os,pathlib,shlex,subprocess,tarfile,io,time
p=argparse.ArgumentParser(description='Run non-grabbing native Sketch regressions on the tablet ARM CPU; no UI restart.')
p.add_argument('--host',required=True);p.add_argument('--key',required=True);p.add_argument('--known-hosts',required=True);p.add_argument('--host-key-alias')
p.add_argument('--output',default='docs/papersketch-tablet-regressions.json')
p.add_argument('--charcoal-benchmark',action='store_true',help='Compare the current charcoal kernel with the frozen baseline at 48 and 80 px.')
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1]
cache=pathlib.Path(os.environ.get('PAPERDESK_TOOLCACHE','/home/lukasz/Documents/Codex/2026-09-25/m-2/work'))/'arm-toolchain/root'
work=root/'work/tablet-regressions';work.mkdir(parents=True,exist_ok=True)
names=['charcoal-speed','charcoal-layers','kneaded-strength','material','material-realism','pressure','touch','pen','display'];targets=[];shared=[]
if a.charcoal_benchmark:names=['charcoal-speed']
env=dict(os.environ,LD_LIBRARY_PATH=str(cache/'usr/lib/x86_64-linux-gnu'))
for name in names:
 source=root/('tests/test-sketch-'+name+'.cpp');target=work/name
 flags=[str(cache/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(cache),'-std=c++17','-O2','-marm','-pthread']
 if name=='charcoal-speed':
  library=target.with_suffix('.so')
  subprocess.run(flags+['-fPIC','-shared',str(root/'tests/test-sketch-charcoal-shared.cpp'),'-ldl','-lm','-o',str(library)],env=env,check=True,capture_output=True)
  subprocess.run(flags+[str(root/'tests/device/papersketch-material-runner.cpp'),'-ldl','-o',str(target)],env=env,check=True,capture_output=True)
  shared.append(library)
 else:
  subprocess.run(flags+[str(source),'-ldl','-lm','-o',str(target)],env=env,check=True,capture_output=True)
 targets.append(target)
ssh=['ssh','-i',a.key,'-o','UserKnownHostsFile='+a.known_hosts,'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=8']
if a.host_key_alias:ssh+=['-o','HostKeyAlias='+a.host_key_alias]
ssh+=['root@'+a.host]
def remote(command,data=None,timeout=120):
 r=subprocess.run(ssh+[command],input=data,capture_output=True,timeout=timeout)
 if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace')+' '+r.stdout.decode(errors='replace'))
 return r.stdout
def artworks():
 return remote('for f in /home/root/.local/share/paperdesk/sketch/cache-9b902d93d14b-*; do test -f "$f" || continue; sha256sum "$f"; done')
before=artworks();stage=remote('mktemp -d /home/root/.local/state/papersketch-cpu-tests.XXXXXX').decode().strip()
assert stage.startswith('/home/root/.local/state/papersketch-cpu-tests.')
report={'architecture':remote('uname -m').decode().strip(),'cases':[],'ui_restart':False,'device_input_grabbed':False}
try:
 stream=io.BytesIO()
 with tarfile.open(fileobj=stream,mode='w') as archive:
  for target in targets+shared:archive.add(target,arcname=target.name)
 remote('tar -xf - -C '+shlex.quote(stage),stream.getvalue())
 for target in targets:
  start=time.monotonic();output=remote(shlex.join([stage+'/'+target.name]+([stage+'/'+target.name+'.so'] if target.name=='charcoal-speed' else [])+(['benchmark'] if a.charcoal_benchmark else [])),timeout=180).decode()
  report['cases'].append({'shared_library_sha256':hashlib.sha256(target.with_suffix('.so').read_bytes()).hexdigest() if target.name=='charcoal-speed' else None,'name':target.name,'passed':True,'binary_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'seconds':round(time.monotonic()-start,3),'output':output[-12000:]})
  print('PASS',target.name,flush=True)
finally:
 report['artwork_preserved']=before==artworks()
 report['passed']=len(report['cases'])==len(names) and report['artwork_preserved']
 out=root/a.output;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+chr(10))
 remote('rm -rf -- '+shlex.quote(stage))
assert report['passed']
print('Report:',out)
