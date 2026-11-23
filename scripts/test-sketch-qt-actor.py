"""Host offscreen Qt experiment; no tablet or installed application changes."""
import pathlib,subprocess,os,json
r=pathlib.Path(__file__).resolve().parents[1];w=r/'work/qt-actor';w.mkdir(parents=True,exist_ok=False)
inc=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/papersketch-qt-sdk/root/usr/include/x86_64-linux-gnu/qt6')
cmd=['g++','-std=c++17','-O2','-fPIC','-pthread','-I'+str(inc),'-I'+str(inc/'QtCore'),'-I'+str(inc/'QtGui'),str(r/'tests/bench-sketch-qt-actor.cpp'),'-l:libQt6Gui.so.6','-l:libQt6Core.so.6','-o',str(w/'bench')]
p=subprocess.run(cmd,capture_output=True,text=True);(w/'build.log').write_text(p.stdout+p.stderr);p.check_returncode()
env=dict(os.environ,QT_QPA_PLATFORM='offscreen');results=[]
sequence=[('sync',False),('actor',False),('actor',True),('sync',True),('actor',False),('sync',False)]
for i,(mode,paced) in enumerate(sequence):
 p=subprocess.run([str(w/'bench'),*(['--sync'] if mode=='sync' else []),*(['--paced'] if paced else [])],env=env,capture_output=True,text=True,timeout=30)
 (w/(str(i)+'.log')).write_text(p.stdout+p.stderr);p.check_returncode()
 result=json.loads(p.stdout.strip().splitlines()[-1]);results.append(result);print(result,flush=True)
(w/'results.json').write_text(json.dumps(results,indent=2))
