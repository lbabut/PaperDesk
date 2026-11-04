"""Release metadata and user-facing installation instructions stay in sync."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'product/VERSION').read_text().strip()


class ReleaseDocumentTests(unittest.TestCase):
    def test_product_metadata_care_and_readme_use_the_same_release(self):
        release = json.loads((ROOT / 'product/release.json').read_text())
        self.assertEqual(release['version'], VERSION)
        self.assertTrue((ROOT / 'product/CHANGELOG.md').read_text().startswith(
            '# ' + VERSION + ' — ' + release['releaseDate'] + '\n'))
        self.assertTrue((ROOT / 'product/README.md').read_text().startswith(
            '# PaperDesk ' + VERSION + '\n'))
        self.assertIn('**' + VERSION + '**', (ROOT / 'README.md').read_text())
        care = (ROOT / 'product/payload/apps/papercare/ui/main.qml').read_text()
        self.assertIn('currentVersion: "' + VERSION + '"', care)

    def test_current_installation_guides_name_the_current_package_and_stage(self):
        for name in ['product/MANUAL-INSTALL.md', 'website/guide-en.html',
                     'website/guide.html']:
            text = (ROOT / name).read_text()
            with self.subTest(document=name):
                versions = re.findall(
                    r'paperdesk-(?:sources|tablet|install)-([0-9]+\.[0-9]+\.[0-9]+)', text)
                self.assertTrue(versions)
                self.assertEqual(set(versions), {VERSION})
                self.assertIn('paperdesk-sources-' + VERSION + '.tar.gz', text)
                self.assertIn('paperdesk-install-' + VERSION, text)
                self.assertIn('https://github.com/lbabut/PaperDesk', text)

    def test_home_shows_current_release_and_preserves_direct_github_sources(self):
        text = (ROOT / 'website/index.html').read_text()
        self.assertIn('Get PaperDesk ' + VERSION, text)
        self.assertRegex(text, re.compile(r'PaperDesk\s+' + re.escape(VERSION), re.I))
        self.assertIn('/download/paperdesk-sources-' + VERSION + '.tar.gz', text)
        self.assertIn('href="https://github.com/lbabut/PaperDesk"', text)


if __name__ == '__main__':
    unittest.main()
