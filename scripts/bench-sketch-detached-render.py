"""Build/run isolated real SketchTile renderer; never installs an app."""
import pathlib,subprocess,os,sys
r=pathlib.Path(__file__).resolve().parents[1];cache=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work');tc=cache/'arm-toolchain/root';sdk=cache/'papersketch-qt-sdk/root/usr';inc=sdk/'include/x86_64-linux-gnu/qt6';zlib=cache/'arm-sysroot/root'
arm='--arm' in sys.argv;live='--live-test' in sys.argv;w=r/('work/'+('live-' if live else 'render-')+('arm' if arm else 'host'));w.mkdir(parents=True,exist_ok=True)
subprocess.run([str(sdk/'lib/qt6/libexec/moc'),'-I'+str(inc),str(r/'product/payload/apps/papersketch/native/papersketch-raster.cpp'),'-o',str(w/'papersketch-raster.moc')],check=True)
cmd=([str(tc/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(tc),'-marm','-idirafter',str(zlib/'usr/include')] if arm else ['g++'])+['-std=c++17','-O2','-fPIC','-pthread','-I'+str(w),'-I'+str(inc)]+['-I'+str(inc/x) for x in ['QtCore','QtGui','QtQml','QtQuick']]+[str(r/('tests/test-sketch-live-worker.cpp' if live else 'tests/bench-sketch-detached-render.cpp'))]
if arm:cmd+=['-L'+str(r/'work/backend-probe-arm-libs'),'-L'+str(zlib/'lib/arm-linux-gnueabihf'),'-Wl,--allow-shlib-undefined']
cmd+=['-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-ldl','-l:libz.so.1','-o',str(w/'bench')]
env=dict(os.environ)
if arm:env['LD_LIBRARY_PATH']=str(tc/'usr/lib/x86_64-linux-gnu')
p=subprocess.run(cmd,env=env,capture_output=True,text=True);(w/'build.log').write_text(p.stdout+p.stderr);p.check_returncode()
if not arm:
 for stride,mode in ([(1,'live')] if live else [(1,'sync'),(1,'async'),(8,'async'),(24,'async'),(24,'sync')]):
  p=subprocess.run([str(w/'bench'),str(stride),mode],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QSG_RENDER_LOOP='basic'),capture_output=True,text=True,timeout=30)
  (w/(str(stride)+'-'+mode+'.log')).write_text(p.stdout+p.stderr);print(p.stdout+p.stderr,flush=True);p.check_returncode()
