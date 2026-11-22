#!/usr/bin/env python3
"""Summarize the predeclared ordinary/heavy confirmation without promoting a winner."""
import datetime,json,pathlib,statistics
root=pathlib.Path(__file__).resolve().parents[1];out=root/'work/prefix-confirm'
plan=json.loads((out/'plan.json').read_text());runs=json.loads((out/'results.json').read_text())
assert len(runs)==12
groups={}
for mode in plan['modes']:
    subset=[r for r in runs if r['mode']==mode]
    assert [r['name'] for r in subset]==plan['sequence']
    groups[mode]={}
    for name in ['baseline','unmodified','adaptive4']:
        rows=[r for r in subset if r['name']==name];assert len(rows)==2
        metrics={}
        for tool in ['pen-graphite','pen-charcoal']:
            cases=[next(c for c in r['cases'] if c['id']==tool) for r in rows]
            metrics[tool]={k:dict(median=statistics.median(c[k] for c in cases),minimum=min(c[k] for c in cases),maximum=max(c[k] for c in cases)) for k in ['gap_ms','queue_ms','tail_ms','hz']}
        groups[mode][name]=dict(passed_runs=sum(r['passed'] for r in rows),runs=2,metrics=metrics)
summary={
 'status':'confirmation_complete_no_automatic_uat',
 'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'plan':plan,'groups':groups,'raw_metrics':runs,
 'fidelity':'Every report1260 input samples/tool,no overflow/pending,original setting and checked saved cache files preserved; no runtime errors. Scoped checks, not full-library audit. Same pinned modules and QML, no new material math or training.',
 'limitations':'Adaptive4 selected from previous10-policy screen, selection bias. Two runs/condition/mode, fixed balanced order, not randomized statistical evidence. Ordinary requested250Hz uses actual measured rates; heavy requested500Hz. Modes also differ in charcoal type/tilt, so compare conditions within a mode only. No physical panel/sensor latency or full device workflow qualification.',
 'deployment':'Staged prefix QML only; lifecycle-timer repair deliberately excluded. Each tested module restored to baseline. Root product remains inherited prototype, not a new installable adaptive package. No accepted UAT,main,website,release,sales or canonical-tree changes.',
 'interpretation':'Ordinary unmodified2/2 and adaptive2/2 pass, baseline0/2. Heavy all conditions0/2 pass. Unmodified heavy tail2463/2605ms versus baseline2694/3057ms (~11.9% lower two-run median in this cohort). Adaptive heavy2545/6205ms;6205ms spike not reproduced, and its two-run median is not a typical-performance estimate. No demonstrated benefit justifies adaptive4 complexity. Earlier combined-package failures cannot automatically be blamed on prefix batching; lifecycle integration remains a separate hypothesis, not a proven cause.',
 'next_action':'Keep simple prefix as research candidate, do not promote adaptive4. Profile complete input-handler/QML/render scheduling and separately isolate a lifecycle fix without ordinary-rate regression. No automatic UAT: heavy absolute gates still fail. Do not add gains or infer causation from two pilots.'}
outlier=json.loads((out/'heavy-3-adaptive4/gui/run-1.json').read_text())['results']['shading_probe']['cases'][1]
summary['diagnostic_outlier']={k:outlier[k] for k in ['max_input_tick_gap_ms','release_to_drained_ms','native_latency']}
summary['diagnostic_note']='Outlier advance_total3.440s versus first unmodified3.120s and first baseline3.081s, while tail jumps to6.205s. These scopes overlap, are not exclusive timers and do not identify the cause. Do not attribute all delay to pigment arithmetic.'
(root/'docs/sketch-prefix-confirm-20261122.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(groups,indent=2))
