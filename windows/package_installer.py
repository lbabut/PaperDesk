"""Package the built EXE and a clean, rebuildable installer source tree."""
import hashlib
from pathlib import Path
import zipfile
from package_core import verified_files

def main():
    root = Path(__file__).resolve().parents[1]
    files, version = verified_files(root / 'product')
    exe = root / 'dist/windows' / (version + '-prepare') / 'PaperDesk-Installer.exe'
    if not exe.is_file():
        raise SystemExit('The matching installer executable has not been built.')
    output = root / 'dist' / ('paperdesk-windows-installer-' + version + '.zip')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.write(exe, exe.name)
        archive.write(root / 'INSTALL-WINDOWS.md', 'INSTALL-WINDOWS.md')
        for name in files + ['SHA256SUMS']:
            archive.write(root / 'product' / name, 'source/product/' + name.removeprefix('./'))
        for path in sorted((root / 'windows').rglob('*.py')):
            if '__pycache__' not in path.parts:
                archive.write(path, 'source/' + path.relative_to(root).as_posix())
        for name in ['windows/requirements.txt', 'scripts/build-windows-installer.ps1', 'INSTALL-WINDOWS.md', 'tests/test_manual_wizard.py']:
            archive.write(root / name, 'source/' + name)
    output.with_name(output.name + '.sha256').write_text(hashlib.sha256(output.read_bytes()).hexdigest() + '  ' + output.name + '\n')
    print('Built', output)

if __name__ == '__main__':
    main()
