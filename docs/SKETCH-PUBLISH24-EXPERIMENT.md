# Publication at 24ms: rejected responsiveness experiment

Do not deploy automatically. This branch keeps 32 input samples per GUI turn
and the original portable compiler profile. It changes only the periodic
display-damage notification window from 16ms to 24ms. Every material sample
is still computed, the first visible dab remains immediate, and finish/cancel
flush or discard pending damage as before. The native fast preview is unchanged.

Three actual tablet shading runs each, charcoal timings in milliseconds:

| Timing median / worst | Original16ms | Experimental24ms |
| --- | ---: | ---: |
| GUI gap | 130 / 136 | 118 / 175 |
| Queue p95 upper bound | 40 / 42 | 47 / 57 |
| Release-to-drained | 100 / 117 | 92 / 135 |

Both pass the original absolute 200/100/150ms budgets, but worst gap, queue
age and worst tail worsen. The separate 24-input-sample candidate has better
median/worst results than this variant in these runs. Reject this publication
change rather than combining it with another change without evidence.

Graphite gap median/worst45/51ms, queue19/20ms, tail33/40ms. Small samples
do not establish significance or universal speed. Synthetic evdev bypasses
physical touch sensing and no optical e-ink latency was measured.

Regression tests retain first-dab immediacy, complete material/pixel equality,
exact damage union, untouched-tile behavior and lifecycle checks. Publication
and latency tests explicitly assert the intended experimental 24ms period.
The first full host run passed 29 C++ cases and two C cases, then failed the
latency test's old16ms assertion. After updating that contract expectation
(not removing it), latency and raster were compiled and passed separately.
Thus all31 C++ cases have passing final results; the original failure is
retained in the logs. Five fault-injected installer tests passed. All three
tablet runs passed sample/display/preservation checks and absolute budgets.

Candidate raster:
`72e4a00b9c5e4642e998844e982530a1b0ce76ffed55029297b4059c9923372a`.
Source:
`db229943a9180d485c87d738ff19c80fae8d09c157f0c8f4929b4e3d7f9b5ec2`.
Ink, installed app/RCC, saved formats, artwork and public releases unchanged.
Raw evidence is retained locally in the Plan400 scheduling study. The native
candidate was removed after the tests, restoring original UAT before installing
the separate input24 candidate for human evaluation.
