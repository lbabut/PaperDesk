"""Audit snapshot ranges and rounded preview settings; never infer exact viewport."""
import math


def preview(raw):
    if raw is None or raw == 'off':
        return {'armed': False, 'exact_viewport': False}
    fields = raw.split()
    if len(fields) != 11 or fields[0] != 'fine':
        raise ValueError('Unsupported preview permit')
    values = list(map(float, fields[1:]))
    if not all(math.isfinite(n) for n in values):
        raise ValueError('Nonfinite preview settings')
    x,y,w,h,size,tool,a,b,c,strength = values
    if any(n != int(n) for n in (x,y,w,h,tool)) or not (
        x>=0 and y>=0 and w>0 and h>0 and x+w<=1404 and y+h<=1872
        and size>=1 and tool in (0,1,2,3,4,5,8) and .05<=strength<=1
        and .001<=a and c<=1 and b-a>=.04 and c-b>=.04 and c-a>=.15):
        raise ValueError('Invalid preview bounds, tool or calibration')
    return {'armed': True, 'rounded_screen_bounds': [x,y,w,h],
        'screen_brush_size': size, 'tool': int(tool), 'pressure_anchors': [a,b,c],
        'strength': strength, 'exact_viewport': False,
        'canvas_brush_size': None}


def validate(snapshot):
    if snapshot.get('schema') != 1 or snapshot.get('read_only') is not True:
        raise ValueError('Unsupported snapshot')
    for key in ('start_realtime_us','start_monotonic_us','end_realtime_us'):
        if type(snapshot.get(key)) is not int or snapshot[key]<0:
            raise ValueError('Invalid clock')
    if snapshot['end_realtime_us']<snapshot['start_realtime_us']:
        raise ValueError('Reversed snapshot clock')
    axes=snapshot.get('axes',[])
    if len(axes)!=5 or {a.get('code') for a in axes}!={0,1,24,26,27}:
        raise ValueError('Expected five distinct axes')
    for a in axes:
        if any(type(a.get(k)) is not int for k in ('code','minimum','maximum','value')) or a['maximum']<=a['minimum']:
            raise ValueError('Invalid axis range')
    return preview(snapshot.get('preview_permit'))


def screen_sample(snapshot, row):
    """Mirror audited PaperPen mapping, not canvas transform or calibration."""
    validate(snapshot)
    if len(row)!=7 or any(type(n) is not int for n in row[:6]) or type(row[6]) is not bool:
        raise ValueError('Complete integer raw sample required')
    axes={a['code']:a for a in snapshot['axes']}
    _,x,y,p,tx,ty,rubber=row
    ax,ay,ap=axes[0],axes[1],axes[24]
    clamp=lambda v: max(-1.0,min(1.0,v))
    tilt=lambda v,a: clamp(v/max(abs(a['minimum']),abs(a['maximum'])))
    return [(y-ay['minimum'])*1404.0/(ay['maximum']-ay['minimum']),
        (ax['maximum']-x)*1872.0/(ax['maximum']-ax['minimum']),
        max(0.0,min(1.0,(p-ap['minimum'])/(ap['maximum']-ap['minimum']))),
        tilt(ty,axes[27]),-tilt(tx,axes[26]),rubber]
