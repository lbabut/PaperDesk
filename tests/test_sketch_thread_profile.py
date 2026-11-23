import sys
from pathlib import Path
import unittest
import subprocess
import tempfile
import os
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from sketch_thread_profile import parse,delta,command

def snapshot(t=1,cpu=5,birth=10,tid=2,sched='100000000 200000000 3'):
    f=['S']+['0']*49
    f[11]=str(cpu); f[12]='2'; f[19]=str(birth)
    return parse(f'{t} 20\nTASK\n{tid} (a ) funny) '+ ' '.join(f)+f'\n{sched}\nEND\n{t+.01} 20\n')

class Test(unittest.TestCase):
    def test_parse_parentheses_and_fields(self):
        s=snapshot(); self.assertEqual(s['tasks']['2']['name'],'a ) funny')
        self.assertEqual(s['tasks']['2']['ticks'],7)
    def test_deltas(self):
        d=delta(snapshot(),snapshot(3,15,sched='600000000 900000000 9'),100)
        self.assertAlmostEqual(d['threads'][0]['cpu_seconds'],.1)
        self.assertAlmostEqual(d['threads'][0]['runnable_wait_seconds'],.7)
        self.assertAlmostEqual(d['wall_lower_seconds'],1.99)
    def test_birth_reuse(self):
        d=delta(snapshot(),snapshot(3,birth=11),100)
        self.assertEqual(d['new_or_reused_tids'],['2']);self.assertFalse(d['threads'])
    def test_vanished_and_new(self):
        d=delta(snapshot(),snapshot(3,tid=4),100)
        self.assertEqual(d['vanished_tids'],['2']);self.assertEqual(d['new_or_reused_tids'],['4'])
    def test_proven_birth_after_snapshot(self):
        d=delta(snapshot(),snapshot(3,birth=120),100)
        self.assertEqual(d['threads'][0]['origin'],'born_in_window_cumulative')
        self.assertEqual(d['threads'][0]['cpu_seconds'],.07)
    def test_ambiguous_birth_excluded(self):
        d=delta(snapshot(),snapshot(3,birth=100),100)
        self.assertEqual(d['new_or_reused_tids'],['2'])
    def test_missing_schedstat(self):
        d=delta(snapshot(sched='unavailable'),snapshot(3),100)
        self.assertIsNone(d['threads'][0]['runnable_wait_seconds'])
    def test_counter_reset(self):
        with self.assertRaises(ValueError):delta(snapshot(),snapshot(3,1),100)
    def test_bad_interval(self):
        with self.assertRaises(ValueError):delta(snapshot(),snapshot(),100)
        with self.assertRaises(ValueError):delta(snapshot(),snapshot(3),0)
    def test_command_validates_pid(self):
        with self.assertRaises(ValueError):command('2; exit')
        with self.assertRaises(ValueError):command(0)

class ObserverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder=tempfile.TemporaryDirectory(prefix='sketch-task-observer-')
        cls.binary=Path(cls.folder.name)/'observer'
        subprocess.run(['cc','-O2','-Wall','-Wextra','-Werror',str(Path(__file__).parent/'device/sketch-task-snapshot.c'),'-o',str(cls.binary)],check=True)
    @classmethod
    def tearDownClass(cls):cls.folder.cleanup()
    def test_live_host_snapshot(self):
        def sample():return parse(subprocess.check_output([str(self.binary),str(os.getpid())],text=True))
        a=sample();time.sleep(.02);b=sample()
        d=delta(a,b,os.sysconf('SC_CLK_TCK'))
        self.assertIn(str(os.getpid()),[x['tid'] for x in d['threads']])
    def test_rejects_invalid_pid(self):
        for pid in ('0','-1','2;exit','999999999999999999999'):
            self.assertEqual(subprocess.run([str(self.binary),pid]).returncode,2)
    def test_missing_process(self):
        self.assertEqual(subprocess.run([str(self.binary),'2147483647']).returncode,3)

if __name__=='__main__':unittest.main()
