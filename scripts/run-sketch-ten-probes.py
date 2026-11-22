#!/usr/bin/env python3
"""Run generated standalone CPU probes only, retaining every failure."""
import json,pathlib,subprocess,statistics,time,argparse
p=argparse.ArgumentParser(); p.add_argument('--only',nargs='*'); p.add_argument('--label',default=''); args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'work/ten-probes'
ssh=['ssh','-F','/dev/null','-i','/home/lukasz/.ssh/id_ed25519_remarkable','-o','IdentitiesOnly=yes','-o','HostKeyAlias=192.168.1.167','-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6','root@10.11.99.1']
results=[]
for item in json.loads((out/'manifest.json').read_text()):
 name=item['name']
 if args.only and name not in args.only:continue
 start=time.time()
 p=subprocess.run(ssh+['/tmp/sketch-ten-20261122/'+name],capture_output=True,text=True,timeout=180)
 (out/(name+args.label+'.arm.log')).write_text(p.stdout+p.stderr)
 rows=[json.loads(line) for line in p.stdout.splitlines() if line.startswith('{')]
 groups={}
 for row in rows:groups.setdefault(str(row['tool'])+'/'+str(row['tilt']),[]).append(row['ratio'])
 result=dict(name=name,exit_code=p.returncode,elapsed_s=time.time()-start,exact_state_passed=p.returncode==0 and len(rows)==24,ratios={k:dict(mean=statistics.mean(v),worst=max(v)) for k,v in groups.items()})
 results.append(result)
 (out/('results'+args.label+'.json')).write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(result),flush=True)
