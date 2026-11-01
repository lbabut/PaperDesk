"""Shared styling and safety context must survive later release edits."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.tags = []
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))


class WebsiteDesignTests(unittest.TestCase):
    def test_all_pages_share_the_same_cache_version(self):
        styles = []
        for name in ['index.html', 'guide.html', 'guide-en.html']:
            page = Page((ROOT / 'website' / name).read_text())
            styles.append(next(a['href'] for t, a in page.tags
                               if t == 'link' and a.get('href', '').startswith('/styles.css?')))
            self.assertEqual(sum(t == 'h1' for t, _ in page.tags), 1)
            ids = [a['id'] for _, a in page.tags if 'id' in a]
            self.assertEqual(len(ids), len(set(ids)))
            self.assertIn('main', ids)
        self.assertEqual(len(set(styles)), 1)

    def test_guides_use_shared_buttons_and_language_metadata(self):
        for name in ['guide.html', 'guide-en.html']:
            page = Page((ROOT / 'website' / name).read_text())
            print_button = next(a for t, a in page.tags if t == 'button')
            self.assertIn('button', print_button['class'].split())
            self.assertIn('print-guide', print_button['class'].split())
            language_link = next(a for t, a in page.tags if t == 'a' and 'hreflang' in a)
            self.assertEqual(language_link['lang'], language_link['hreflang'])

    def test_sharing_uses_public_graphic_and_compatibility_is_visible(self):
        text = (ROOT / 'website/index.html').read_text()
        page = Page(text)
        image = next(a['content'] for t, a in page.tags
                     if t == 'meta' and a.get('property') == 'og:image')
        self.assertEqual(image, 'https://paperdesk.lukaszbabut.info/assets/press/paperdesk-social-v4.png')
        self.assertTrue((ROOT / 'website/assets/press/paperdesk-social-v4.png').is_file())
        hero = text[text.index('id="top"'):text.index('class="edition-strip"')]
        self.assertIn('Requires XOVI + AppLoad', hero)
        self.assertIn('href="#compatibility"', hero)
        self.assertIn('id="compatibility"', text)

    def test_page_and_sharing_titles_match_the_current_major_version(self):
        version = (ROOT / 'product/VERSION').read_text().strip()
        major = version.split('.')[0]
        home = (ROOT / 'website/index.html').read_text()
        self.assertIn('<title>PaperDesk ' + major + ' —', home)
        page = Page(home)
        title = next(a['content'] for t, a in page.tags
                     if t == 'meta' and a.get('property') == 'og:title')
        self.assertTrue(title.startswith('PaperDesk ' + major + ' —'))
        self.assertTrue((ROOT / 'website/assets/press/paperdesk-social.png').is_file())

    def test_shared_control_tokens_and_no_remote_fonts(self):
        styles = (ROOT / 'website/styles.css').read_text()
        self.assertIn('--control-radius:8px', styles)
        self.assertIn('border-radius:var(--control-radius)', styles)
        self.assertIn('font-size:clamp(44px,10vw,60px)', styles)
        self.assertNotIn('fonts.googleapis.com', styles)
        self.assertNotIn('font:700 14px inherit', (ROOT / 'website/guide.css').read_text())


if __name__ == '__main__':
    unittest.main()
