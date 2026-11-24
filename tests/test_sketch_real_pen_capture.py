import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('capture', Path(__file__).parents[1]/'scripts/capture-sketch-real-pen.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def event(t, kind, code, value):
    return capture.EVENT.pack(1700000000+t//1000000,t%1000000,kind,code,value)


class CaptureTest(unittest.TestCase):
    def test_discovers_pen_not_touch_number(self):
        self.assertEqual(capture.pen_device('N: Name="pt_mt"\nH: Handlers=event2\n\nN: Name="Wacom I2C Digitizer"\nH: Handlers=event1'),'/dev/input/event1')

    def test_missing_or_ambiguous_pen_rejected(self):
        for text in ['', 'N: Name="Wacom I2C Digitizer"\nH: Handlers=event1 event2']:
            with self.assertRaises(ValueError): capture.pen_device(text)

    def test_empty_not_success(self):
        self.assertEqual(capture.summarize(b'')['usable_complete_contacts'],0)
        self.assertFalse(capture.summarize(b'')['replay_ready'])

    def test_hover_not_contact(self):
        self.assertEqual(capture.summarize(event(0,3,0,10)+event(0,0,0,0))['contacts'],[])

    def test_complete_contact_preserves_all_reports(self):
        data = b''.join(event(0,3,n,v) for n,v in [(0,10),(1,20),(24,100),(26,-30),(27,45)])
        data += event(0,1,320,1)+event(0,1,330,1)+event(0,0,0,0)+event(2000,3,0,11)+event(2000,0,0,0)
        data += event(4000,1,330,0)+event(4000,0,0,0)
        r=capture.summarize(data); c=r['contacts'][0]
        self.assertEqual(r['usable_complete_contacts'],1)
        self.assertEqual(c['reports'],2)
        self.assertEqual(c['report_hz'],500)
        self.assertEqual(c['samples'][1][1:6],[11,20,100,-30,45])
        self.assertFalse(r['optical_latency_measured'])
        self.assertTrue(r['replay_ready'])

    def test_missing_axes_must_not_be_invented_for_replay(self):
        r=capture.summarize(event(0,1,330,1)+event(0,0,0,0)+event(5,1,330,0)+event(5,0,0,0))
        self.assertEqual(r['usable_complete_contacts'],1)
        self.assertEqual(r['complete_axis_contacts'],0)
        self.assertFalse(r['replay_ready'])
        self.assertIsNone(r['contacts'][0]['samples'][0][1])

    def test_unfinished_contact_not_complete(self):
        r=capture.summarize(event(0,1,330,1)+event(0,0,0,0))
        self.assertTrue(r['trailing_contact'])
        self.assertEqual(r['usable_complete_contacts'],0)
        self.assertEqual(r['contacts'][0]['unknown_axis_reports'],1)

    def test_drop_invalidates_contact(self):
        r=capture.summarize(event(0,1,330,1)+event(0,0,0,0)+event(20,0,3,0))
        self.assertEqual(r['syn_dropped'],1)
        self.assertEqual(r['usable_complete_contacts'],0)

    def test_truncated_rejected(self):
        with self.assertRaises(ValueError):capture.summarize(b'x')

    def test_timestamp_reversal_reported(self):
        self.assertEqual(capture.summarize(event(10,0,0,0)+event(0,0,0,0))['timestamp_reversals'],1)

    def test_invalid_timestamp_rejected(self):
        with self.assertRaises(ValueError):capture.summarize(capture.EVENT.pack(1,1000000,0,0,0))


if __name__=='__main__':unittest.main()
