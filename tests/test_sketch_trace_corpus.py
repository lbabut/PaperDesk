import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('corpus',Path(__file__).parents[1]/'scripts/sketch-trace-corpus.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def e(t,k,c,v):return m.capture.EVENT.pack(1700000000,t,k,c,v)
def contact(known=True):
    b=b''.join(e(0,3,n,v) for n,v in [(0,10),(1,20),(24,100),(26,-30),(27,45)]) if known else b''
    if known:b+=e(0,1,320,1)
    return b+e(0,1,330,1)+e(0,0,0,0)+e(2000,0,0,0)+e(4000,1,330,0)+e(4000,0,0,0)
def selection(b):return {'raw_sha256':hashlib.sha256(b).hexdigest(),'canvas_evidence':'synthetic fixture','contacts':[{'index':0,'reports':2}]}
class CorpusTest(unittest.TestCase):
    def test_all_stationary_samples_retained(self):
        b=contact();r=m.build(b,selection(b));c=r['contacts'][0]
        self.assertEqual(c['samples'],m.capture.summarize(b)['contacts'][0]['samples'])
        self.assertEqual(c['diagnostics']['unchanged_all_pairs'],1)
        self.assertEqual(c['diagnostics']['report_hz'],500)
        self.assertFalse(r['render_replay_ready'])
    def test_unknown_not_guessed(self):
        b=contact(False);r=m.build(b,selection(b))
        self.assertEqual(r['accepted_contacts'],0)
        self.assertEqual(r['rejected_contacts'][0]['reasons'],['unknown_axes','unknown_tool'])
    def test_wrong_recording(self):
        with self.assertRaises(ValueError):m.build(contact(False),selection(contact()))
    def test_wrong_count(self):
        b=contact();s=selection(b);s['contacts'][0]['reports']=3
        with self.assertRaises(ValueError):m.build(b,s)
    def test_duplicate_index(self):
        b=contact();s=selection(b);s['contacts']*=2
        with self.assertRaises(ValueError):m.build(b,s)
    def test_bad_indices(self):
        b=contact()
        for index in [-1,1,True,0.0,'0']:
            s=selection(b);s['contacts'][0]['index']=index
            with self.assertRaises(ValueError):m.build(b,s)
    def test_no_canvas_assumption(self):
        b=contact();s=selection(b);s['contacts']=[]
        with self.assertRaises(ValueError):m.build(b,s)
    def test_evidence_required(self):
        b=contact();s=selection(b);s['canvas_evidence']=''
        with self.assertRaises(ValueError):m.build(b,s)
    def test_drop_refused(self):
        b=contact()+e(5000,0,3,0)
        with self.assertRaises(ValueError):m.build(b,selection(b))
    def test_reversal_refused(self):
        b=contact()+e(0,0,0,0)
        with self.assertRaises(ValueError):m.build(b,selection(b))
    def test_release_missing(self):
        b=contact()[:-32];r=m.build(b,selection(b))
        self.assertEqual(r['accepted_contacts'],0)
        self.assertIn('incomplete_contact',r['rejected_contacts'][0]['reasons'])
    def test_dropped_tool_does_not_leak(self):
        b=contact()+e(5000,0,3,0)
        b+=b''.join(e(6000,3,n,v) for n,v in [(0,10),(1,20),(24,100),(26,-30),(27,45)])
        b+=e(6000,1,330,1)+e(6000,0,0,0)+e(8000,1,330,0)+e(8000,0,0,0)
        r=m.capture.summarize(b)
        self.assertEqual(r['contacts'][1]['unknown_tool_reports'],1)
    def test_cli_private_output_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);b=contact()
            (root/'raw').write_bytes(b);(root/'selection').write_text(json.dumps(selection(b)))
            command=[sys.executable,str(Path(m.__file__)), '--raw',str(root/'raw'),
                '--selection',str(root/'selection'),'--output',str(root/'output')]
            first=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(first.returncode,0,first.stderr)
            output=(root/'output').read_bytes()
            self.assertEqual((root/'output').stat().st_mode & 0o777,0o600)
            second=subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(second.returncode,0)
            self.assertEqual((root/'output').read_bytes(),output)
            self.assertEqual((root/'raw').read_bytes(),b)
    def test_selected_subset_only(self):
        b=contact()+b''.join(e(5000,3,n,v) for n,v in [(0,30),(1,40)])
        b+=e(5000,1,330,1)+e(5000,0,0,0)+e(7000,1,330,0)+e(7000,0,0,0)
        r=m.build(b,selection(b))
        self.assertEqual(r['accepted_contacts'],1)
        self.assertEqual(r['excluded_unselected_indices'],[1])
if __name__=='__main__':unittest.main()
