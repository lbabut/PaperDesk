"""Content integrity across the landing page and its local destinations."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import unittest
import struct

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / 'website'

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.tags = []
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

class WebsiteContentTests(unittest.TestCase):
    def test_local_assets_and_fragment_destinations_exist(self):
        home = Page((WEB / 'index.html').read_text())
        for tag, attrs in home.tags:
            key = 'src' if tag in ('img', 'script') else 'href'
            url = attrs.get(key, '')
            if not url or urlsplit(url).scheme:
                continue
            parts = urlsplit(url)
            if parts.path.startswith('/download/'):
                continue
            target = WEB / (parts.path.lstrip('/') or 'index.html')
            self.assertTrue(target.is_file(), url)
            if parts.fragment:
                ids = {a.get('id') for _, a in Page(target.read_text()).tags}
                view_keys = {a['data-tab'] for _, a in home.tags if 'data-tab' in a}
                self.assertTrue(parts.fragment in ids or parts.fragment in view_keys, url)

    def test_all_views_and_complete_uncropped_screens_are_present(self):
        text = (WEB / 'index.html').read_text()
        page = Page(text)
        self.assertEqual(sum(t == 'h1' for t, _ in page.tags), 4)
        self.assertEqual(sum('data-tab' in a for _, a in page.tags), 4)
        self.assertEqual(sum('data-app' in a for _, a in page.tags), 9)
        self.assertEqual(sum('data-app-stage' in a for _, a in page.tags), 9)
        ids = [a['id'] for _, a in page.tags if 'id' in a]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn('https://www.linkedin.com/in/lukasz-babut', text)
        self.assertIn('storage.ko-fi.com/cdn/useruploads/', text)
        self.assertIn('/assets/authors/openai-mark.svg', text)
        self.assertIn('class="reddit-icon"', text)
        self.assertNotIn('Package downloads · explore the map', text)
        self.assertIn('Home ↑', text)
        self.assertIn('Every feature stays free', text)
        for tag, attrs in page.tags:
            if tag == 'img':
                self.assertIn('alt', attrs)
                if attrs.get('src', '').startswith('/assets/screens/'):
                    data = (WEB / attrs['src'].lstrip('/')).read_bytes()
                    self.assertEqual(struct.unpack('>II', data[16:24]), (1404, 1872), attrs['src'])
            if attrs.get('role') == 'tab':
                self.assertIn(attrs['aria-controls'], ids)

if __name__ == '__main__':
    unittest.main()
