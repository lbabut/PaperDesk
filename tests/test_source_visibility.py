"""Source links must browse GitHub; prepared installation packages stay distinct."""
from html.parser import HTMLParser
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'product/VERSION').read_text().strip()
SOURCE_URL = "https://github.com/lbabut/PaperDesk"


class Links(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.links = []
        self.current = None
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.current = [dict(attrs), '']

    def handle_data(self, data):
        if self.current is not None:
            self.current[1] += data

    def handle_endtag(self, tag):
        if tag == 'a' and self.current is not None:
            self.links.append(self.current)
            self.current = None


class SourceVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.home = (ROOT / 'website/index.html').read_text()

    def assert_source_link(self, fragment):
        matches = [(attrs, label) for attrs, label in Links(fragment).links
                   if attrs.get('href') == SOURCE_URL]
        self.assertTrue(matches, 'Source code must link directly to the GitHub repository')
        self.assertTrue(any('source code' in label.lower() for _, label in matches))

    def test_source_code_is_in_top_navigation(self):
        nav = re.search(r'<nav\b.*?</nav>', self.home, re.S).group()
        self.assert_source_link(nav)

    def test_source_code_is_a_visible_hero_button(self):
        hero = self.home[self.home.index('id="top"'):self.home.index('class="edition-strip"')]
        self.assert_source_link(hero)
        links = Links(hero).links
        source = next(attrs for attrs, _ in links if attrs.get('href') == SOURCE_URL)
        self.assertIn('button', source.get('class', '').split())
        self.assertNotIn('<details', hero)

    def test_source_code_links_on_every_public_page_use_github(self):
        for path in (ROOT / 'website').glob('*.html'):
            for attrs, label in Links(path.read_text()).links:
                if 'source code' in label.lower() or 'źródła' in label.lower():
                    self.assertEqual(attrs.get('href'), SOURCE_URL, str(path))

    def test_download_label_and_client_role_are_explicit(self):
        self.assertIn('Browse source code on GitHub', self.home)
        self.assertIn('Download project package', self.home)
        self.assertIn('QML and C/C++ app code, installers, tests and licences', self.home)
        ssh = re.search(r'<h3>Paper Terminal</h3>(.*?)</article>', self.home, re.S).group(1)
        self.assertIn('graphical SSH client and terminal', ssh)
        self.assertIn('connecting to other computers', ssh)


if __name__ == '__main__':
    unittest.main()
