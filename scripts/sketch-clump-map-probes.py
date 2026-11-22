#!/usr/bin/env python3
"""Generate exact-state CPU-only clump-map probes; never install a module."""
import hashlib, json, os, pathlib, subprocess
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'work/clump-map'
out.mkdir(parents=True,exist_ok=True)
base=(root/'product/payload/apps/papersketch/native/sketch-material.h').read_text()
bench=(root/'tests/bench-sketch-rowspan.cpp').read_text()
(out/'baseline.h').write_text(base)
chain=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/arm-toolchain/root')
env=dict(os.environ,LD_LIBRARY_PATH=str(chain/'usr/lib/x86_64-linux-gnu'))
manifest=[]
for name,ctype in [('byte-map','uint8_t'),('double-map','double')]:
    source=base.replace('std::vector<uint8_t> tooth;',f'std::vector<uint8_t> tooth;\n    std::vector<{ctype}> clumpMap;\n    int clumpStride=0;')
    marker='        rebuildTooth();\n        (void)grainResponses();'
    init='''        clumpStride=(w+2)/3;
        clumpMap.resize(size_t(clumpStride)*((h+6)/7));
        for(int y=0;y<(h+6)/7;y++)for(int x=0;x<clumpStride;x++)
            clumpMap[size_t(y)*clumpStride+x]=VALUE;
'''.replace('VALUE','hash(x,y)&255' if ctype=='uint8_t' else '.70 + .60 * ((hash(x,y)&255) * (1.0 / 255.0))')
    assert marker in source
    source=source.replace(marker,init+marker)
    old='.70 + .60 * ((hash(x / 3, y / 7) & 255) * (1.0 / 255.0))'
    new='clumpMap[size_t(y/7)*clumpStride+x/3]'
    if ctype=='uint8_t':new='.70 + .60 * ('+new+' * (1.0 / 255.0))'
    assert old in source
    source=source.replace(old,new)
    header=out/(name+'.h');header.write_text(source)
    text=bench.replace('"fixtures/sketch-material-before-rowspan.h"','"baseline.h"').replace('"../product/payload/apps/papersketch/native/sketch-material.h"','"'+header.name+'"')
    test=out/(name+'.cpp');test.write_text(text)
    for arch,compiler,extra in [('host','g++',[]),('arm',str(chain/'usr/bin/arm-linux-gnueabihf-g++-12'),['--sysroot='+str(chain),'-static'])]:
        result=subprocess.run([compiler,*extra,'-std=c++17','-O2','-pthread',str(test),'-o',str(out/(name+'-'+arch))],env=env,capture_output=True,text=True)
        (out/(name+'-'+arch+'.build.log')).write_text(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(name+' '+arch+' build failed')
    manifest.append(dict(name=name,sha256=hashlib.sha256(source.encode()).hexdigest(),bytes_at_1200x1600=400*229*(1 if ctype=='uint8_t' else 8)))
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
