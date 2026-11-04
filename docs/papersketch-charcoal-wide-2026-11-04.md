# Wide charcoal calculation — 2026-11-04

Status: candidate; host regressions and ARM module build passed. Tablet performance measurement and installation are pending device connectivity.

Wide normal and soft charcoal dabs now divide their scanlines between the caller and one persistent worker. Each dab joins before the next dab, so every pixel receives exactly the original sequence of deposits and burnishing. The tooth, pressure, tilt, wear, spacing and pigment formulas are unchanged. The two charcoal kernels are specialized at compile time.

The second thread is started lazily and used only on multicore systems for footprints with area at least 200 and at least 17 scanlines. Smaller footprints and other media keep the serial path. One shared worker serializes concurrent independent callers. Footprint columns and prepared fresh-contact responses are read-only during parallel painting; pigment, optical image and burnishing writes have disjoint scanlines.

No additional grain/contact lookup cache is shipped. Native tests compare the entire optical image, pigment, finger, burnish, ink, wear and sampling state against the frozen header from commit 031fd0235e679dc030c9e9d1f0c1e9e6502711ab. They cover all nine tools, three papers, pressure ramps, tilt, sizes 1–80, reused engines, mixed polished/tooth pairs, erasers and a shared-worker concurrency case.

## Reproduce

Run scripts/test-sketch-native.py for host coverage. The focused new test is tests/test-sketch-charcoal-speed.cpp; it requires C++17 and pthread support, with no Qt dependency.

Run scripts/run-sketch-tablet-regressions.py with --host, --host-key-alias, --key, --known-hosts and --output for nine ARM suites directly on the tablet CPU. Add --charcoal-benchmark for paired old/current normal and soft charcoal workloads at 48 and 80 px with constant and varying pressure. Benchmark cases verify complete physical-state equality after timing. No UI restart or input grab is needed; saved artwork hashes must remain unchanged.

After installation, use tests/run-sketch-native.py --extended-fidelity-probe --fidelity-brush-size 80 with the same SSH arguments for full input/rendering, charcoal layering, kneaded erasing, Clear and Care foreground regressions in an isolated namespace. This test temporarily restarts the tablet UI and restores the owner's files.

Timing results measure software computation, not optical panel latency. No speedup is claimed for the threaded candidate before measurement on the tablet.

## Host validation

Focused host regressions passed for full-state charcoal equivalence, shared-worker concurrency, charcoal layers, kneaded strength, material, material realism, pressure, contact-cache compatibility, realism integration, blank-pigment migration, rapidograph integration and rear stylus erasure. The final worker test and both eraser/ink integrations passed after caching the multicore capability check. The ARM module build completed successfully.

No threaded speedup or tablet deployment is asserted by these host results.
