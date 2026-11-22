#!/usr/bin/env python3
"""Audit complete GUI reports and emit only non-personal aggregate evidence."""
import pathlib,json
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/pipeline-ten'
first=json.loads((out/'gui-results.json').read_text());retry=json.loads((out/'gui-results-batch-retest.json').read_text())
merged={v['name']:v for v in first if 'cases' in v};merged.update({v['name']:v for v in retry if 'cases' in v})
names=[v['name'] for v in json.loads((out/'manifest.json').read_text())]
assert len(names)==10 and len(set(names))==10 and all(n in merged for n in names)
reports=list(out.glob('*/gui*/run-1.json'))+list(out.glob('baseline-*/run-1.json'))
reports=[p for p in reports if 'setup-failed' not in str(p)]
assert len(reports)==12,len(reports)
rates=[]
for file in reports:
 d=json.loads(file.read_text());assert d['artwork_preserved'] and d['saved_files_preserved'] and d['saved_file_count']==17
 for c in d['results']['shading_probe']['cases']:
  assert c['input_samples']==1260 and c['input_stats'][1:]==[0,0]
  rates.append(c['achieved_input_hz'])
assert min(rates)>=400 and max(rates)<=550
summary=dict(baseline_commit='802925a',experiments=[merged[n] for n in names],controls=[merged['baseline-before'],merged['baseline-after']],gui_reports=len(reports),preservation_all=True,checked_saved_files_per_report=17,samples_per_tool=1260,input_overflow_or_pending=False,actual_hz_range=[min(rates),max(rates)],new_uat_accepted=False,installed_raster_sha256='29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7',physical_panel_latency_measured=False)
dest=root/'docs/sketch-pipeline-ten-20261122';dest.mkdir(exist_ok=True)
(dest/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ['experiments','controls']},indent=2))
