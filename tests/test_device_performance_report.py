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
                    "no_automatic_save": True, "cases": [dict(id=name, tool=1 if name=="pen-graphite" else 4, passed=True,
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

    def test_tilted_soft_contract_is_not_silently_replaced(self):
        good = self.good()
        self.assertFalse(perf.summarize([good],5,True)["passed"])
        case=good["results"]["shading_probe"]["cases"][1]
        case["tool"]=5
        self.assertFalse(perf.summarize([good],5,True)["passed"])
        case["tilted_charcoal_requested"]=True
        self.assertFalse(perf.summarize([good],5,True)["passed"])
        case["contact"]={"tilt_x":.8,"tilt_y":0}
        self.assertTrue(perf.summarize([good],5,True)["passed"])
        for invalid in (0, float("nan"), True, 2):
            case["contact"]["tilt_x"]=invalid
            self.assertFalse(perf.summarize([good],5,True)["passed"])

    def test_actual_input_rate_is_required(self):
        report=self.good()
        self.assertFalse(perf.summarize([report],expected_input_hz=500)["passed"])
        for c in report["results"]["shading_probe"]["cases"]:
            c.update(requested_input_hz=500,injected_interval_us=2000,injected_samples=1260,achieved_input_hz=480)
        self.assertTrue(perf.summarize([report],expected_input_hz=500)["passed"])
        for invalid in (250,None,float("nan"),True,390,600):
            bad=copy.deepcopy(report)
            bad["results"]["shading_probe"]["cases"][0]["achieved_input_hz"]=invalid
            self.assertFalse(perf.summarize([bad],expected_input_hz=500)["passed"])
        for key,value in (("requested_input_hz",250),("injected_interval_us",4000),("injected_samples",1000)):
            bad=copy.deepcopy(report);bad["results"]["shading_probe"]["cases"][0][key]=value
            self.assertFalse(perf.summarize([bad],expected_input_hz=500)["passed"])


if __name__ == "__main__":
    unittest.main()
