"""Ten explicit ARM code-generation probes, CPU only; no app installation."""
import pathlib,subprocess,os,json,re,hashlib,sys
resume='--resume-builds' in sys.argv
r=pathlib.Path(__file__).resolve().parents[1];w=r/'work/codegen-ten';w.mkdir(parents=True,exist_ok=resume)
tc=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/arm-toolchain/root')
env=dict(os.environ,LD_LIBRARY_PATH=str(tc/'usr/lib/x86_64-linux-gnu'))
variants={
 'baseline':['-O2'],
 '01-o3':['-O3'],
 '02-no-vector':['-O2','-fno-tree-vectorize'],
 '03-unroll':['-O2','-funroll-loops'],
 '04-o3-unroll':['-O3','-funroll-loops'],
 '05-no-slp':['-O2','-fno-tree-slp-vectorize'],
 '06-no-ipa-cp':['-O2','-fno-ipa-cp'],
 '07-no-small-inline':['-O2','-fno-inline-small-functions'],
 '08-no-math-errno':['-O2','-fno-math-errno'],
 '09-cortex-a7':['-O2','-mcpu=cortex-a7'],
 '10-o3-cortex-a7':['-O3','-mcpu=cortex-a7']}
(w/'plan.json').write_text(json.dumps({'variants':variants,'scope':'Compiler probes, not ten algorithm improvements; no fast-math; two opposite ARM orders; no UI or deployment'},indent=2))
for name,flags in variants.items():
 folder=w/name
 if resume and (folder/'arm').exists():continue
 folder.mkdir(exist_ok=resume)
 if name!='baseline':
  # ARM-only CPU selection has no meaning on the host. ARM digest is checked below.
  hostFlags=[f for f in flags if not f.startswith('-mcpu=')]
  if (folder/'host-build.log').exists():
   (folder/'host-build.initial.log').write_bytes((folder/'host-build.log').read_bytes())
  cmd=['g++','-std=c++17','-pthread',*hostFlags,'tests/bench-sketch-rowspan.cpp','-o',str(folder/'host-fidelity')]
  p=subprocess.run(cmd,cwd=r,capture_output=True,text=True);(folder/'host-build.log').write_text(p.stdout+p.stderr);p.check_returncode()
  p=subprocess.run([str(folder/'host-fidelity')],capture_output=True,text=True,timeout=120);(folder/'host-fidelity.log').write_text(p.stdout+p.stderr);p.check_returncode()
 cmd=[str(tc/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(tc),'-std=c++17','-marm','-static','-pthread',*flags,'tests/bench-sketch-material-profile.cpp','-o',str(folder/'arm')]
 p=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True);(folder/'arm-build.log').write_text(p.stdout+p.stderr);p.check_returncode()
 print('BUILT_AND_TESTED',name,flush=True)
key='/home/lukasz/.ssh/id_ed25519_remarkable';opts=['-F','/dev/null','-i',key,'-o','IdentitiesOnly=yes','-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6']
ssh=['ssh',*opts,'root@10.11.99.1'];remote='/tmp/sketch-codegen-ten-20261123'
p=subprocess.run(ssh+['mkdir -p '+remote+'; cat /proc/cpuinfo; systemctl is-active xochitl; sha256sum /home/root/xovi/extensions.d/papersketch-raster.so'],capture_output=True,text=True,check=True);(w/('before-resume.log' if resume else 'before.log')).write_text(p.stdout+p.stderr)
for name in variants:subprocess.run(['scp',*opts,str(w/name/'arm'),'root@10.11.99.1:'+remote+'/'+name],check=True)
names=list(variants)[1:];sequence=['baseline',*names,'baseline',*reversed(names),'baseline']
results=json.loads((w/'results.json').read_text()) if resume and (w/'results.json').exists() else []
for index,name in enumerate(sequence):
 if any(x['index']==index for x in results):continue
 log=w/(str(index)+'-'+name+'.log')
 if log.exists():log.rename(log.with_suffix('.initial.log'))
 p=subprocess.run(ssh+['chmod 700 '+remote+'/'+name+'; '+remote+'/'+name],capture_output=True,text=True,timeout=60)
 (w/(str(index)+'-'+name+'.log')).write_text(p.stdout+p.stderr);p.check_returncode()
 match=re.search(r'wall_us=(\d+) digest=(\d+)',p.stdout);assert match,p.stdout
 results.append(dict(index=index,name=name,wall_us=int(match[1]),digest=match[2],digest_matches=match[2]=='2347201020787794403'));(w/'results.json').write_text(json.dumps(results,indent=2));print(results[-1],flush=True)
p=subprocess.run(ssh+['systemctl is-active xochitl; sha256sum /home/root/xovi/extensions.d/papersketch-raster.so; systemctl is-enabled remarkable-fail.service'],capture_output=True,text=True,check=True);(w/'after.log').write_text(p.stdout+p.stderr)
assert '29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7' in p.stdout
