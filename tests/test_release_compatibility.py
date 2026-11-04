"""Release invariants, including the update path for pre-four-part Care."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]

class ReleaseCompatibilityTests(unittest.TestCase):
    def test_current_and_legacy_feeds_have_matching_signed_archives(self):
        current = (ROOT / 'product/VERSION').read_text().strip()
        for feed, version in [('stable', current), ('latest', current)]:
            with self.subTest(feed=feed):
                path = ROOT / ('website/update/' + feed + '.json')
                manifest = json.loads(path.read_text())
                self.assertEqual(manifest['version'], version)
                subprocess.run(['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin',
                    '-inkey', str(ROOT / 'product/payload/system/paperdesk-release-public.pem'),
                    '-sigfile', str(path) + '.sig', '-in', str(path)], check=True,
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                archive = ROOT / 'dist' / Path(manifest['archiveUrl']).name
                self.assertEqual(archive.stat().st_size, manifest['archiveSize'])
                self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), manifest['archiveSha256'])
                with zipfile.ZipFile(archive) as bundle:
                    prefix = 'paperdesk-' + version + '/'
                    self.assertEqual(bundle.read(prefix + 'VERSION').decode().strip(), version)
                    care = bundle.read(prefix + 'payload/apps/papercare/ui/main.qml').decode()
                    agent = bundle.read(prefix + 'payload/system/paperdesk-update-agent').decode()
                    self.assertIn('currentVersion: "' + version + '"', care)
                    self.assertIn('/update/stable.json', care)
                    self.assertIn('/update/stable.json', agent)
                    for row in bundle.read(prefix + 'SHA256SUMS').decode().splitlines():
                        digest, name = row.split('  ', 1)
                        self.assertEqual(hashlib.sha256(bundle.read(prefix + name.removeprefix('./'))).hexdigest(), digest)
        self.assertRegex(json.loads((ROOT / 'website/update/latest.json').read_text())['version'], r'^[0-9]+\.[0-9]+\.[0-9]+$')

    def test_home_links_match_current_version_and_guide_sections(self):
        page = (ROOT / 'website/index.html').read_text()
        version = (ROOT / 'product/VERSION').read_text().strip()
        for name in re.findall(r'href="/download/([^"]+)"', page):
            self.assertTrue((ROOT / 'dist' / name).is_file(), name)
            if name != 'SHA256SUMS': self.assertIn(version, name)
        guide = (ROOT / 'website/guide-en.html').read_text()
        for fragment in re.findall(r'href="/guide-en.html#([^"]+)"', page):
            self.assertIn('id="' + fragment + '"', guide)
        stages = set(re.findall(r'data-app-stage="([^"]+)"', page))
        self.assertEqual(stages, {'sketch','ssh','rdp','rss','books','dots','web','care'})
        for app in stages:
            self.assertIn('/guide-en.html#' + ('updates' if app == 'care' else app), page)

    def test_deploy_does_not_replace_proxy_configuration_or_download_state(self):
        deploy = (ROOT / 'scripts/deploy-prod.sh').read_text()
        self.assertNotIn('install -o root', deploy)
        self.assertNotIn('reload-or-restart caddy', deploy)
        self.assertIn('src.backup(dst)', deploy)
        self.assertIn('Counter unexpectedly decreased', deploy)
        self.assertIn('Production changed during staging', deploy)

if __name__ == '__main__': unittest.main()
