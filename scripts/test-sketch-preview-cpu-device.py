#!/usr/bin/env python3
"""Run standalone ARM preview fixtures in a new device /tmp directory.

No installation, display/input access, settings changes, service restart or
artwork access. CPU timing is NOT GUI or physical-panel responsiveness.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import statistics
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binaries', type=pathlib.Path, required=True)
    p.add_argument('--output', type=pathlib.Path, required=True)
    p.add_argument('--host', required=True)
    p.add_argument('--key', required=True)
    p.add_argument('--known-hosts', required=True)
    p.add_argument('--host-key-alias', required=True)
    a = p.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9.:-]+', a.host)
    a.output.mkdir(parents=True, exist_ok=False)
    opts = ['-F', '/dev/null', '-i', a.key, '-o', 'IdentitiesOnly=yes',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6',
            '-o', f'UserKnownHostsFile={a.known_hosts}', '-o', f'HostKeyAlias={a.host_key_alias}']
    ssh = ['ssh', *opts, f'root@{a.host}']

    def run(command, timeout=30):
        return subprocess.check_output([*ssh, command], text=True, timeout=timeout).strip()

    before = run('date -u; systemctl is-active xochitl; cat /tmp/papersketch-ink-status')
    status = json.loads(before.splitlines()[-1])
    if status.get('active') or status.get('armed'):
        raise RuntimeError('Drawing is armed/active: do not compete with the user for CPU')
    remote = run('mktemp -d /tmp/sketch-damage-cpu.XXXXXX')
    assert re.fullmatch(r'/tmp/sketch-damage-cpu\.[a-zA-Z0-9]+', remote)
    hashes = {}
    for name in ('reference', 'candidate'):
        path = a.binaries/name
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        subprocess.run(['scp', *opts, str(path), f'root@{a.host}:{remote}/{name}'], check=True, timeout=30)
        assert run(f'sha256sum {remote}/{name}').split()[0] == hashes[name]
    report = dict(schema=1, started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  before=before, remote_directory=remote, binary_sha256=hashes,
                  scope='Standalone CPU/fidelity fixture, not live GUI/panel; no device app changes',
                  fidelity={}, bench=[])
    try:
        for name in ('reference', 'candidate'):
            report['fidelity'][name] = json.loads(run(f'{remote}/{name} --fidelity'))
        assert report['fidelity']['reference'] == report['fidelity']['candidate']
        for name in ['reference', 'candidate', 'candidate', 'reference']*2:
            current = json.loads(run('cat /tmp/papersketch-ink-status'))
            if current.get('active') or current.get('armed'):
                raise RuntimeError('User returned to painting; stopping CPU replay')
            report['bench'].append(dict(variant=name, **json.loads(run(f'{remote}/{name} --bench'))))
        assert len({r['image_fnv64'] for r in report['bench']}) == 1
        report['candidate_to_reference_median_time_ratio'] = statistics.median(r['seconds'] for r in report['bench'] if r['variant']=='candidate') / statistics.median(r['seconds'] for r in report['bench'] if r['variant']=='reference')
        report['passed'] = True
    finally:
        report['finished_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        report['after'] = run('date -u; systemctl is-active xochitl; cat /tmp/papersketch-ink-status')
        (a.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(dict(report=str(a.output/'report.json'), ratio=report['candidate_to_reference_median_time_ratio'])))


if __name__ == '__main__':
    main()
