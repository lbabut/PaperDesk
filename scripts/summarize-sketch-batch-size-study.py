"""Sanitize guarded device reports; never reinterpret a failing suite as UAT."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--run', action='append', nargs=3, metavar=('LABEL', 'CAP', 'FOLDER'), required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
record = {
    'schema': 'sketch-batch-size-study-v1',
    'decision': 'research_only_not_UAT',
    'gates_ms_strictly_below': {'gui_gap': 200, 'queue_p95': 100, 'release_tail': 150},
    'limits': [
        'Small ABBA screening, not a statistical or physical stylus-to-panel latency claim.',
        'Exact ordered material computation and publication stride unchanged; available-work cap only.',
        'Safety checks cover benchmark settings/artwork and checked caches, not a full library backup.',
        'Latency and center-tile visibility failures remain failures in the unchanged device suite.',
        'Phase durations overlap and include preemption/barrier waits; they are not additive CPU time.',
        'All temporary modules restored after each run. No production release.',
    ],
    'runs': [],
}
for label, cap, folder in a.run:
    root = Path(folder)
    assert (root / 'restored.txt').is_file(), 'Missing restoration evidence'
    path = root / 'probe/run-1.json'
    raw = json.loads(path.read_text())
    summary = json.loads((root / 'probe/summary.json').read_text())
    install = json.loads((root / 'install.json').read_text())
    probe = raw['results']['shading_probe']
    entry = {
        'label': label, 'batch_limit': int(cap), 'created_at': summary['created_at'],
        'high_rate_shading': summary['high_rate_shading'],
        'source_report_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'raster_sha256': install['candidate_sha256']['papersketch-raster.so'],
        'suite_passed': summary['passed'], 'suite_failures': summary['failures'],
        'artwork_preserved': raw['artwork_preserved'], 'saved_files_preserved': raw['saved_files_preserved'],
        'no_automatic_save': probe['no_automatic_save'], 'runtime_error_count': len(probe['runtime_errors']),
        'cases': [],
    }
    for case in probe['cases']:
        sanitized = {k: case.get(k) for k in (
            'id', 'input_samples', 'input_stats', 'achieved_input_hz', 'requested_input_hz',
            'max_input_tick_gap_ms', 'release_to_drained_ms', 'tile_visible_before_release',
            'blank_frames_after_visible', 'display_binary', 'optical_has_grays', 'deferred_material')}
        sanitized['queue_p95_upper_ms'] = case['queue_latency']['p95_upper_ms']
        entry['cases'].append(sanitized)
    record['runs'].append(entry)
a.output.write_text(json.dumps(record, indent=2) + '\n')
for run in record['runs']:
    c = next(c for c in run['cases'] if c['id'] == 'pen-charcoal')
    print(run['label'], c['max_input_tick_gap_ms'], c['queue_p95_upper_ms'], c['release_to_drained_ms'], run['suite_passed'])
