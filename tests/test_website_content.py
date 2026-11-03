"""Content integrity across the landing page and its local destinations."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import unittest

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
                self.assertIn(parts.fragment, ids, url)

    def test_makers_community_and_each_app_are_represented(self):
        text = (WEB / 'index.html').read_text()
        page = Page(text)
        self.assertEqual(sum(t == 'h1' for t, _ in page.tags), 1)
        self.assertEqual(sum(t == 'article' and a.get('class') == 'feature'
                             for t, a in page.tags), 8)
        self.assertEqual(sum(t == 'figure' and a.get('class') == 'tour-card'
                             for t, a in page.tags), 8)
        ids = [a['id'] for _, a in page.tags if 'id' in a]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn('https://www.linkedin.com/in/lukasz-babut', text)
        self.assertIn('class="reddit-icon"', text)
        self.assertIn('AI collaborator', text)
        self.assertIn('PNG/PDF', text)
        self.assertNotIn('id="terminal-preview"', text)
        self.assertNotIn('onboarding_email_founderwelcome', text)
        for tag, attrs in page.tags:
            if tag == 'img':
                self.assertIn('alt', attrs)

if __name__ == '__main__':
    unittest.main()
