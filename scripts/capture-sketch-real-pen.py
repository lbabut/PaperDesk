#!/usr/bin/env python3
"""Bounded read-only physical-pen capture. No grab, injection, restart or install.

Private raw input remains in the specified local output directory. Timestamps
are kernel event timestamps, NOT optical screen timings or receipt latencies.
Only the audited 32-bit little-endian reMarkable profile is supported.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import subprocess
import time

EVENT = struct.Struct('<iiHHi')


def metadata_options(path, digest):
    if path is None and digest is None:
        return False
    if not isinstance(path,str) or not re.fullmatch(r'/tmp/[a-zA-Z0-9_./-]+',path) or '..' in path.split('/'):
        raise ValueError('Metadata probe must be an explicit safe /tmp path')
    if not isinstance(digest,str) or not re.fullmatch(r'[0-9a-f]{64}',digest):
        raise ValueError('Metadata probe requires pinned SHA256')
    return True


def pen_device(devices):
    found = []
    for block in devices.split('\n\n'):
        if 'N: Name="Wacom I2C Digitizer"' not in block:
            continue
        handlers = re.search(r'^H: Handlers=(.*)$', block, re.M)
        if handlers:
            found.extend(re.findall(r'\bevent[0-9]+\b', handlers[1]))
    if len(found) != 1:
        raise ValueError('Expected exactly one audited Wacom input device')
    return '/dev/input/' + found[0]


def summarize(data):
    if len(data) % EVENT.size:
        raise ValueError('Truncated 32-bit input_event stream')
    result = {'events': len(data)//EVENT.size, 'syn_dropped': 0,
              'timestamp_reversals': 0, 'contacts': [], 'trailing_contact': False}
    axes = {n: None for n in (0, 1, 24, 26, 27)}
    touch, rubber, contact, previous = None, None, None, None
    for sec, usec, kind, code, value in EVENT.iter_unpack(data):
        if sec < 0 or not 0 <= usec < 1000000:
            raise ValueError('Invalid event timestamp / unsupported event layout')
        stamp = sec*1000000 + usec
        if previous is not None and stamp < previous:
            result['timestamp_reversals'] += 1
        previous = stamp
        if kind == 0 and code == 3:
            result['syn_dropped'] += 1
            if contact is not None:
                contact['interrupted'] = True
                result['contacts'].append(contact)
            contact, touch = None, None
            axes = dict.fromkeys(axes)
            rubber = None
        elif kind == 3 and code in axes:
            axes[code] = value
        elif kind == 1 and code == 321:
            rubber = bool(value)
        elif kind == 1 and code == 320 and value:
            rubber = False
        elif kind == 1 and code == 330:
            touch = bool(value)
        elif kind == 0 and code == 0:
            if touch:
                if contact is None:
                    contact = {'first_report_us': stamp, 'last_report_us': stamp,
                               'release_report_us': None, 'interrupted': False,
                               'samples': []}
                contact['last_report_us'] = stamp
                contact['samples'].append([stamp, *(axes[n] for n in (0,1,24,26,27)), rubber])
            elif touch is False and contact is not None:
                contact['release_report_us'] = stamp
                result['contacts'].append(contact)
                contact = None
    if contact is not None:
        result['trailing_contact'] = True
        result['contacts'].append(contact)
    for c in result['contacts']:
        c['reports'] = len(c['samples'])
        duration = (c['last_report_us']-c['first_report_us'])/1e6
        c['report_hz'] = (c['reports']-1)/duration if duration > 0 else None
        c['unknown_axis_reports'] = sum(any(v is None for v in row[1:6]) for row in c['samples'])
        c['unknown_tool_reports'] = sum(row[6] is None for row in c['samples'])
    result['usable_complete_contacts'] = sum(c['release_report_us'] is not None
                                            and not c['interrupted'] for c in result['contacts'])
    result['complete_axis_contacts'] = sum(c['release_report_us'] is not None
                                          and not c['interrupted'] and not c['unknown_axis_reports']
                                          and not c['unknown_tool_reports']
                                          for c in result['contacts'])
    result['replay_ready'] = bool(result['contacts']) and not (
        result['syn_dropped'] or result['timestamp_reversals'] or result['trailing_contact']
        or result['complete_axis_contacts'] != len(result['contacts']))
    result['raw_sha256'] = hashlib.sha256(data).hexdigest()
    result['optical_latency_measured'] = False
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True)
    parser.add_argument('--key', required=True)
    parser.add_argument('--known-hosts', required=True)
    parser.add_argument('--host-key-alias', required=True)
    parser.add_argument('--seconds', type=int, default=30, choices=range(5,61))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--metadata-probe', help='Previously audited read-only helper in tablet /tmp')
    parser.add_argument('--metadata-sha256', help='Required SHA256 of that helper')
    args = parser.parse_args()
    try:
        with_metadata=metadata_options(args.metadata_probe,args.metadata_sha256)
    except ValueError as error:
        parser.error(str(error))
    if not re.fullmatch(r'[a-zA-Z0-9.:-]+', args.host):
        parser.error('Invalid host')
    ssh = ['ssh','-F','/dev/null','-i',args.key,'-o','IdentitiesOnly=yes',
           '-o','StrictHostKeyChecking=yes','-o','BatchMode=yes','-o','ConnectTimeout=6',
           '-o','UserKnownHostsFile='+args.known_hosts,
           '-o','HostKeyAlias='+args.host_key_alias,'root@'+args.host]

    def remote(command):
        return subprocess.check_output(ssh+[command], timeout=15).decode()

    metadata_parser=None
    if with_metadata:
        actual=remote('sha256sum '+args.metadata_probe).split()[0]
        if actual!=args.metadata_sha256:
            raise RuntimeError('Metadata helper SHA256 mismatch; not executed')
        spec=importlib.util.spec_from_file_location('pen_metadata',Path(__file__).with_name('sketch-pen-metadata.py'))
        metadata_parser=importlib.util.module_from_spec(spec);spec.loader.exec_module(metadata_parser)

    def metadata_snapshot():
        snap=json.loads(remote(args.metadata_probe))
        parsed=metadata_parser.validate(snap)
        return {'received_at_unix':time.time(),'snapshot':snap,'preview':parsed}

    profile = remote('set -eu; test "$(uname -m)" = armv7l; '
                     'grep -q \'^IMG_VERSION="3.29.0.153"$\' /etc/os-release; '
                     'systemctl is-active --quiet xochitl; cat /proc/bus/input/devices')
    device = pen_device(profile)
    before = json.loads(remote('cat /tmp/papersketch-ink-status'))
    remote_now = int(remote('date +%s'))
    if not before.get('ready') or not before.get('armed') or abs(before['time_ms']/1000-remote_now)>3:
        raise RuntimeError('Open Sketch canvas with fresh armed preview before capture')
    metadata_samples=[metadata_snapshot()] if with_metadata else []
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    (args.output/'input-profile.txt').write_text(profile)
    (args.output/'preview-before.json').write_text(json.dumps(before, indent=2)+'\n')
    meta = {'schema': 1, 'device': device, 'started_at_unix': time.time(),
            'requested_seconds': args.seconds, 'read_only_device': True,
            'physical_input_not_synthetic': True, 'optical_latency_measured': False}
    meta['metadata_probe_sha256']=args.metadata_sha256
    meta['metadata_sampling']='about1second; not atomic with input and may miss transient settings' if with_metadata else None
    started = time.monotonic()
    with (args.output/'events.bin').open('wb') as out, (args.output/'capture.stderr').open('w') as err:
        # Keep a shell parent: direct BusyBox timeout exec dies by SIGTERM,
        # which SSH reports as 255 rather than the child's conventional 143.
        command = (f'timeout {args.seconds} cat {device}; capture_rc=$?; '
                   'printf "CAPTURE_EXIT=%s\\n" "$capture_rc" >&2; exit "$capture_rc"')
        process = subprocess.Popen(ssh+[command], stdout=out, stderr=err)
        snapshots = []
        try:
            while process.poll() is None:
                status = json.loads(remote('cat /tmp/papersketch-ink-status'))
                snapshots.append({'received_at_unix': time.time(), 'status': status})
                if with_metadata:
                    metadata_samples.append(metadata_snapshot())
                estimated_remote_now = remote_now + time.monotonic()-started
                if (not status.get('ready') or not status.get('armed')
                        or status.get('pid') != before.get('pid')
                        or abs(status.get('time_ms',0)/1000-estimated_remote_now)>3):
                    meta['stopped_reason'] = 'Sketch preview disarmed, stale or process changed; capture stopped'
                    process.terminate()
                    break
                if time.monotonic()-started > args.seconds+15:
                    raise TimeoutError('Remote capture exceeded bounded duration')
                time.sleep(1)
            code = process.wait(timeout=10)
            meta['capture_returncode'] = code
            # timeout may use 124 (coreutils) or 143 (BusyBox SIGTERM).
            if code not in (0,124,143) and 'stopped_reason' not in meta:
                raise RuntimeError(f'Capture failed: returncode {code}')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill();process.wait()
            meta['finished_at_unix'] = time.time()
            (args.output/'capture.json').write_text(json.dumps(meta,indent=2)+'\n')
            (args.output/'preview-snapshots.json').write_text(json.dumps(snapshots,indent=2)+'\n')
            if with_metadata:
                (args.output/'metadata-snapshots.json').write_text(json.dumps(metadata_samples,indent=2)+'\n')
    report = summarize((args.output/'events.bin').read_bytes())
    report['status'] = 'captured' if report['usable_complete_contacts'] else 'no_complete_contact'
    if report['syn_dropped'] or report['timestamp_reversals'] or meta.get('stopped_reason'):
        report['status'] = 'incomplete_or_invalid'
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='contacts'}))


if __name__ == '__main__':
    main()
