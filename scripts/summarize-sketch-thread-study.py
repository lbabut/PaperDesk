"""Export selected non-private accounting evidence; preserve failed gates."""
import argparse
import hashlib
import json
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--runs',type=Path,nargs='+',required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
out={'schema':1,'uat_ready':False,'runs':[],
     'limitations':['Read-only task counters around synthetic evdev injection, not whole-stroke CPU or physical panel latency.',
                    'Boundary scans and SSH delay included; no zero-cost observer/control claim.',
                    'Thread names do not prove worker roles. Runnable wait excludes blocking and overlaps across threads.']}
for folder in a.runs:
    report_path=folder/'probe/run-1.json'
    r=json.loads(report_path.read_text())
    s=json.loads((folder/'probe/summary.json').read_text())
    assert r['artwork_preserved'] and r['saved_files_preserved']
    item={'run':folder.name,'report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest(),
          'observer':'single_process_c' if r.get('thread_observer_sha256') else 'shell_high_overhead_excluded',
          'observer_sha256':r.get('thread_observer_sha256'),'suite_passed':s['passed'],'failures':s['failures'],
          'process_pid':r.get('thread_profile_process_pid'),
          'diagnostic_preview_disabled':r.get('diagnostic_preview_disabled',False),
          'native_modules':{Path(line.split()[1]).name:line.split()[0] for line in r['native_modules']},
          'preservation':{k:r[k] for k in ['artwork_preserved','saved_files_preserved','saved_file_count']},
          'cases':[],'thread_profiles':[]}
    for c in r['results']['shading_probe']['cases']:
        item['cases'].append({k:c[k] for k in ['id','input_samples','input_stats','max_input_tick_gap_ms','queue_latency','release_to_drained_ms','tile_visible_before_release','achieved_input_hz']})
        item['cases'][-1]['fast_pen_preview_enabled']=c.get('fast_pen_preview_enabled')
    for t in r['thread_profiles']:
        item['thread_profiles'].append({'id':t['id'],**t['delta']})
    out['runs'].append(item)
if any(r['observer']=='shell_high_overhead_excluded' for r in out['runs']):
    out['limitations'].append('Shell sampler retained but excluded from low-overhead evidence; no thresholds relaxed.')
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(out,indent=2)+'\n')
print(a.output)
