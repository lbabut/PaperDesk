import hashlib
from pathlib import Path
import re
import tarfile
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'product/VERSION').read_text().strip()

class SourceDistributionTests(unittest.TestCase):
    def test_no_graphical_installer_links_on_public_pages(self):
        for page in (ROOT / 'website').glob('*.html'):
            text = page.read_text()
            self.assertNotRegex(text, r'href=["\x27][^"\x27]*(?:windows-installer|linux-installer|\.exe)')
        home = (ROOT / 'website/index.html').read_text()
        self.assertIn('paperdesk-sources-' + VERSION + '.tar.gz', home)
        self.assertLess(home.index('Join the PaperDesk discussion'), home.index('<main'))

    def test_project_archive_contains_sources_payload_and_checksums_not_secrets(self):
        archive = ROOT / 'dist' / ('paperdesk-sources-' + VERSION + '.tar.gz')
        prefix = 'paperdesk-sources-' + VERSION + '/'
        with tarfile.open(archive) as bundle:
            names = bundle.getnames()
            for name in ['product/install.sh', 'product/payload/apps/paperbooks/ui/main.qml',
                         'windows/installer.py', 'website/server.py', 'tests/test_source_distribution.py']:
                self.assertIn(prefix + name, names)
            for name in names:
                self.assertFalse(name.endswith(('.exe', '.pyc', 'paperdesk.local.conf')))
                self.assertNotIn('/work/', name)
                self.assertNotIn('release-signing-key', name)
            product_sums = bundle.extractfile(prefix + 'product/SHA256SUMS').read()
            with zipfile.ZipFile(ROOT / 'dist' / ('paperdesk-' + VERSION + '.zip')) as update:
                self.assertEqual(product_sums, update.read('paperdesk-' + VERSION + '/SHA256SUMS'))
            for line in product_sums.decode().splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(hashlib.sha256(bundle.extractfile(prefix + 'product/' + name.removeprefix('./')).read()).hexdigest(), digest)
            for line in bundle.extractfile(prefix + 'SOURCE-SHA256SUMS').read().decode().splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(hashlib.sha256(bundle.extractfile(prefix + name.removeprefix('./')).read()).hexdigest(), digest)

    def test_terminal_guides_are_explicit_and_consistent(self):
        for name in ['guide.html', 'guide-en.html']:
            text = (ROOT / 'website' / name).read_text()
            for instruction in ['scp paperdesk-tablet-', 'Get-FileHash', 'sha256sum -c SHA256SUMS',
                                'test ! -e /home/root/paperdesk-install-', '/home/root/xovi/start']:
                self.assertIn(instruction, text)
            self.assertNotIn('StrictHostKeyChecking=no', text)
            self.assertNotIn('3.0.0.1', text)

    def test_documented_payload_transfer_roundtrip(self):
        # Exercise the documented tar/scp-file layout without installing apps.
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            archive = folder / ('paperdesk-tablet-' + VERSION + '.tar.gz')
            subprocess.run(['tar', '--exclude=paperdesk.local.conf', '-czf', str(archive),
                            '-C', str(ROOT / 'product'), '.'], check=True)
            target = folder / 'tablet-stage'
            target.mkdir()
            subprocess.run(['tar', '-xzf', str(archive), '-C', str(target)], check=True)
            subprocess.run(['sha256sum', '--quiet', '-c', 'SHA256SUMS'], cwd=target, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual((target / 'VERSION').read_text().strip(), VERSION)
            self.assertFalse((target / 'paperdesk.local.conf').exists())
