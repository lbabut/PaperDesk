#!/usr/bin/env python3
"""Select complete private raw contacts for offline work; NEVER inject input.

The selection is an audited, SHA-bound list of canvas contact indices and
expected report counts. It is not automatic canvas classification. Geometry,
pressure calibration, UI settings and initial material state are deliberately
not guessed. Output is private raw data, NOT a rendering replay or latency test.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import statistics

spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('capture-sketch-real-pen.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def build(data, selection):
    digest = hashlib.sha256(data).hexdigest()
    if selection.get('raw_sha256') != digest:
        raise ValueError('Selection is not bound to this raw recording')
    evidence = selection.get('canvas_evidence')
    if not isinstance(evidence, str) or not evidence.strip():
        raise ValueError('Canvas classification needs an evidence reference')
    choices = selection.get('contacts')
    if not isinstance(choices, list) or not choices:
        raise ValueError('Select contacts explicitly; never assume all are canvas strokes')
    report = capture.summarize(data)
    if report['syn_dropped'] or report['timestamp_reversals']:
        raise ValueError('Recording has loss or reversed timestamps')
    chosen, rejected, seen = [], [], set()
    for choice in choices:
        index, expected = choice.get('index'), choice.get('reports')
        if type(index) is not int or index < 0 or index >= len(report['contacts']) or index in seen:
            raise ValueError('Invalid or duplicate contact index')
        seen.add(index)
        c = report['contacts'][index]
        if type(expected) is not int or expected != c['reports']:
            raise ValueError('Contact count differs from audited selection')
        reasons = []
        if c['release_report_us'] is None or c['interrupted']:
            reasons.append('incomplete_contact')
        if c['unknown_axis_reports']:
            reasons.append('unknown_axes')
        if c['unknown_tool_reports']:
            reasons.append('unknown_tool')
        if reasons:
            rejected.append({'index': index, 'reasons': reasons, 'reports': expected})
            continue
        samples = c['samples']
        intervals = [b[0]-a[0] for a,b in zip(samples,samples[1:])]
        if any(n <= 0 for n in intervals):
            raise ValueError('Contact timestamps must increase strictly')
        unchanged_xy = sum(a[1:3] == b[1:3] for a,b in zip(samples,samples[1:]))
        unchanged_all = sum(a[1:] == b[1:] for a,b in zip(samples,samples[1:]))
        chosen.append({'index': index, 'first_report_us': c['first_report_us'],
            'release_report_us': c['release_report_us'], 'reports': len(samples),
            'samples': samples,
            'diagnostics': {'report_hz': c['report_hz'],
                'interval_median_us': statistics.median(intervals) if intervals else None,
                'interval_max_us': max(intervals) if intervals else None,
                'unchanged_xy_pairs': unchanged_xy, 'unchanged_all_pairs': unchanged_all,
                'raw_pressure_min': min(s[3] for s in samples),
                'raw_pressure_max': max(s[3] for s in samples),
                'raw_xy_distance': sum(math.hypot(b[1]-a[1],b[2]-a[2]) for a,b in zip(samples,samples[1:]))}})
    return {'schema': 'sketch-private-raw-corpus-v1', 'raw_sha256': digest,
        'canvas_evidence': evidence, 'selected_contacts': len(choices),
        'accepted_contacts': len(chosen), 'accepted_reports': sum(c['reports'] for c in chosen),
        'excluded_unselected_indices': [i for i in range(len(report['contacts'])) if i not in seen],
        'rejected_contacts': rejected, 'contacts': chosen,
        'status': 'complete_raw_contacts' if chosen else 'no_usable_contacts',
        'render_replay_ready': False, 'optical_latency_measured': False,
        'missing_for_faithful_replay': ['historical viewport transform and input exclusion',
            'audited device axis ranges', 'per-contact tool, size and material options',
            'pressure calibration', 'initial material/image/wear state'],
        'sampling': 'All selected accepted SYN_REPORT samples retained, including stationary samples; no interpolation or deduplication.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--raw', type=Path, required=True)
    p.add_argument('--selection', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    result = build(a.raw.read_bytes(), json.loads(a.selection.read_text()))
    # Exclusive creation prevents overwriting recordings or older evidence.
    with os.fdopen(os.open(a.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        json.dump(result, f, indent=2, allow_nan=False)
        f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'contacts'}))


if __name__ == '__main__':
    main()
