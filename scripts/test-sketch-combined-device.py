#!/usr/bin/env python3
"""Explicit staged candidate regressions; no unattended scheduling."""
import argparse,json,pathlib,runpy,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output-dir',type=pathlib.Path,default=root/'work/combined-device')
p.add_argument('--only',nargs='+',choices=['ordinary','workflow','fidelity','eraser','controls'])
a=p.parse_args();out=a.output_dir.resolve();out.mkdir(parents=True,exist_ok=False)
common=['--safe-state-confirmed','--candidate-probe','--baseline-qml','tests/fixtures/sketch-before-prefix.qml','--expected-installed-rcc','3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1','--host','10.11.99.1','--host-key-alias','192.168.1.167','--key','/home/lukasz/.ssh/id_ed25519_remarkable','--known-hosts','/home/lukasz/.ssh/known_hosts']
results=[]
for name,flags in [('ordinary',['--shading-probe']),('workflow',['--workflow-probe']),('fidelity',['--fidelity-probe']),('eraser',['--eraser-probe']),('controls',['--controls-probe'])]:
    if a.only and name not in a.only:continue
    path=out/(name+'.json')
    with (out/(name+'.log')).open('w') as log:
        p=subprocess.run([sys.executable,str(root/'scripts/run-sketch-native-guarded.py'),*common,*flags,'--output',str(path)],stdout=log,stderr=subprocess.STDOUT,cwd=root)
    report=json.loads(path.read_text()) if path.exists() else {}
    result=dict(probe=name,exit_code=p.returncode,artwork_preserved=report.get('artwork_preserved'),saved_files_preserved=report.get('saved_files_preserved'))
    if name=='ordinary':
        summarize=runpy.run_path(str(root/'scripts/test-sketch-device-performance.py'))['summarize']
        result['performance_summary']=summarize([report],expected_input_hz=250)
        if not result['performance_summary']['passed']:result['exit_code']=1
    results.append(result);print(json.dumps(result),flush=True)
    (out/'summary.json').write_text(json.dumps(results,indent=2)+'\n')
    if result['exit_code'] or not all(report.get(k) is True for k in ('artwork_preserved','saved_files_preserved')):sys.exit(1)
