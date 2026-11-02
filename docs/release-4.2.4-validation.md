# PaperDesk 4.2.4 validation

Based on the published Paper Sketch rear-stylus eraser implementation. The release retains synchronous rendering and excludes the progressive-preview prototype.

Implementation validation: 18 native test groups passed; QML 54 passed, 0 failed, 2 skipped; ARM build succeeded. On reMarkable 2, evdev checks verified stationary rear contact, rear dragging and normal nib resumption, preserving selected settings and saved pages.

Release verification covers signed stable/latest manifests, package and source archive checksums, current download routes, and preservation of the other app payloads. The production deployment uses a reviewed baseline, stages alongside the current site, backs up statistics, and retains the previous release directory.

Release checks passed: 41 package, 3 compatibility, 4 source-distribution and 16 website tests (64 total). All 140 payload files outside Care version metadata/resources are byte-identical to the published implementation.
