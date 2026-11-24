#!/usr/bin/env python3
"""Export private, bracketed preview workloads. No device access or input injection.

This reuses the *preview's* rounded screen geometry, not the exact material
canvas. Sampled unchanged settings cannot rule out unseen intermediate changes.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


corpus = module('corpus', 'sketch-trace-corpus.py')
metadata = module('metadata', 'sketch-pen-metadata.py')


def workloads(raw, selection, snapshots):
    source = corpus.build(raw, selection)
    if source['rejected_contacts']:
        raise ValueError('Selected contact is incomplete')
    if not snapshots:
        raise ValueError('Metadata required')
    entries = [entry['snapshot'] for entry in snapshots]
    for s in entries:
        metadata.validate(s)
    if any(b['start_realtime_us'] <= a['end_realtime_us'] for a, b in zip(entries, entries[1:])):
        raise ValueError('Metadata overlaps or reverses')
    result = []
    for contact in source['contacts']:
        start, end = contact['first_report_us'], contact['release_report_us']
        before = [s for s in entries if s['end_realtime_us'] <= start]
        after = [s for s in entries if s['start_realtime_us'] >= end]
        if not before or not after:
            raise ValueError('Contact lacks both metadata brackets')
        first, last = before[-1], after[0]
        if start-first['end_realtime_us'] > 5000000 or last['start_realtime_us']-end > 5000000:
            raise ValueError('Metadata bracket is too distant')
        covered = [s for s in entries if first['start_realtime_us'] <= s['start_realtime_us'] <= last['start_realtime_us']]
        settings = metadata.validate(first)
        ranges = lambda s: sorted((a['code'], a['minimum'], a['maximum']) for a in s['axes'])
        if not settings['armed'] or any(metadata.validate(s) != settings or ranges(s) != ranges(first) for s in covered):
            raise ValueError('Settings or axes changed within bracket')
        axes = {a['code']: a for a in first['axes']}
        # The installed native preview assumes zero X/Y minima, unlike PaperPen.
        if axes[0]['minimum'] != 0 or axes[1]['minimum'] != 0:
            raise ValueError('Unsupported preview axis origin')
        samples = contact['samples']
        if any(s[6] or not axes[24]['minimum'] < s[3] <= axes[24]['maximum'] or
               not 0 <= s[1] <= axes[0]['maximum'] or not 0 <= s[2] <= axes[1]['maximum'] for s in samples):
            raise ValueError('Preview requires in-range positive pen contact')
        lines = [f"SKETCH_PREVIEW_TRACE_V1 {len(samples)} {contact['index']} {end-start}",
                 first['preview_permit'],
                 f"{axes[0]['maximum']} {axes[1]['maximum']} {axes[24]['minimum']} {axes[24]['maximum']}"]
        lines += [f'{s[1]} {s[2]} {s[3]}' for s in samples]
        result.append({'index': contact['index'], 'reports': len(samples),
                       'duration_us': end-start, 'tool': settings['tool'],
                       'screen_brush_size': settings['screen_brush_size'],
                       'metadata_bracket_us': [first['start_realtime_us'], last['end_realtime_us']],
                       'unchanged_metadata_snapshots': len(covered),
                       'text': '\n'.join(lines)+'\n'})
    return source['raw_sha256'], result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.capture
    digest, rows = workloads((root/'events.bin').read_bytes(),
        json.loads((root/'corpus-selection-v1.json').read_text()),
        json.loads((root/'metadata-snapshots.json').read_text()))
    args.output.mkdir(mode=0o700)  # Fail closed if existing; never overwrite evidence.
    for row in rows:
        with os.fdopen(os.open(args.output/f"contact-{row['index']}.txt", os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600), 'w') as stream:
            stream.write(row.pop('text'))
    summary = {'raw_sha256': digest, 'contacts': rows,
        'scope': 'Recorded geometry/pressure; sampled bracketed preview settings; white memory-only framebuffer. Not material replay or optical timing.',
        'sample_policy': 'All selected samples retained; no interpolation or deduplication.'}
    with os.fdopen(os.open(args.output/'manifest.json', os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600), 'w') as stream:
        json.dump(summary, stream, indent=2, allow_nan=False)
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
