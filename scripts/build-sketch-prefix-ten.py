#!/usr/bin/env python3
"""Ten independent exact prefix-policy probes; never install or change material math."""
import concurrent.futures,hashlib,json,os,pathlib,shutil,subprocess
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/prefix-ten';out.mkdir(parents=True,exist_ok=False)
native='product/payload/apps/papersketch/native/papersketch-raster.cpp';base=(root/native).read_text()
variants=[]
for n,minimum in enumerate([4,8,12,16,20,24],1):
    variants.append((f'{n:02}-minimum{minimum}',base.replace('if(contact && tool>=0','if(events.size()>='+str(minimum)+' && contact && tool>=0'),False))
for n,cap in enumerate([4,8,12,16],7):
    variants.append((f'{n:02}-cap{cap}',base.replace('while(consumed<events.size())','while(consumed<events.size() && consumed<'+str(cap)+')'),True))
sdk=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/papersketch-qt-sdk/root/usr');inc=sdk/'include/x86_64-linux-gnu/qt6'
def build(item):
    name,source,capped=item;dest=out/name;dest.mkdir()
    for folder in ['scripts','tests','product/payload/apps/papersketch']:shutil.copytree(root/folder,dest/folder)
    (dest/native).write_text(source)
    if capped:
        test=dest/'tests/test-sketch-native-prefix.cpp'
        test.write_text(test.read_text().replace('x.summarized>500','x.summarized>0'))
    p=subprocess.run(['python3',str(dest/'scripts/build-sketch-raster.py')],capture_output=True,text=True)
    (dest/'build.log').write_text(p.stdout+p.stderr);passed=p.returncode==0
    for target in (['native-prefix','input-fidelity'] if passed else []):
        binary=dest/('host-'+target)
        cmd=['g++','-std=c++17','-O2','-fPIC','-pthread','-I'+str(dest/'work/papersketch-native-ink'),'-I'+str(inc)]
        cmd+=['-I'+str(inc/m) for m in ['QtCore','QtGui','QtQml','QtQuick']]
        cmd+=[str(dest/('tests/test-sketch-'+target+'.cpp')),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-ldl','-lz','-o',str(binary)]
        compile_result=subprocess.run(cmd,capture_output=True,text=True)
        text=compile_result.stdout+compile_result.stderr
        if compile_result.returncode:passed=False
        else:
            run=subprocess.run([str(binary)],env=dict(os.environ,QT_QPA_PLATFORM='offscreen'),capture_output=True,text=True)
            text+=run.stdout+run.stderr;passed=run.returncode==0
        (dest/(target+'.host.log')).write_text(text)
        if not passed:break
    module=dest/'product/payload/apps/papersketch/native/papersketch-raster.so'
    result=dict(name=name,compiled=p.returncode==0,host_exact_passed=passed,capped_summary_coverage_assertion=capped,source_sha256=hashlib.sha256(source.encode()).hexdigest(),module_sha256=hashlib.sha256(module.read_bytes()).hexdigest())
    print(json.dumps(result),flush=True);return result
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(build,variants))
(out/'manifest.json').write_text(json.dumps(results,indent=2)+'\n')
assert len(results)==10 and all(r['compiled'] and r['host_exact_passed'] for r in results)
