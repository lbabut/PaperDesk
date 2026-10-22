#!/usr/bin/env python3
"""Build a real three-part compatibility release for existing Care clients."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    current = (ROOT / 'product/VERSION').read_text().strip()
    if current != '3.0.0.1':
        raise SystemExit('This one-time bridge is only for the 3.0.0.1 transition.')
    bridge = '3.0.0'
    rcc = os.environ.get('PAPERDESK_RCC') or shutil.which('rcc')
    if not rcc:
        rcc = '/home/lukasz/Documents/Codex/2026-09-25/m-2/work/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc'
    key = Path(os.environ.get('PAPERDESK_SIGNING_KEY', str(Path.home() / '.config/paperdesk/release-signing-key.pem')))
    if not key.is_file():
        raise SystemExit('The official signing key is required; nothing published.')
    with tempfile.TemporaryDirectory(prefix='paperdesk-care-bridge-') as tmp:
        product = Path(tmp) / ('paperdesk-' + bridge)
        shutil.copytree(ROOT / 'product', product, ignore=shutil.ignore_patterns('paperdesk.local.conf'))
        (product / 'VERSION').write_text(bridge + '\n')
        metadata = json.loads((product / 'release.json').read_text())
        metadata['version'] = bridge
        (product / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
        care = product / 'payload/apps/papercare'
        qml = care / 'ui/main.qml'
        qml.write_text(qml.read_text().replace('currentVersion: "' + current + '"', 'currentVersion: "' + bridge + '"'))
        subprocess.run([rcc, '--binary', 'application.qrc', '-o', 'resources.rcc'], cwd=care, check=True)
        notes = ['Compatibility update: enables four-part release numbers in Care and switches to the current signed feed.',
                 'After this update, reopen Care and install PaperDesk 3.0.0.1.',
                 'Includes the integrated Books, Dots, SSH sessions, RDP orientation and shared usability improvements.']
        (product / 'RELEASE_NOTES.txt').write_text('\n'.join(notes) + '\n')
        paths = sorted(p for p in product.rglob('*') if p.is_file() and p != product / 'SHA256SUMS')
        (product / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ./' + p.relative_to(product).as_posix() + '\n' for p in paths))
        archive = ROOT / 'dist' / ('paperdesk-' + bridge + '.zip')
        if archive.exists():
            raise SystemExit('Bridge archive already exists; refuse to overwrite an immutable release.')
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
            for p in sorted(product.rglob('*')):
                if p.is_file():
                    output.write(p, product.name + '/' + p.relative_to(product).as_posix())
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_name(archive.name + '.sha256').write_text(digest + '  ' + archive.name + '\n')
        manifest = ROOT / 'website/update/latest.json'
        manifest.write_text(json.dumps(dict(product='PaperDesk', channel='stable', version=bridge,
            publishedAt=metadata['releaseDate'], archiveUrl='/download/' + archive.name,
            archiveSha256=digest, archiveSize=archive.stat().st_size, releaseNotes=notes), indent=2) + '\n')
        signature = manifest.with_name(manifest.name + '.sig')
        subprocess.run(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(key), '-in', str(manifest), '-out', str(signature)], check=True)
        subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(ROOT / 'product/payload/system/paperdesk-release-public.pem'), '-in', str(manifest), '-sigfile', str(signature)], check=True)
        print('Built and verified the 3.0.0 legacy Care bridge. Current release files unchanged.')

if __name__ == '__main__':
    main()
