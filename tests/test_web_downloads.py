import pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]

class WebDownloads(unittest.TestCase):
    def test_worker_limits_and_public_network_policy(self):
        if not shutil.which('cc'): self.skipTest('C compiler unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            exe=pathlib.Path(tmp)/'check'
            subprocess.run(['cc','-std=c11','-Wno-deprecated-declarations','-iquote','/usr/include/x86_64-linux-gnu/curl',str(ROOT/'tests/web-download-validation.c'),'-ldl','-o',str(exe)],check=True,capture_output=True)
            subprocess.run([str(exe)],check=True,capture_output=True,timeout=10)

    def test_no_system_service_or_direct_library_writes(self):
        worker=(ROOT/'product/payload/apps/paperweb-download/web-download.c').read_text()
        self.assertNotIn('/remarkable/xochitl',worker)
        for guard in ('CURLOPT_SSL_VERIFYPEER','CURLOPT_SSL_VERIFYHOST','CURLOPT_OPENSOCKETFUNCTION','CURLOPT_PROXY','CURLOPT_MAXFILESIZE_LARGE','CURLOPT_XFERINFOFUNCTION','LIMIT-received','RESERVE+LIMIT','!declared||declared==received'):
            self.assertIn(guard,worker)
        self.assertIn('web-inbox',worker)
        installer=(ROOT/'product/install.sh').read_text()
        self.assertNotIn('systemctl enable --now paperdesk-download.path',installer)
        self.assertIn('"$TARGET/paperweb-download/web-download"',installer)
