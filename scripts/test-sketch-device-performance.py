"""Explicit, guarded device benchmark. No scheduling or production installation."""
import argparse
import datetime
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LIMITS = {"gui_gap_ms": 200, "queue_p95_ms": 100, "release_tail_ms": 150}


def summarize(reports, expected_charcoal_tool=4, require_tilt=False):
    groups = {}
    failures = []
    fingerprints = set()
    for run, report in enumerate(reports):
        fingerprints.add(tuple(report.get("native_modules", [])))
        probe = report.get("results", {}).get("shading_probe", {})
        cases = probe.get("cases", [])
        if {c.get("id") for c in cases} != {"pen-graphite", "pen-charcoal"} or len(cases) != 2:
            failures.append(f"run {run}: missing/duplicate cases")
        if not all(report.get(k) is True for k in ("artwork_preserved", "saved_files_preserved")):
            failures.append(f"run {run}: preservation not verified")
        if probe.get("no_automatic_save") is not True:
            failures.append(f"run {run}: isolated no-save contract not verified")
        for case in cases:
            if case.get("id")=="pen-charcoal":
                if case.get("tool")!=expected_charcoal_tool:
                    failures.append(f"run {run}: wrong charcoal tool")
                if require_tilt and case.get("tilted_charcoal_requested") is not True:
                    failures.append(f"run {run}: tilted case not verified")
                if require_tilt:
                    tilt = [case.get("contact", {}).get(k) for k in ("tilt_x", "tilt_y")]
                    valid = all(isinstance(v, (int, float)) and not isinstance(v, bool)
                                and math.isfinite(v) and abs(v)<=1 for v in tilt)
                    if not valid or sum(abs(v) for v in tilt)<=.6:
                        failures.append(f"run {run}: actual charcoal tilt not verified")
            values = {"gui_gap_ms": case.get("max_input_tick_gap_ms"),
                      "queue_p95_ms": case.get("queue_latency", {}).get("p95_upper_ms"),
                      "release_tail_ms": case.get("release_to_drained_ms")}
            if case.get("passed") is not True or case.get("tile_visible_before_release") is not True:
                failures.append(f"run {run}/{case.get('id')}: device correctness/performance gate failed")
            for key, value in values.items():
                if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
                    failures.append(f"run {run}/{case.get('id')}: invalid {key}")
                    continue
                groups.setdefault(case["id"], {}).setdefault(key, []).append(value)
                if value >= LIMITS[key]:
                    failures.append(f"run {run}/{case['id']}: {key}={value} >= {LIMITS[key]}")
    if not reports or len(fingerprints) != 1 or not next(iter(fingerprints), ()):
        failures.append("missing or changing native module fingerprint")
    return {"passed": not failures, "failures": failures, "limits_ms": LIMITS,
            "runs": len(reports), "physical_panel_latency_measured": False,
            "scope": "synthetic evdev shading in production Sketch handlers; not hardware finger sensing or physical e-ink latency",
            "metrics": {case: {key: {"median": statistics.median(v), "worst": max(v), "samples": len(v)}
                               for key, v in metrics.items()} for case, metrics in groups.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--safe-state-confirmed", action="store_true")
    parser.add_argument("--host", required=True)
    parser.add_argument("--host-key-alias")
    parser.add_argument("--key", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--expected-installed-rcc")
    parser.add_argument("--tilted-shading", action="store_true")
    parser.add_argument("--soft-charcoal", action="store_true")
    parser.add_argument("--repeats", type=int, default=3, choices=range(1, 6))
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if not args.safe_state_confirmed:
        parser.error("Save/close personal work: --safe-state-confirmed required; restarts UI")
    # Exclusive output prevents accidental replacement of previous evidence.
    args.output_dir.mkdir(parents=True, exist_ok=False)
    reports, codes = [], []
    for index in range(args.repeats):
        path = args.output_dir.resolve() / f"run-{index+1}.json"
        command = [sys.executable, str(ROOT / "scripts/run-sketch-native-guarded.py"),
                   "--safe-state-confirmed", "--shading-probe", "--output", str(path)]
        if args.tilted_shading:
            command.append("--tilted-shading")
        if args.soft_charcoal:
            command.append("--soft-charcoal")
        for key in ("host", "host_key_alias", "key", "known_hosts", "expected_installed_rcc"):
            value = getattr(args, key)
            if value:
                command.extend(["--"+key.replace("_", "-"), value])
        with path.with_suffix(".log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        codes.append(result.returncode)
        current = None
        if path.exists():
            current = json.loads(path.read_text())
            reports.append(current)
        # A measured budget failure may continue, but not an incomplete or unsafe run.
        if current is None or "results" not in current or not all(current.get(k) is True for k in ("artwork_preserved", "saved_files_preserved")):
            break
    summary = summarize(reports,5 if args.soft_charcoal else 4,args.tilted_shading)
    summary.update({"created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "requested_runs": args.repeats, "exit_codes": codes,
                    "tilted_shading": args.tilted_shading,"soft_charcoal": args.soft_charcoal})
    summary["passed"] = summary["passed"] and len(reports) == args.repeats and all(c == 0 for c in codes)
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
