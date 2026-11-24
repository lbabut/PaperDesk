import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT=Path(__file__).parents[1]
def module(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('metadata',ROOT/'scripts/sketch-pen-metadata.py')
c=module('capture_metadata',ROOT/'scripts/capture-sketch-real-pen.py')
class MetadataTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.binary=Path(cls.temp.name)/'probe'
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(ROOT/'tests/test-sketch-pen-metadata.c'),'-o',str(cls.binary)],check=True)
        cls.snapshot=json.loads(subprocess.check_output([str(cls.binary)]))
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def test_read_only_probe_snapshot(self):
        p=m.validate(self.snapshot);self.assertEqual(p['tool'],5)
        self.assertFalse(p['exact_viewport']);self.assertIsNone(p['canvas_brush_size'])
        self.assertEqual(p['screen_brush_size'],62.4)
    def test_probe_rejects_device_or_axis_without_partial_json(self):
        for args in [['bad'],['bad','axis']]:
            p=subprocess.run([str(self.binary),*args],capture_output=True)
            self.assertEqual(p.returncode,2);self.assertEqual(p.stdout,b'')
    def test_native_orientation_and_tilt(self):
        self.assertEqual(m.screen_sample(self.snapshot,[1,20967,0,4095,9000,-4500,False]),[0,0,1,-.5,-1,False])
        self.assertEqual(m.screen_sample(self.snapshot,[1,0,15725,0,-9000,9000,True]),[1404,1872,0,1,1,True])
    def test_nonzero_axis_minima(self):
        s=copy.deepcopy(self.snapshot);s['axes'][0].update(minimum=10,maximum=110)
        s['axes'][1].update(minimum=20,maximum=220);s['axes'][2].update(minimum=5,maximum=105)
        self.assertEqual(m.screen_sample(s,[1,60,120,55,0,0,False]),[702,936,.5,0,0,False])
    def test_pressure_and_tilt_clamp(self):
        r=m.screen_sample(self.snapshot,[1,0,0,9999,99999,-99999,False]);self.assertEqual(r[2:5],[1,-1,-1])
    def test_no_unknown_sample_seed(self):
        with self.assertRaises(ValueError):m.screen_sample(self.snapshot,[1,None,0,0,0,0,False])
    def test_off_not_guessed(self):self.assertFalse(m.preview('off')['armed'])
    def test_bad_permits(self):
        for raw in ['on 0 0','fine 0 0 1404 1872 nan 5 .15 .5 .95 1','fine 0 0 1404 1872 10 7 .15 .5 .95 1','fine 0 0 1404 1872 10 5 .5 .4 .95 1']:
            with self.assertRaises(ValueError):m.preview(raw)
    def test_bad_axis_profile(self):
        s=copy.deepcopy(self.snapshot);s['axes'][0]['maximum']=0
        with self.assertRaises(ValueError):m.validate(s)
    def test_clock_reversal(self):
        s=copy.deepcopy(self.snapshot);s['end_realtime_us']=0
        with self.assertRaises(ValueError):m.validate(s)
    def test_optional_helper_is_pinned_and_safe(self):
        self.assertFalse(c.metadata_options(None,None))
        self.assertTrue(c.metadata_options('/tmp/sketch-test/probe','a'*64))
        for path,digest in [('/tmp/x;id','a'*64),('/tmp/../bin/x','a'*64),('/home/x','a'*64),('/tmp/x',None),(None,'a'*64)]:
            with self.assertRaises(ValueError):c.metadata_options(path,digest)
    def run_capture(self, output, mismatch=False, fail_during=False):
        status={'ready':True,'armed':True,'pid':10,'time_ms':1700000000000}
        helper_calls=0
        def remote(command,**kwargs):
            nonlocal helper_calls
            command=command[-1]
            if command.startswith('sha256sum'):return ((('b' if mismatch else 'a')*64)+'  /tmp/probe\n').encode()
            if command.startswith('set -eu'):return b'N: Name="Wacom I2C Digitizer"\nH: Handlers=event1\n'
            if command=='date +%s':return b'1700000000\n'
            if command=='cat /tmp/papersketch-ink-status':return json.dumps(status).encode()
            if command=='/tmp/probe':
                helper_calls+=1
                if fail_during and helper_calls>1:raise RuntimeError('fixture probe failure')
                return json.dumps(self.snapshot).encode()
            self.fail('unexpected remote command: '+command)
        process=Mock();process.poll.side_effect=[None,143,143];process.wait.return_value=143
        argv=['capture','--host','fixture','--key','/tmp/key','--known-hosts','/tmp/known',
            '--host-key-alias','fixture','--seconds','5','--output',str(output),
            '--metadata-probe','/tmp/probe','--metadata-sha256','a'*64]
        with patch('sys.argv',argv),patch.object(c.subprocess,'check_output',side_effect=remote),patch.object(c.subprocess,'Popen',return_value=process) as popen,patch.object(c.time,'time',return_value=1700000000),patch.object(c.time,'monotonic',return_value=0),patch.object(c.time,'sleep'),patch('builtins.print'):
            if mismatch or fail_during:
                with self.assertRaises(RuntimeError):c.main()
            else:c.main()
            if mismatch:popen.assert_not_called()
        return process
    def test_capture_retains_timed_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'capture';self.run_capture(p)
            snapshots=json.loads((p/'metadata-snapshots.json').read_text())
            self.assertEqual(len(snapshots),2)
            self.assertFalse(snapshots[0]['preview']['exact_viewport'])
            self.assertEqual(json.loads((p/'report.json').read_text())['status'],'no_complete_contact')
    def test_hash_mismatch_never_starts_capture(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'capture';self.run_capture(p,mismatch=True);self.assertFalse(p.exists())
    def test_metadata_error_retains_partial_evidence_not_success(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'capture';self.run_capture(p,fail_during=True)
            self.assertTrue((p/'capture.json').exists())
            self.assertTrue((p/'metadata-snapshots.json').exists())
            self.assertFalse((p/'report.json').exists())
if __name__=='__main__':unittest.main()
