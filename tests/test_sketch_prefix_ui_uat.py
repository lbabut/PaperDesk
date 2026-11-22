import hashlib,json,pathlib,runpy,subprocess,sys,tempfile,unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts/install-sketch-prefix-ui-uat.py'
class UiUat(unittest.TestCase):
 def exercise(self,consent=True,mismatch=False,fail=False):
  calls=[];installed=set();error=None;failed=False
  expected={'ui/main.qml':'dda3e31c9113bb914afec256926c75858240dd3e5611c36448714f2bb8362819','resources.rcc':'3207f8fbd23057eeaa0ebc47b684b2888d4b0b66f21d5efd0295040035e5d0a1','engine.js':'34c3c14f08ae7a0f52716e77f54aec3ea7533d2668cd76aebacfac931dd3814f','papersketch-raster.so':'3989ebc926a32ea77efed3ab9f7501775f41f37fb475e05287d2d3e665e2a8dc','papersketch-ink.so':'5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7'}
  def fake(args,**kwargs):
   nonlocal failed
   self.assertIn('StrictHostKeyChecking=yes',args);cmd=args[-1];calls.append(cmd);data=''
   if cmd.startswith('sha256sum '):
    name=cmd.split()[-1];rel='ui/main.qml' if name.endswith('ui/main.qml') else name.rsplit('/',1)[-1]
    h=hashlib.sha256((ROOT/'product/payload/apps/papersketch'/rel).read_bytes()).hexdigest() if rel in installed else expected[rel]
    data=('0'*64 if mismatch else h)+' file\n'
   elif cmd.startswith('mktemp '):data='/home/root/.local/state/sketch-prefix-ui.TEST\n'
   elif cmd.startswith('systemctl is-enabled'):data='static\n'
   elif '.uat-new; mv ' in cmd:
    if fail and not failed:failed=True;raise subprocess.CalledProcessError(1,args)
    installed.add('ui/main.qml' if cmd.endswith('ui/main.qml') else 'resources.rcc')
   return subprocess.CompletedProcess(args,0,stdout=data.encode(),stderr=b'')
  with tempfile.TemporaryDirectory() as d:
   out=pathlib.Path(d)/'result.json';argv=[str(SCRIPT),'--key','test','--known-hosts','test','--output',str(out)]+(['--safe-state-confirmed'] if consent else [])
   with patch.object(sys,'argv',argv),patch('subprocess.run',side_effect=fake),patch('time.sleep'):
    try:runpy.run_path(str(SCRIPT),run_name='__main__')
    except (RuntimeError,SystemExit,subprocess.CalledProcessError) as e:error=e
   return error,calls,json.loads(out.read_text()) if out.exists() else None
 def test_consent_before_ssh(self):
  error,calls,r=self.exercise(consent=False);self.assertIsInstance(error,SystemExit);self.assertEqual(calls,[])
 def test_mismatch_before_stop(self):
  error,calls,r=self.exercise(mismatch=True);self.assertIsInstance(error,RuntimeError);self.assertFalse(any('stop xochitl' in c for c in calls))
 def test_success_hashes_backup_no_library(self):
  error,calls,r=self.exercise();self.assertIsNone(error);self.assertEqual(r['status'],'installed_for_limited_uat');self.assertTrue(any('previous-ui-main.qml' in c for c in calls));self.assertTrue(any('unmask --runtime' in c for c in calls));self.assertFalse(any('Documents' in c or 'xochitl.conf' in c for c in calls))
 def test_install_failure_rolls_back(self):
  error,calls,r=self.exercise(fail=True);self.assertIsInstance(error,subprocess.CalledProcessError);self.assertEqual(r['status'],'rolled_back');self.assertTrue(any(c.startswith('sh ') and c.endswith('/rollback.sh') for c in calls));self.assertTrue(any('unmask --runtime' in c for c in calls))
if __name__=='__main__':unittest.main()
