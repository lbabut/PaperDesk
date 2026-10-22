from contextlib import closing
import concurrent.futures
import gzip
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request


class DownloadStatsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        spec = importlib.util.spec_from_file_location('stats_site', Path(__file__).resolve().parents[1] / 'website/server.py')
        self.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.site)
        self.site.STATE_DIR = root
        self.site.STATS_DB = root / 'stats.sqlite3'
        self.site.REPO = root
        self.site.initialize_stats()
        (root / 'dist').mkdir()
        self.files = ['paperdesk-2.0.2.zip', 'paperdesk-3.0.0.1.zip', 'paperdesk-windows-installer-3.0.0.1.zip', 'paperdesk-linux-installer-3.0.0.1.tar.gz', 'paperdesk-sources-3.0.1.tar.gz']
        for name in self.files + ['SHA256SUMS', self.files[0] + '.sha256']:
            (root / 'dist' / name).write_bytes(b'test archive')
        geo = root / 'countries.gz'
        with gzip.open(geo, 'wt') as output:
            output.write('8.8.8.0,8.8.8.255,US\n2001:4860::,2001:4860:ffff:ffff:ffff:ffff:ffff:ffff,US\n')
        self.site.COUNTRIES = self.site.CountryLookup(geo)
        self.http = self.site.ThreadingHTTPServer(('127.0.0.1', 0), self.site.Handler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()
        self.temp.cleanup()

    def get(self, path, method='GET', headers=None):
        request = urllib.request.Request(f'http://127.0.0.1:{self.http.server_port}{path}', method=method, headers=headers or {})
        with urllib.request.urlopen(request) as response:
            return response.read(), response.headers

    def test_combined_total_and_exclusions(self):
        for name in self.files:
            _, headers = self.get('/download/' + name, headers={'X-PaperDesk-Client-IP': '8.8.8.8'})
            self.assertEqual(headers['Cache-Control'], 'no-store')
        for _ in range(100):
            if self.site.download_count() == len(self.files):
                break
            time.sleep(.01)
        self.get('/download/' + self.files[0], method='HEAD')
        self.get('/download/' + self.files[0] + '.sha256')
        self.get('/download/SHA256SUMS')
        with self.assertRaises(urllib.error.HTTPError):
            self.get('/download/paperdesk-9.9.9.zip')
        data, headers = self.get('/api/download-countries')
        self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertEqual(json.loads(data), {'downloaded': len(self.files), 'countries': {'US': len(self.files), 'ZZ': 0}})
        with closing(sqlite3.connect(self.site.STATS_DB)) as db, db:
            columns = [row[1] for row in db.execute('PRAGMA table_info(download_countries)')]
        self.assertEqual(columns, ['day', 'artifact', 'country', 'downloads'])

    def test_migration_and_concurrent_counts(self):
        with closing(sqlite3.connect(self.site.STATS_DB)) as db, db:
            db.execute('DELETE FROM download_countries')
            db.execute("UPDATE counters SET value=47 WHERE name='downloads'")
        self.site.initialize_stats()
        self.site.initialize_stats()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.site.record_download(self.files[0], 'PL'), range(40)))
        self.assertEqual(self.site.country_counts(), {'downloaded': 87, 'countries': {'ZZ': 47, 'PL': 40}})
        self.assertEqual(self.site.download_count(), 87)

    def test_country_lookup_and_proxy_trust(self):
        for ip in ['8.8.8.8', '::ffff:8.8.8.8', '2001:4860::8888']:
            self.assertEqual(self.site.COUNTRIES.country(ip), 'US')
        for ip in ['127.0.0.1', '10.0.0.1', 'garbage', '1.1.1.1']:
            self.assertEqual(self.site.COUNTRIES.country(ip), 'ZZ')
        handler = object.__new__(self.site.Handler)
        handler.client_address = ('1.1.1.1', 1234)
        handler.headers = {'X-PaperDesk-Client-IP': '8.8.8.8'}
        self.assertEqual(handler.download_country(), 'ZZ')
        handler.client_address = ('127.0.0.1', 1234)
        self.assertEqual(handler.download_country(), 'US')

    def test_fast_country_loader_retains_range_validation(self):
        invalid = self.site.STATE_DIR / 'invalid-country.csv.gz'
        for rows in ('8.8.8.9,8.8.8.1,US\n',
                     '8.8.8.0,2001:4860::,US\n',
                     '8.8.8.0,8.8.8.255,US\n8.8.8.128,8.8.9.0,CA\n',
                     'invalid,8.8.8.8,US\n'):
            with self.subTest(rows=rows):
                with gzip.open(invalid, 'wt') as output: output.write(rows)
                with self.assertRaises(ValueError): self.site.CountryLookup(invalid)


if __name__ == '__main__':
    unittest.main()
