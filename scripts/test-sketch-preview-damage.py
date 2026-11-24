#!/usr/bin/env python3
"""Compile and compare an isolated preview geometry experiment, never install it."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[1]


def compare(reference, candidate):
    if len(reference) != 16 or len(candidate) != 16:
        raise AssertionError('incomplete sweep')
    expected = {(shape, tool, rate) for shape in ('serpentine', 'diagonal', 'stationary', 'adversarial_jumps')
                for tool in (1, 5) for rate in (2, 4)}
    for rows in (reference, candidate):
        assert {(r['shape'], r['tool'], r['interval_ms']) for r in rows} == expected
    results = []
    for a, b in zip(reference, candidate):
        for field in ('shape', 'tool', 'interval_ms', 'samples', 'submissions',
                      'image_fnv64', 'touched_pixels_per_batch_sum'):
            assert a[field] == b[field], (field, a, b)
        assert b['submitted_box_pixels'] == b['tight_touched_box_pixels']
        assert b['submitted_box_pixels'] == a['tight_touched_box_pixels']
        assert b['submitted_box_pixels'] <= a['submitted_box_pixels']
        results.append(dict(reference=a, candidate=b, area_reduction_pct=
                            100*(1-b['submitted_box_pixels']/a['submitted_box_pixels'])))
    return results


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=pathlib.Path, required=True)
    p.add_argument('--cc', default='gcc')
    p.add_argument('--sysroot', type=pathlib.Path)
    p.add_argument('--build-only', action='store_true')
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=False)
    bins = {}
    for name, flag in [('reference', 0), ('candidate', 1)]:
        path = a.output/name
        cmd = [a.cc, '-O2', f'-DPREVIEW_TIGHT_BOUNDS={flag}']
        if a.sysroot:
            cmd += [f'--sysroot={a.sysroot}', '-static']
        cmd += [str(ROOT/'tests/test-sketch-preview-damage.c'), '-ldl', '-lpthread', '-lm', '-o', str(path)]
        subprocess.run(cmd, check=True)
        bins[name] = path
    inputs = ['tests/test-sketch-preview-damage.c',
              'product/payload/apps/papersketch/native/papersketch-ink.c',
              'product/payload/apps/papersketch/native/sketch-preview-shade.h']
    build = dict(compiler=a.cc, source_sha256={name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in inputs},
                 binary_sha256={name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in bins.items()})
    (a.output/'build.json').write_text(json.dumps(build, indent=2)+'\n')
    if a.build_only:
        return
    rows = {}
    for name, path in bins.items():
        raw = subprocess.check_output([str(path)], text=True, timeout=120)
        (a.output/f'{name}.jsonl').write_text(raw)
        rows[name] = [json.loads(line) for line in raw.splitlines()]
    report = dict(schema=1, scope='Offline idealized screen-space geometry, not GUI or panel latency; masks reset only after submission accounting. Unchanged pixel writes are never suppressed.',
                  cases=compare(rows['reference'], rows['candidate']))
    fidelity = {name: json.loads(subprocess.check_output([str(path), '--fidelity'], text=True, timeout=30)) for name, path in bins.items()}
    assert fidelity['reference'] == fidelity['candidate']
    report['fidelity'] = fidelity
    bench = []
    for name in ['reference', 'candidate', 'candidate', 'reference']*2:
        row = json.loads(subprocess.check_output([str(bins[name]), '--bench'], text=True, timeout=30))
        bench.append(dict(variant=name, **row))
    assert len({row['image_fnv64'] for row in bench}) == 1
    report['bench'] = bench
    report['candidate_to_reference_median_time_ratio'] = statistics.median(r['seconds'] for r in bench if r['variant']=='candidate') / statistics.median(r['seconds'] for r in bench if r['variant']=='reference')
    report['binary_sha256'] = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in bins.items()}
    (a.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(dict(cases_passed=len(report['cases']), report=str(a.output/'report.json'), bench_ratio=report['candidate_to_reference_median_time_ratio'])))


if __name__ == '__main__':
    main()
