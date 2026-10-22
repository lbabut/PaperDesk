import io
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[1]

class BooksSources(unittest.TestCase):
    def test_catalogues(self):
        subprocess.run(['node',str(ROOT/'tests/books-catalogues.cjs')],check=True,capture_output=True,timeout=20)

    def test_downloader_validation(self):
        if not shutil.which('cc'): self.skipTest('C compiler unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            tmp=pathlib.Path(tmp);exe=tmp/'validate'
            subprocess.run(['cc','-std=c11','-Wno-deprecated-declarations','-iquote','/usr/include/x86_64-linux-gnu/curl',str(ROOT/'tests/books-download-validation.c'),'-ldl','-o',str(exe)],check=True,capture_output=True,timeout=30)
            def epub(extra=None):
                buf=io.BytesIO()
                with zipfile.ZipFile(buf,'w') as z:
                    z.writestr('mimetype','application/epub+zip')
                    z.writestr('META-INF/container.xml','<container/>')
                    z.writestr('OEBPS/book.opf','<package/>')
                    if extra: z.writestr(extra,'bad')
                return buf.getvalue()
            cases=[('pdf',b'%PDF-1.7\n'+b'x'*300+b'\n%%EOF\n',1),
                   ('pdf',b'<html>'+b'x'*300+b'%%EOF',0),('pdf',b'%PDF-1.7\n'+b'x'*300,0),
                   ('epub',epub(),1),('epub',epub()[:-20],0),('epub',epub('../escape'),0),
                   ('epub',epub('/absolute'),0),('epub',b'PK'+b'x'*500,0)]
            for i,(fmt,data,valid) in enumerate(cases):
                with self.subTest(case=i):
                    fixture=tmp/str(i);fixture.write_bytes(data)
                    subprocess.run([str(exe),str(fixture),fmt,str(valid)],check=True,capture_output=True,timeout=10)

    def test_worker_is_hidden_and_never_writes_the_library(self):
        launcher=(ROOT/'product/payload/system/paperdesk-appload.qml').read_text()
        worker=(ROOT/'product/payload/apps/paperbooks-download/book-download.c').read_text()
        self.assertIn('application.id !== "external::paperbooks-download"',launcher)
        self.assertNotIn('/remarkable/xochitl',worker)
        self.assertIn('O_NOFOLLOW',worker)
        self.assertIn('CURLOPT_PROTOCOLS',worker)
        self.assertNotIn('SSL_VERIFYPEER,0',worker)

    def test_settings_initialization_waits_for_settings_and_does_not_cache_catalogues_in_them(self):
        qml=(ROOT/'product/payload/apps/paperbooks/ui/main.qml').read_text()
        self.assertIn('Component.onCompleted: Qt.callLater(function()',qml)
        self.assertIn('root.initialized && root.deleteId',qml)
        self.assertNotIn('catalogueCacheJson',qml)
        self.assertNotIn('legacydevice/window/main',qml)
