from pathlib import Path
import json,unittest
ROOT=Path(__file__).resolve().parents[1]
class CalcRelease(unittest.TestCase):
 def test_installed_and_removable(self):
  self.assertIn('papercalc', [c['id'] for c in json.loads((ROOT/'product/release.json').read_text())['components']])
  for name in ['install.sh','uninstall.sh']:
   text=(ROOT/'product'/name).read_text()
   self.assertIn('papersketch papercalc',text)
   self.assertIn('calc-original-recorded',text)
 def test_site_collection_and_handbooks(self):
  page=(ROOT/'website/index.html').read_text()
  self.assertIn('data-app="calc"',page);self.assertIn('data-app-stage="calc"',page)
  self.assertIn('Nine free apps',page)
  for name in ['calc-desk-20261105.png','calc-graph-20261105.png']:
   self.assertIn(name,page);self.assertTrue((ROOT/'website/assets/screens'/name).is_file())
  for name in ['guide.html','guide-en.html']:
   self.assertIn('id="calc"',(ROOT/'website'/name).read_text())
 def test_hub_and_reference_version(self):
  text=(ROOT/'product/payload/apps/paperdesk/ui/main.qml').read_text()
  self.assertIn('applicationId: "papercalc"',text)
  self.assertIn('Nine focused tools',text)
  self.assertIn('V '+(ROOT/'product/VERSION').read_text().strip(),text)
