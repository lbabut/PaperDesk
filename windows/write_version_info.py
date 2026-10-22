"""Generate PyInstaller PE metadata from the verified product version."""
from pathlib import Path
import re

def main():
    root = Path(__file__).resolve().parents[1]
    version = (root / 'product/VERSION').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Invalid release version')
    numbers = tuple(int(p) for p in version.split('.'))
    numbers += (0,) * (4 - len(numbers))
    if any(n > 65535 for n in numbers):
        raise ValueError('PE version component exceeds 65535')
    strings = dict(CompanyName='Łukasz Babut', FileDescription='PaperDesk Installer',
        FileVersion=version, InternalName='PaperDesk-Installer',
        OriginalFilename='PaperDesk-Installer.exe', ProductName='PaperDesk', ProductVersion=version)
    output = root / 'build/windows-version.txt'
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = ',\n'.join('StringStruct(' + repr(k) + ', ' + repr(v) + ')' for k, v in strings.items())
    output.write_text('VSVersionInfo(ffi=FixedFileInfo(filevers=' + repr(numbers) + ', prodvers=' + repr(numbers) +
        ', mask=0x3f, flags=0, OS=0x40004, fileType=0x1, subtype=0, date=(0, 0)), kids=['
        'StringFileInfo([StringTable("040904B0", [' + fields + '])]), '
        'VarFileInfo([VarStruct("Translation", [1033, 1200])])])\n', encoding='utf-8')
    print(output)

if __name__ == '__main__':
    main()
