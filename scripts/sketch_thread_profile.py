"""Read-only Linux task accounting. Boundary snapshots, not a full profiler."""
import math


def command(pid):
    pid = int(pid)
    if pid <= 0:
        raise ValueError('invalid pid')
    return f'/tmp/papersketch-task-snapshot {pid}'


def parse(raw):
    lines = raw.splitlines()
    start = float(lines.pop(0).split()[0])
    tasks = {}
    while lines[0] != 'END':
        if lines.pop(0) != 'TASK':
            raise ValueError('missing task marker')
        stat = lines.pop(0)
        left, fields = stat.rsplit(') ', 1)
        tid, name = left.split(' (', 1)
        f = fields.split()
        sched = lines.pop(0).split()
        tasks[tid] = dict(name=name, birth=int(f[19]), ticks=int(f[11])+int(f[12]),
                          runtime_ns=int(sched[0]) if len(sched)==3 else None,
                          wait_ns=int(sched[1]) if len(sched)==3 else None)
    lines.pop(0)
    end = float(lines.pop(0).split()[0])
    if not math.isfinite(start+end) or end < start or lines:
        raise ValueError('invalid snapshot bounds')
    return dict(start=start, end=end, tasks=tasks)


def delta(before, after, ticks):
    if ticks <= 0 or after['start'] < before['end']:
        raise ValueError('invalid interval')
    rows, unavailable = [], []
    for tid, b in after['tasks'].items():
        a = before['tasks'].get(tid)
        origin = 'matched_birth'
        if a is None or a['birth'] != b['birth']:
            # Linux starttime is floored to ticks. Only accept a task known
            # to have been born after the entire first snapshot completed.
            if b['birth']/ticks < before['end']:
                unavailable.append(tid)
                continue
            a = dict(ticks=0,runtime_ns=0,wait_ns=0)
            origin = 'born_in_window_cumulative'
        row = dict(tid=tid, name=b['name'], origin=origin, cpu_seconds=(b['ticks']-a['ticks'])/ticks)
        for source, output in [('runtime_ns','scheduled_seconds'),('wait_ns','runnable_wait_seconds')]:
            row[output] = None if a[source] is None or b[source] is None else (b[source]-a[source])/1e9
        if any(v is not None and v < 0 for k,v in row.items() if k.endswith('seconds')):
            raise ValueError('counter reset')
        rows.append(row)
    return dict(wall_lower_seconds=after['start']-before['end'],
                wall_upper_seconds=after['end']-before['start'],
                snapshot_scan_seconds=[before['end']-before['start'],after['end']-after['start']],
                threads=sorted(rows,key=lambda x:x['cpu_seconds'],reverse=True),
                new_or_reused_tids=unavailable,
                vanished_tids=sorted(set(before['tasks'])-set(after['tasks'])),
                limitation='Boundary scan and SSH overhead included; waits overlap across threads. Missing tasks are not zero CPU. Names do not prove worker roles.')
