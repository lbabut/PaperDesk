# Paper Sketch tool preferences (4.2.7)

The prior toolbar reset each tool to its factory width, and its selected width was kept only in an explicit sketchbook save. The UI now keeps all nine tool widths, the selected tool and the hard/kneaded eraser choice. A small versioned JSON file is independent of the artwork envelope, with bounded validated input and atomic replacement. Its cache namespace also isolates device diagnostics from user settings.

UI changes schedule an idle write after 500 ms, postponed while a stroke is active. Normal close and explicit Save flush pending settings. Tool-only changes do not dirty artwork. Rear erasing temporarily uses the remembered eraser width and retains the selected tool. Older saved single-tool settings are migrated; paper and physical tip wear retain their sketchbook Save semantics.

Native and QML checks cover cold file reopen, namespace isolation, rejected malformed/range-invalid data, drawing preservation, per-tool switching and idle-only writes. The tablet probe reopens the app after setting different pencil, charcoal, eraser and ink widths without saving the drawing; all choices return and no notebook is saved.

## Responsiveness investigation

The released drawing pipeline remains the one from 4.2.6. In a stress case with an 80px charcoal and 1200 fast samples, smaller GUI batches reduced the largest GUI pause from 536 to 121 ms but increased completion after input release from 2659 to 3908 ms. That pacing change was rejected. Compiler-tuning experiments brought about two percent in an isolated workload and were also left out. Neither is presented as a speed fix. Software queue/frame timings do not measure optical panel latency.
