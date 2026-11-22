# Ten independent painting CPU experiments

Baseline: installed rowspan candidate 802925a, raster SHA256
29d482734f987777a8b355df8a3511d9a93f0e843375daee0f9950c8d52975a7.
Canonical dirty source tree (343 entries) untouched. No module installation,
GUI restart, input injection or artwork mutation in this screening series.

Generate with `python3 scripts/sketch-ten-probes.py`. This creates independent
headers and statically linked ARM tests in `work/ten-probes`, using the same
O2 compiler and workload. The reference is frozen from the current material
header before any variant is generated. The run script executes only standalone
memory/CPU tests, not Sketch. Copy generated artifacts to the explicitly named
device `/tmp/sketch-ten-20261122` directory first.

Every variant passed full-state comparisons after 8100 cross-tool dabs,
2000 varied charcoal dabs and the timed traces. The first screening has two
opposite-order timing pairs for each tool and tilt, not a statistical efficacy
trial. Ratios below are new/reference CPU time for soft charcoal at tilt .95;
other tool/tilt results must also be considered (see raw JSON).

| # | Independent change | Initial ratio | Decision |
| --- | --- | --- | --- |
| 1 | Prefetch pigment mass | 1.035 | Reject |
| 2 | Prefetch grain response | 1.087 | Reject |
| 3 | Hoist row address multiplication | 1.007 | Reject |
| 4 | Remove extra row-bound guard pixel | 1.012 | Reject; no speed reason to weaken guard |
| 5 | Raise parallel area threshold 200 to 400 | 1.372 | Reject |
| 6 | Lower parallel area threshold 200 to 100 | .883 | Advance to application testing, not UAT yet |
| 7 | Lower fresh-contact cache area 144 to 64 | 1.020 | Reject |
| 8 | Raise fresh-contact cache area 144 to 256 | 1.027 | Reject |
| 9 | Apply row spans to circular charcoal footprints too | .877 | Reject after confirmation ratio 1.019 |
| 10 | Avoid identical image stores | 1.025 | Reject |

Two extra executions for #6 give six opposite-order timing pairs overall.
Soft tilted ratios in the extra executions average .815 and .886; normal
charcoal gains generally persist, with one upright outlier. Graphite/finger
are near unchanged in these traces. This is evidence for a GUI pilot, not
proof of lower painting latency, physical panel latency or full performance
acceptance. Full application regressions and a real guarded GUI comparison
are separate gates. No point, pressure, pigment, wear or model simplification.

`results*.json` and `*.arm.log` are retained in the Plan400 evidence directory
`sketch-ten-study-20261122`. The separate parallel100 candidate branch contains
the proposed one-line runtime change and updated module; this research branch
keeps baseline product sources and binaries unchanged.
