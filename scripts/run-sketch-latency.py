#!/usr/bin/env python3
"""Run the official isolated latency probe with the usual verified SSH options.

For comparison, --baseline-qml accepts a preserved UI source snapshot. The caller
must install the matching native renderer deliberately before each tablet run.
--latency-fresh-only runs just HB and charcoal on fresh pages for a shorter A/B.
All backup, input validation and restoration are handled by run-sketch-native.
Software raster/tile/frame timestamps are not optical e-ink latency.
"""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
raise SystemExit(subprocess.call([
    sys.executable, str(root / "tests/run-sketch-native.py"), "--latency-probe",
    "--output", "docs/papersketch-latency-device.json", *sys.argv[1:],
]))
