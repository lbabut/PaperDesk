"""Targeted real SketchRaster regressions; isolated host files, no device."""
import pathlib,subprocess,os,sys
r=pathlib.Path(__file__).resolve().parents[1];s=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/papersketch-qt-sdk/root/usr');inc=s/'include/x86_64-linux-gnu/qt6';w=r/('work/backend-probe-final' if '--finish' in sys.argv else 'work/backend-probe-verified');w.mkdir(parents=True,exist_ok=False)
subprocess.run(['bash',str(r/'scripts/build-sketch.sh')],check=True)
subprocess.run([str(s/'lib/qt6/libexec/moc'),'-I'+str(inc),str(r/'product/payload/apps/papersketch/native/papersketch-raster.cpp'),'-o',str(w/'papersketch-raster.moc')],check=True)
for name in (['backend-deferred','release-resource','publication','workflow'] if '--finish' in sys.argv else ['backend-deferred','native-prefix','input-fidelity','latency','release-resource','publication','workflow']):
 cmd=['g++','-std=c++17','-O2','-fPIC','-pthread','-I'+str(w),'-I'+str(inc)]+['-I'+str(inc/x) for x in ['QtCore','QtGui','QtQml','QtQuick']]+[str(r/('tests/test-sketch-'+name+'.cpp')),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-ldl','-lz','-o',str(w/name)]
 p=subprocess.run(cmd,capture_output=True,text=True);(w/(name+'-build.log')).write_text(p.stdout+p.stderr);p.check_returncode()
 p=subprocess.run([str(w/name)],env=dict(os.environ,QT_QPA_PLATFORM='offscreen'),capture_output=True,text=True,timeout=120);(w/(name+'.log')).write_text(p.stdout+p.stderr);print(name,p.stdout,p.stderr,flush=True);p.check_returncode()
