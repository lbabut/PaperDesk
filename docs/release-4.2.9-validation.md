# PaperDesk 4.2.9 release validation

The owner accepted the tested Sketch fixes and authorized production publication. The native renderer, native preview and Sketch RCC in the signed update are identical to the verified tablet payload. Care's displayed version and release metadata are 4.2.9.

- 161 Python tests passed (2 skipped); package hashes, signed feeds, source distribution, installer safety, update compatibility and website routes are included.
- 284 QML tests passed (2 skipped), with no failures. The terminal core and matching native host plugin also built and passed.
- Nine final native ARM suites and the extended tablet input probe passed; saved drawings/settings were preserved. Reports are linked in the charcoal performance audit.
- Other application resource contents match production 4.2.8 after ignoring RCC timestamp metadata; Care's intentional version change is excluded.
- Update ZIP hashes and both Ed25519 feed signatures are verified. Source archives contain the same prepared product payload and all source checksums.
- The current production website was integrated from GitHub main, including its crayon design, handbook updates and five-euro Ko-fi links. Legacy website assertions were updated to check the current tab panels, persistent source navigation, download labels and actual screenshot links.
- Release-only staging is tested against both fixtures and the current live website snapshot. It changes the three HTML version/download documents, current notes, signed feeds and new archives. Styles, artwork, backend, existing immutable downloads and statistics are preserved; baseline/lock/rollback guards remain active.
- Software timing measures computation and input drain, not optical panel latency. XOVI boot startup remains manual.

Publication provenance and live download verification are recorded separately after deployment.
