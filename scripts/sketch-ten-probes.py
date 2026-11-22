#!/usr/bin/env python3
"""Generate ten independent exact-state CPU probes, never install a module."""
import json, pathlib, subprocess, os, hashlib
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'work/ten-probes'
out.mkdir(parents=True,exist_ok=True)
base=(root/'product/payload/apps/papersketch/native/sketch-material.h').read_text()
bench=(root/'tests/bench-sketch-rowspan.cpp').read_text()
(out/'baseline.h').write_text(base)
def change(old,new):
    assert old in base, old
    return base.replace(old,new)
variants={
 '01-prefetch-mass':change('uint32_t packed = mass[at];','__builtin_prefetch(mass + std::min(at + 16, width * height - 1), 1, 1);\n                uint32_t packed = mass[at];'),
 '02-prefetch-response':change('uint32_t packed = mass[at];','if (responses && x + 8 <= rowX1) __builtin_prefetch(responses + unsigned(burnish[at+8]) * 256 + tooth[at+8], 0, 1);\n                uint32_t packed = mass[at];'),
 '03-row-offset':change('const double dy = y + .5 - cy, dySquared = dy * dy * quadraticY;','const int rowOffset = y * width;\n            const double dy = y + .5 - cy, dySquared = dy * dy * quadraticY;').replace('int at = y * width + x;', 'int at = rowOffset + x;'),
 '04-tight-row-guard':change('inverseTwoX-.5))-1);','inverseTwoX-.5)));').replace('inverseTwoX-.5))+1);','inverseTwoX-.5)));'),
 '05-parallel-area400':change('shape.a * shape.b >= 200 && y1-y0 >= 16','shape.a * shape.b >= 400 && y1-y0 >= 16'),
 '06-parallel-area100':change('shape.a * shape.b >= 200 && y1-y0 >= 16','shape.a * shape.b >= 100 && y1-y0 >= 16'),
 '07-contact-cache64':change('const bool cacheFresh = tool < 6 && shape.a * shape.b >= 144;','const bool cacheFresh = tool < 6 && shape.a * shape.b >= 64;'),
 '08-contact-cache256':change('const bool cacheFresh = tool < 6 && shape.a * shape.b >= 144;','const bool cacheFresh = tool < 6 && shape.a * shape.b >= 256;'),
 '09-circular-rowspan':change('shape.a * shape.b >= 64 && (shape.a > shape.b * 1.25 || shape.b > shape.a * 1.25);','shape.a * shape.b >= 64;'),
 '10-conditional-image-store':change('image[at] = 0xff000000u | uint32_t(gray) * 0x010101u;', 'const uint32_t nextGray = 0xff000000u | uint32_t(gray) * 0x010101u;\n                if (image[at] != nextGray) image[at] = nextGray;'),
}
toolchain=pathlib.Path('/home/lukasz/Documents/Codex/2026-09-25/m-2/work/arm-toolchain/root')
env=dict(os.environ,LD_LIBRARY_PATH=str(toolchain/'usr/lib/x86_64-linux-gnu'))
manifest=[]
for name,source in variants.items():
    header=out/(name+'.h'); header.write_text(source)
    test=out/(name+'.cpp')
    text=bench.replace('"fixtures/sketch-material-before-rowspan.h"','"baseline.h"').replace('"../product/payload/apps/papersketch/native/sketch-material.h"','"'+header.name+'"')
    test.write_text(text)
    result=subprocess.run([str(toolchain/'usr/bin/arm-linux-gnueabihf-g++-12'),'--sysroot='+str(toolchain),'-std=c++17','-O2','-pthread','-static',str(test),'-o',str(out/name)],env=env,capture_output=True,text=True)
    (out/(name+'.build.log')).write_text(result.stdout+result.stderr)
    manifest.append(dict(name=name,compiled=result.returncode==0,header_sha256=hashlib.sha256(source.encode()).hexdigest()))
    print(name,'compiled' if result.returncode==0 else 'BUILD FAILED',flush=True)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
assert all(v['compiled'] for v in manifest)
