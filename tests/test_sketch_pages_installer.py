import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts/install-sketch-pages-uat.py'

class PagesInstallerSafety(unittest.TestCase):
    def test_requires_fresh_safe_state_before_any_ssh(self):
        with patch.object(sys,'argv',[str(SCRIPT),'--output','unused']), patch('subprocess.run') as run, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:runpy.run_path(str(SCRIPT),run_name='__main__')
            self.assertEqual(error.exception.code,2);run.assert_not_called()

    def test_mismatched_baseline_never_stops_interface(self):
        calls=[]
        def run(args,**kwargs):
            self.assertIn('StrictHostKeyChecking=yes',args)
            calls.append(args[-1]);return subprocess.CompletedProcess(args,0,b'changed-hash filename\n',b'')
        with patch.object(sys,'argv',[str(SCRIPT),'--safe-state-confirmed','--output','unused']), patch('subprocess.run',side_effect=run):
            with self.assertRaisesRegex(AssertionError,'Preview baseline changed'):runpy.run_path(str(SCRIPT),run_name='__main__')
        self.assertTrue(calls);self.assertFalse(any('systemctl stop' in command or 'mktemp' in command for command in calls))

    def test_closed_drawing_gate_failure_never_creates_backup(self):
        calls=[]
        def run(args,**kwargs):
            calls.append(args[-1]);raise subprocess.CalledProcessError(1,args,stderr=b'not idle')
        with tempfile.TemporaryDirectory() as folder, patch.object(sys,'argv',[str(SCRIPT),'--safe-state-confirmed','--output',folder+'/result.json']), patch('subprocess.run',side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError):runpy.run_path(str(SCRIPT),run_name='__main__')
            self.assertFalse((Path(folder)/'result.json').exists())
        self.assertEqual(len(calls),1);self.assertIn('/tmp/papersketch-ink',calls[0])

if __name__=='__main__':unittest.main()
