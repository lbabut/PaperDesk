import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('workload',Path(__file__).parents[1]/'scripts/sketch-preview-workload.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def fixture():
    def event(us,kind,code,value):return m.corpus.capture.EVENT.pack(1,us,kind,code,value)
    raw=b''.join(event(100,3,code,value) for code,value in [(0,100),(1,200),(24,200),(26,0),(27,0)])
    raw+=event(100,1,320,1)+event(100,1,330,1)+event(100,0,0,0)+event(200,0,0,0)
    raw+=event(300,1,330,0)+event(300,0,0,0)
    selection={'raw_sha256':hashlib.sha256(raw).hexdigest(),'canvas_evidence':'synthetic only','contacts':[{'index':0,'reports':2}]}
    s={'schema':1,'read_only':True,'start_realtime_us':1000000,'end_realtime_us':1000050,'start_monotonic_us':1,
       'preview_permit':'fine 0 0 1404 1872 40 4 0.1 0.5 1 1',
       'axes':[{'code':code,'value':0,'minimum':low,'maximum':high} for code,low,high in
               [(0,0,20966),(1,0,15725),(24,0,4095),(26,-9000,9000),(27,-9000,9000)]]}
    t=copy.deepcopy(s);t.update(start_realtime_us=1000400,end_realtime_us=1000450)
    return raw,selection,[{'snapshot':s},{'snapshot':t}]


class WorkloadTest(unittest.TestCase):
    def test_retains_stationary_reports(self):
        raw,sel,meta=fixture();digest,rows=m.workloads(raw,sel,meta)
        self.assertEqual(digest,hashlib.sha256(raw).hexdigest())
        self.assertEqual(rows[0]['reports'],2)
        self.assertEqual(rows[0]['text'].splitlines()[-2:],['100 200 200']*2)
    def test_brackets_required(self):
        raw,sel,meta=fixture()
        for subset in [[],meta[:1],meta[1:]]:
            with self.assertRaises(ValueError):m.workloads(raw,sel,subset)
    def test_changed_settings(self):
        raw,sel,meta=fixture();meta[1]['snapshot']['preview_permit']='fine 0 0 1404 1872 41 4 0.1 0.5 1 1'
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_changed_axes(self):
        raw,sel,meta=fixture();meta[1]['snapshot']['axes'][0]['maximum']+=1
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_nonzero_origin(self):
        raw,sel,meta=fixture()
        for item in meta:item['snapshot']['axes'][0]['minimum']=1
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_stale_bracket(self):
        raw,sel,meta=fixture();meta[1]['snapshot'].update(start_realtime_us=7000400,end_realtime_us=7000450)
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_reversed_metadata(self):
        raw,sel,meta=fixture()
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta[::-1])
    def test_off(self):
        raw,sel,meta=fixture()
        for item in meta:item['snapshot']['preview_permit']='off'
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_wrong_raw_hash(self):
        raw,sel,meta=fixture();sel['raw_sha256']='0'*64
        with self.assertRaises(ValueError):m.workloads(raw,sel,meta)
    def test_cli_private_and_exclusive(self):
        raw,sel,meta=fixture()
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'events.bin').write_bytes(raw)
            (root/'corpus-selection-v1.json').write_text(json.dumps(sel))
            (root/'metadata-snapshots.json').write_text(json.dumps(meta))
            command=[sys.executable,m.__file__,'--capture',str(root),'--output',str(root/'out')]
            first=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(first.returncode,0,first.stderr)
            output=root/'out/contact-0.txt';saved=output.read_bytes()
            self.assertEqual(output.stat().st_mode&0o777,0o600)
            self.assertEqual((root/'out').stat().st_mode&0o777,0o700)
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)
            self.assertEqual(output.read_bytes(),saved)
            self.assertEqual((root/'events.bin').read_bytes(),raw)


class NativeWorkloadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.root=Path(cls.temp.name)
        cls.binary=cls.root/'bench'
        source=Path(__file__).with_name('sketch-preview-workload.c')
        subprocess.run(['gcc','-std=c11','-O2',str(source),'-ldl','-lpthread','-lm','-o',str(cls.binary)],check=True)
        _,rows=m.workloads(*fixture());cls.trace=rows[0]['text']
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def run_trace(self,text):
        path=self.root/'trace';path.write_text(text)
        return subprocess.run([str(self.binary),str(path)],capture_output=True,text=True)
    def test_count_and_determinism(self):
        r=self.run_trace(self.trace);self.assertEqual(r.returncode,0,r.stderr)
        rows=[json.loads(line) for line in r.stdout.splitlines()]
        self.assertEqual(len(rows),3)
        self.assertEqual({row['painted'] for row in rows},{2})
        self.assertEqual(len({row['buffer_digest'] for row in rows}),1)
    def test_truncated(self):
        self.assertEqual(self.run_trace('\n'.join(self.trace.splitlines()[:-1])+'\n').returncode,4)
    def test_extra_sample(self):
        self.assertEqual(self.run_trace(self.trace+'100 200 200\n').returncode,4)
    def test_invalid_pressure(self):
        self.assertEqual(self.run_trace(self.trace.replace('100 200 200','100 200 99999')).returncode,4)


if __name__=='__main__':unittest.main()
