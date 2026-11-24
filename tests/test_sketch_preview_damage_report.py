import copy
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('damage', pathlib.Path(__file__).resolve().parents[1]/'scripts/test-sketch-preview-damage.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DamageReportTests(unittest.TestCase):
    def setUp(self):
        self.a = [dict(shape=shape, tool=tool, interval_ms=rate, samples=1260,
                       submissions=316, image_fnv64='fixture', touched_pixels_per_batch_sum=40,
                       submitted_box_pixels=100, tight_touched_box_pixels=80)
                  for shape in ('serpentine', 'diagonal', 'stationary', 'adversarial_jumps')
                  for tool in (1, 5) for rate in (2, 4)]
        self.b = copy.deepcopy(self.a)
        for row in self.b:
            row['submitted_box_pixels'] = 80

    def test_valid(self):
        self.assertEqual(len(module.compare(self.a, self.b)), 16)

    def test_missing(self):
        with self.assertRaises(AssertionError): module.compare(self.a, self.b[:-1])

    def test_duplicate(self):
        self.b[-1] = self.b[0]
        with self.assertRaises(AssertionError): module.compare(self.a, self.b)

    def test_changed_pixels_or_input_or_coverage(self):
        for key in ('image_fnv64', 'samples', 'submissions', 'touched_pixels_per_batch_sum'):
            with self.subTest(key=key):
                bad = copy.deepcopy(self.b);bad[0][key] = 'changed'
                with self.assertRaises(AssertionError): module.compare(self.a, bad)

    def test_missing_damage(self):
        self.b[0]['submitted_box_pixels'] = 79
        with self.assertRaises(AssertionError): module.compare(self.a, self.b)


if __name__ == '__main__': unittest.main()
