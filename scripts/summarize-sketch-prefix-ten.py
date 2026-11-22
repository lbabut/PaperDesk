#!/usr/bin/env python3
"""Summarize all ten completed ordinary-rate probes, including failures."""
import datetime,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/prefix-ten'
manifest=json.loads((out/'manifest.json').read_text());runs=json.loads((out/'gui-results.json').read_text())
assert len(manifest)==10 and all(v['compiled'] and v['host_exact_passed'] for v in manifest)
assert len(runs)==12 and runs[0]['name']=='baseline-before' and runs[-1]['name']=='baseline-after'
variants=[r for r in runs if not r['name'].startswith('baseline-')]
assert {r['name'] for r in variants}=={m['name'] for m in manifest}
summary={
 'status':'ten_screening_experiments_completed_no_uat_promotion',
 'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'base_commit':'46bb6f4; original prefix QML without later lifecycle-timer repair, to isolate policy effects',
 'variants':manifest,'runs':runs,
 'passed_single_run_names':[r['name'] for r in variants if r['passed']],
 'failed_single_run_names':[r['name'] for r in variants if not r['passed']],
 'correctness':'All ten ARM modules built;20 targeted C++ host regressions passed. Every GUI report1260 samples/tool,no overflow/pending,original setting and checked saved cache files preserved. Not a full-library audit. Material arithmetic and24-event drain/16ms publication unchanged.',
 'cap_assertion':'Four capped-policy host tests require summarized>0 instead of>500, because their optimization intentionally handles a prefix only. Exact640 raw points/41contacts,images,pigment,pressure metadata and all other assertions remain unchanged.',
 'limitations':'One ordinary-rate pilot per variant and two controls, not randomized/statistical proof. Record actual achieved Hz, not an exact250Hz claim. Policies may remain inactive under low backlog. No heavy500Hz validation, full device workflow regression or physical panel/sensor latency measurement for these policies.',
 'deployment':'Staged candidate QML only; global native modules temporarily installed with own rollback after every candidate. Deployed main QML/RCC untouched; final baseline retained. No main/site/release/sales change.',
 'interpretation':'Controls charcoal gap150/203ms,queue56/53ms,tail102/103ms. Final control itself fails200ms GUI-gap gate, so single gap failures cannot prove a policy caused slowdown. Six single-run passes are screening candidates, not accepted improvements. No convincing universal winner selected.',
 'package_warning':'Root product remains inherited unmodified-prefix prototype, not a chosen adaptive package. The ten source/module variants are generated research artifacts under work/prefix-ten, with hashes in this report; do not install root package as the winning version.',
 'next_action':'Compare against unmodified-prefix control and repeat only a promising candidate in ordinary and heavy scenarios before combining with an independently validated lifecycle repair. Do not select a winner from a single best metric.'}
target=root/'docs/sketch-prefix-ten-20261122.json';target.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ['status','passed_single_run_names','failed_single_run_names']},indent=2))
