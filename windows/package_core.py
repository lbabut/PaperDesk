"""Package integrity and archive construction shared by both manual assistants."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import tarfile

def verified_files(product):
    files = []
    for line in (product / 'SHA256SUMS').read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match:
            raise ValueError('Invalid SHA256SUMS manifest.')
        digest, name = match.groups()
        relative = PurePosixPath(name)
        if relative.is_absolute() or '..' in relative.parts or '\\' in name or ':' in name:
            raise ValueError('Unsafe path in the package.')
        path = product.joinpath(*relative.parts)
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(product.resolve()):
            raise ValueError('Missing package file: ' + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('Corrupt package file: ' + name)
        name = relative.as_posix()
        if name in files or name == 'paperdesk.local.conf':
            raise ValueError('Invalid file in the manifest.')
        files.append(name)
    if not {'install.sh', 'VERSION', 'release.json'}.issubset(files):
        raise ValueError('Incomplete package.')
    version = (product / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Invalid version.')
    if json.loads((product / 'release.json').read_text())['version'] != version:
        raise ValueError('Package version mismatch.')
    return files, version


def archive(product):
    files, version = verified_files(product)
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as tar:
        for name in files + ['SHA256SUMS']:
            content = (product / name).read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o755 if name.endswith('.sh') or name.startswith('payload/system/') else 0o644
            tar.addfile(info, io.BytesIO(content))
    return data.getvalue(), version


