import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("perf", Path(__file__).resolve().parents[1]/"scripts/test-sketch-device-performance.py")
perf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(perf)


class ReportTests(unittest.TestCase):
    def good(self):
        return {"native_modules": ["sha raster", "sha ink"], "artwork_preserved": True,
                "saved_files_preserved": True, "results": {"shading_probe": {
                    "no_automatic_save": True, "cases": [dict(id=name, passed=True,
                    tile_visible_before_release=True, max_input_tick_gap_ms=50,
                    queue_latency={"p95_upper_ms": 30}, release_to_drained_ms=80)
                    for name in ("pen-graphite", "pen-charcoal")]}}}

    def test_good_repeats(self):
        self.assertTrue(perf.summarize([self.good(), self.good()])["passed"])

    def test_failures_are_not_averaged_away(self):
        bad = self.good()
        bad["results"]["shading_probe"]["cases"][1]["max_input_tick_gap_ms"] = 250
        self.assertFalse(perf.summarize([self.good(), bad, self.good()])["passed"])

    def test_incomplete_and_nonfinite_fail(self):
        for value in (None, float("nan"), -1, True):
            bad = self.good()
            bad["results"]["shading_probe"]["cases"][0]["release_to_drained_ms"] = value
            self.assertFalse(perf.summarize([bad])["passed"])
        self.assertFalse(perf.summarize([])["passed"])

    def test_changed_binary_and_artwork_fail(self):
        bad = copy.deepcopy(self.good())
        bad["native_modules"] = ["other"]
        self.assertFalse(perf.summarize([self.good(), bad])["passed"])
        bad = self.good()
        bad["artwork_preserved"] = False
        self.assertFalse(perf.summarize([bad])["passed"])


if __name__ == "__main__":
    unittest.main()
