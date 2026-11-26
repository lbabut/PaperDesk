#!/usr/bin/env python3
"""Build/run focused stage instrumentation checks; no device deployment."""
import argparse
import json
import os
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--arm-libs',type=Path)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
root=Path(__file__).resolve().parents[1]
cache=Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work')
sdk=cache/'papersketch-qt-sdk/root/usr';inc=sdk/'include/x86_64-linux-gnu/qt6'
subprocess.run([str(sdk/'lib/qt6/libexec/moc'),'-I'+str(inc),str(root/'product/payload/apps/papersketch/native/papersketch-raster.cpp'),'-o',str(a.output/'papersketch-raster.moc')],check=True)
results=[]
for test in ['bench-sketch-worker-stages','test-sketch-worker-stage-counters','test-sketch-live-worker','test-sketch-seeded-tiles']:
 args=['g++','-std=c++17','-O2','-fPIC','-pthread','-I'+str(a.output),'-I'+str(inc)]
 args+=['-I'+str(inc/m) for m in ['QtCore','QtGui','QtQml','QtQuick']]
 args+=[str(root/'tests'/(test+'.cpp')),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-ldl','-lz','-o',str(a.output/test)]
 r=subprocess.run(args,capture_output=True,text=True)
 (a.output/(test+'-build.log')).write_text(r.stdout+r.stderr);r.check_returncode()
 for mode in (['burst','blocking','paced','burst seeded','blocking seeded','paced seeded'] if test.startswith('bench') else ['','seeded'] if test=='test-sketch-live-worker' else ['']):
  r=subprocess.run([str(a.output/test)]+mode.split(),env=dict(os.environ,QT_QPA_PLATFORM='offscreen'),capture_output=True,text=True,timeout=90)
  (a.output/(test+'-'+mode+'.log')).write_text(r.stdout+r.stderr);r.check_returncode()
  print(r.stdout.strip(),flush=True);results.append({'test':test,'mode':mode,'passed':True})
if a.arm_libs:
 tc=cache/'arm-toolchain/root';z=cache/'arm-sysroot/root'
 for test in ['bench-sketch-worker-stages','test-sketch-worker-stage-counters','test-sketch-seeded-tiles']:
  args=[str(tc/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(tc),'-std=c++17','-O2','-marm','-fPIC','-pthread','-I'+str(a.output),'-I'+str(inc),'-idirafter',str(z/'usr/include')]
  args+=['-I'+str(inc/m) for m in ['QtCore','QtGui','QtQml','QtQuick']]
  args+=[str(root/'tests'/(test+'.cpp')),'-L'+str(a.arm_libs),'-L'+str(z/'lib/arm-linux-gnueabihf'),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-l:libz.so.1','-ldl','-Wl,--allow-shlib-undefined','-o',str(a.output/(test+'-arm'))]
  r=subprocess.run(args,env=dict(os.environ,LD_LIBRARY_PATH=str(tc/'usr/lib/x86_64-linux-gnu')),capture_output=True,text=True)
  (a.output/(test+'-arm-build.log')).write_text(r.stdout+r.stderr);r.check_returncode()
(a.output/'checks.json').write_text(json.dumps(results,indent=2)+'\n')
