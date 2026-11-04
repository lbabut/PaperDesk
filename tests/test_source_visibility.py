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

    def test_source_code_is_in_persistent_footer_navigation(self):
        footer = re.search(r'<footer\b.*?</footer>', self.home, re.S).group()
        links = Links(footer).links
        self.assertTrue(any(attrs.get('href') == SOURCE_URL and 'GitHub' in label for attrs, label in links))
        self.assertNotIn(' hidden', footer)
        self.assertGreater(self.home.index('<footer'), self.home.index('</main>'))

    def test_source_code_is_directly_visible_in_about_panel(self):
        about = re.search(r'<section id="view-about".*?</section>', self.home, re.S).group()
        self.assert_source_link(about)
        source = next(attrs for attrs, label in Links(about).links
                      if attrs.get('href') == SOURCE_URL and 'Source code' in label)
        self.assertEqual(source['href'], SOURCE_URL)
        self.assertLess(about.index('Source code on GitHub'), about.index('<details'))

    def test_source_code_links_on_every_public_page_use_github(self):
        for path in (ROOT / 'website').glob('*.html'):
            for attrs, label in Links(path.read_text()).links:
                if 'source code' in label.lower() or 'źródła' in label.lower():
                    self.assertEqual(attrs.get('href'), SOURCE_URL, str(path))

    def test_download_label_and_client_role_are_explicit(self):
        install = re.search(r'<section id="view-install".*?</section>', self.home, re.S).group()
        matches = [(attrs,label) for attrs,label in Links(install).links
                   if attrs.get('href') == '/download/paperdesk-sources-' + VERSION + '.tar.gz']
        self.assertTrue(any('Download PaperDesk' in label for attrs,label in matches))
        self.assertIn('Source code on GitHub', self.home)
        self.assertIn('source code and prepared tablet files', install)
        terminal = re.search(r'<article[^>]*data-app-stage="ssh"[^>]*>(.*?)</article>', self.home, re.S).group(1)
        self.assertIn('SSH', terminal)
        self.assertIn('native keyboard', terminal)
        self.assertIn('/guide-en.html#ssh', terminal)


if __name__ == '__main__':
    unittest.main()
