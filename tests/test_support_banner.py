"""The optional support CTA must be visible before the hero, without embeds."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SupportBannerTests(unittest.TestCase):
    def test_support_is_below_reddit_and_above_main(self):
        page = (ROOT / 'website/index.html').read_text()
        start = page.index('<aside class="support-banner shell"')
        end = page.index('</aside>', start)
        banner = page[start:end]
        self.assertLess(page.index('Join the PaperDesk discussion on Reddit'), start)
        self.assertLess(end, page.index('<main id="main">'))
        self.assertIn('Support the project', banner)
        self.assertIn('Optional support', banner)
        self.assertIn('Free and open source', banner)
        self.assertIn('aria-label="Support PaperDesk"', banner)
        self.assertNotIn('<script', banner)
        self.assertNotIn('<iframe', banner)

        class Links(HTMLParser):
            def handle_starttag(self, tag, attrs):
                if tag == 'a':
                    self.links.append(dict(attrs))
        parser = Links()
        parser.links = []
        parser.feed(banner)
        self.assertEqual(len(parser.links), 1)
        self.assertEqual(parser.links[0]['href'], 'https://ko-fi.com/lbabut?ref=onboarding_email_founderwelcome')
        self.assertEqual(parser.links[0]['target'], '_blank')
        self.assertIn('noopener', parser.links[0]['rel'])
        self.assertIn('noreferrer', parser.links[0]['rel'])


if __name__ == '__main__':
    unittest.main()
