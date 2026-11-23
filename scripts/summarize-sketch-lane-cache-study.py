"""Scalar-only evidence from the diagnostic GUI run and separate ARM CPU runs."""
import argparse,json,hashlib,statistics
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--profile',type=Path,required=True);p.add_argument('--cpu',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
raw=json.loads((a.profile/'probe/run-1.json').read_text())
summary=json.loads((a.profile/'probe/summary.json').read_text())
assert (a.profile/'restored.txt').is_file()
c=next(c for c in raw['results']['shading_probe']['cases'] if c['id']=='pen-charcoal')
lanes=c['deferred_material']['lane_diagnostics'];pixels=sum(x['pixels'] for x in lanes)
assert all(x['clock_failures']==0 and x['pixels']==x['fresh_hits']+x['fallbacks'] for x in lanes)
record={
 'schema':'sketch-lane-cache-study-v1','decision':'cache_rejected_no_UAT',
 'profile':{'created_at':summary['created_at'],'lanes':lanes,
  'fallback_fraction':sum(x['fallbacks'] for x in lanes)/pixels,
  'row_fraction_of_instrumented_lane_cpu':sum(x['rows_cpu_us'] for x in lanes)/sum(x['cpu_us'] for x in lanes),
  'gui_gap_ms':c['max_input_tick_gap_ms'],'queue_p95_upper_ms':c['queue_latency']['p95_upper_ms'],'release_tail_ms':c['release_to_drained_ms'],
  'suite_passed':summary['passed'],'suite_failures':summary['failures'],
  'artwork_preserved':raw['artwork_preserved'],'saved_files_preserved':raw['saved_files_preserved'],'saved_file_count':raw['saved_file_count'],
  'no_automatic_save':raw['results']['shading_probe']['no_automatic_save'],
  'source_sha256':hashlib.sha256((a.profile/'probe/run-1.json').read_bytes()).hexdigest()},
 'arm_cache_runs':[],
 'limits':['Profile is an instrumented single synthetic GUI run, not uninstrumented speed or physical panel latency.',
  'Pixel counters and clock reads introduce overhead, including possible cache interference; fractions characterize this instrumented run.',
  'CPU benchmark is separate from GUI, compares exact varied traces and includes two execution orders per invocation.',
  'Second CPU invocation is noisier; preserve all outliers. No repeatable benefit, no module installation for cache candidate.',
  'No production/main/site changes. Diagnostic module restored from owned backup. Checked settings and17 caches are not a complete library audit.']}
for name in ('bench-1','bench-2'):
 path=a.cpu/(name+'.log');rows=[json.loads(line) for line in path.read_text().splitlines() if line.startswith('{')]
 assert len(rows)==24
 record['arm_cache_runs'].append({'name':name,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'rows':rows})
a.output.write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'fallback_fraction':record['profile']['fallback_fraction'],'row_cpu_fraction':record['profile']['row_fraction_of_instrumented_lane_cpu'],
 'soft_charcoal_median_ratios':[statistics.median(r['ratio'] for r in run['rows'] if r['tool']==5) for run in record['arm_cache_runs']]},indent=2))
