#!/usr/bin/env python3
"""Ten independent pipeline probes; generates/builds candidates, never installs."""
import pathlib,shutil,subprocess,json,hashlib,concurrent.futures
root=pathlib.Path(__file__).resolve().parents[1]; out=root/'work/pipeline-ten';out.mkdir(parents=True,exist_ok=True)
native='product/payload/apps/papersketch/native/papersketch-raster.cpp'
base=(root/native).read_text()
def change(old,new):
 assert old in base,old
 return base.replace(old,new)
variants={}
for n,size in [(1,12),(2,20),(3,28)]:variants[f'{n:02}-batch{size}']=change('penSamples.takeInput(24)',f'penSamples.takeInput({size})')
for n,ms in [(4,8),(5,12),(6,20)]:variants[f'{n:02}-publish{ms}']=change('displayPublicationTimer.setInterval(16)',f'displayPublicationTimer.setInterval({ms})')
variants['07-pending-bounds']=change('}else displayPending+=damage;','}else displayPending=QRegion(displayPending.boundingRect().united(damage.boundingRect()));')
variants['08-reserved-event-row']=change('result.append(QVariant(QVariantList{event.phase,p.x,p.y,p.p,p.tiltX,p.tiltY,p.eraser,p.contact}));','QVariantList row;row.reserve(8);row.append(event.phase);row.append(p.x);row.append(p.y);row.append(p.p);row.append(p.tiltX);row.append(p.tiltY);row.append(p.eraser);row.append(p.contact);result.append(QVariant(row));')
old='if(!ensureMaterial())return false;\n        double radius='
variants['09-ready-fast-path']=change(old,'if((!materialReady || image.isNull() || finger.isNull()) && !ensureMaterial())return false;\n        double radius=')
variants['10-conservative-radius']=change('double radius=std::max(physics.footprintRadius(tool,size,ap),physics.footprintRadius(tool,size,p))+3;','double radius=43; // Conservative maximum40px footprint plus original3px margin.')
installer=root/'scripts/install-sketch-charcoal-uat.py'
def build(item):
 name,source=item; dest=out/name;dest.mkdir(exist_ok=True)
 for folder in ['scripts','tests','product/payload/apps/papersketch']:
  shutil.copytree(root/folder,dest/folder,dirs_exist_ok=True)
 shutil.copy2(installer,dest/'scripts/install-sketch-charcoal-uat.py')
 (dest/native).write_text(source)
 p=subprocess.run(['python3',str(dest/'scripts/build-sketch-raster.py')],capture_output=True,text=True)
 (dest/'build.log').write_text(p.stdout+p.stderr)
 module=dest/'product/payload/apps/papersketch/native/papersketch-raster.so'
 result=dict(name=name,compiled=p.returncode==0,source_sha256=hashlib.sha256(source.encode()).hexdigest(),module_sha256=hashlib.sha256(module.read_bytes()).hexdigest() if p.returncode==0 else None)
 print(json.dumps(result),flush=True);return result
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(build,variants.items()))
(out/'manifest.json').write_text(json.dumps(results,indent=2)+'\n')
assert len(results)==10 and all(v['compiled'] for v in results)
