"""Build isolated SketchRaster probe test, not an app installer."""
import pathlib,subprocess,os
r=pathlib.Path(__file__).resolve().parents[1];cache=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work');tc=cache/'arm-toolchain/root';sdk=cache/'papersketch-qt-sdk/root/usr';inc=sdk/'include/x86_64-linux-gnu/qt6';zlib=cache/'arm-sysroot/root';w=r/'work/backend-probe-arm';w.mkdir(parents=True,exist_ok=True)
subprocess.run([str(sdk/'lib/qt6/libexec/moc'),'-I'+str(inc),str(r/'product/payload/apps/papersketch/native/papersketch-raster.cpp'),'-o',str(w/'papersketch-raster.moc')],check=True)
libs=r/'work/backend-probe-arm-libs'
for name in ['Core','Gui','Qml','Quick']:
 if not (libs/('libQt6'+name+'.so.6')).is_file():raise SystemExit('Supply authorized local tablet Qt libraries in '+str(libs))
cmd=[str(tc/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(tc),'-std=c++17','-O2','-marm','-fPIC','-pthread','-I'+str(w),'-I'+str(inc),'-idirafter',str(zlib/'usr/include')]+['-I'+str(inc/x) for x in ['QtCore','QtGui','QtQml','QtQuick']]+[str(r/'tests/test-sketch-backend-deferred.cpp'),'-L'+str(libs),'-L'+str(zlib/'lib/arm-linux-gnueabihf'),'-l:libQt6Quick.so.6','-l:libQt6Qml.so.6','-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-l:libz.so.1','-ldl','-Wl,--allow-shlib-undefined','-o',str(w/'test')]
p=subprocess.run(cmd,env=dict(os.environ,LD_LIBRARY_PATH=str(tc/'usr/lib/x86_64-linux-gnu')),capture_output=True,text=True);(w/'build.log').write_text(p.stdout+p.stderr);p.check_returncode()
