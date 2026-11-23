"""Build isolated Qt harness using local copies of tablet Qt shared libraries."""
import pathlib,os,subprocess
r=pathlib.Path(__file__).resolve().parents[1];w=r/'work/qt-actor'
cache=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work');tc=cache/'arm-toolchain/root';inc=cache/'papersketch-qt-sdk/root/usr/include/x86_64-linux-gnu/qt6'
for name in ['libQt6Core.so.6','libQt6Gui.so.6']:
 if not (w/'arm-libs'/name).is_file():raise SystemExit('Copy authorized tablet library into work/qt-actor/arm-libs: '+name)
cmd=[str(tc/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(tc),'-std=c++17','-O2','-marm','-fPIC','-pthread','-I'+str(inc),'-I'+str(inc/'QtCore'),'-I'+str(inc/'QtGui'),str(r/'tests/bench-sketch-qt-actor.cpp'),'-L'+str(w/'arm-libs'),'-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-Wl,--allow-shlib-undefined','-o',str(w/'arm-bench')]
p=subprocess.run(cmd,env=dict(os.environ,LD_LIBRARY_PATH=str(tc/'usr/lib/x86_64-linux-gnu')),capture_output=True,text=True)
(w/'arm-build.log').write_text(p.stdout+p.stderr);p.check_returncode()
