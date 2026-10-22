"""Copy only verified release files into the executable build input."""
from pathlib import Path
import shutil
from installer import verified_files

root = Path(__file__).resolve().parents[1]
files, version = verified_files(root / 'product')
stage = root / 'build' / 'windows-product' / 'product'
if stage.exists():
    shutil.rmtree(stage)
for name in files + ['SHA256SUMS']:
    target = stage / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / 'product' / name, target)
print('Staged verified PaperDesk', version)
