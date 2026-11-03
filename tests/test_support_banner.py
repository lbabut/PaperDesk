"""Support stays easy to find without embeds or obscuring installation context."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class Links(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.links = []
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.links.append(dict(attrs))

class SupportBannerTests(unittest.TestCase):
    def test_support_and_counter_are_above_main_without_embeds(self):
        page = (ROOT / 'website/index.html').read_text()
        start = page.index('<header class="site-header">')
        end = page.index('<main id="main">')
        banner = page[start:end]
        self.assertIn('data-download-count', banner)
        self.assertIn('Buy us a coffee', banner)
        self.assertNotIn('<script', banner)
        self.assertNotIn('<iframe', page)
        links = Links(banner).links
        links = [link for link in links if link.get("href") == "https://ko-fi.com/lbabut"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]['href'], 'https://ko-fi.com/lbabut')
        self.assertEqual(links[0]['target'], '_blank')
        self.assertIn('noopener', links[0]['rel'])
        self.assertIn('noreferrer', links[0]['rel'])
        self.assertEqual(page.count('data-download-count'), 1)
        self.assertIn('Requires a working XOVI', page)
        self.assertIn('Optional support', page)

if __name__ == '__main__':
    unittest.main()
