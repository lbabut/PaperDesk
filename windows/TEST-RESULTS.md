# Windows installer validation — 2026-10-01

## PaperDesk 2.0.2 — PaperPet removal

- 16 automated tests passed, including absence of PaperPet from the payload
  and verification that the upgrade script backs up PaperPet before removal.
- Product manifest regenerated and verified after the removal.
- Standalone 2.0.2 EXE self-test exited with status 0 and verified the embedded
  product: `PaperDesk 2.0.2 package OK 1319242 bytes`.
- Source and Windows ZIP saved on Nostalgiczny; transferred ZIP checksum verified.
- Earlier standalone EXE and UI tests below refer to version 2.0.1.

Environment: Windows 11 x64, Python 3.14.5, Paramiko 5.0.0,
PyInstaller 6.22.3; PaperDesk product 2.0.1 copied from Nostalgiczny.

- 15 automated tests passed: archive contents and executable script mode,
  exclusion of local credentials, corrupt/missing files, traversal paths,
  version mismatch, cancellation, failed upload, remote checksum failure,
  successful simulated installation, invalid addresses, SSH trust refusal,
  changed-key rejection, real product manifest, actual loopback SSH protocol
  with password authentication, stdout/stderr and nonzero exit status.
- Standalone Windows EXE built successfully (19,871,973 bytes).
- Standalone EXE `--self-test --report ...` exited with status 0 and verified
  its embedded product: `PaperDesk 2.0.1 package OK 1325740 bytes`.
- Standalone EXE `--ui-smoke` launched and exited; real installer window
  visually checked with Polish labels, masked code input and install button.
- Physical reMarkable test: pending user completion in the installer window.
- User reported that the remaining apps appear to work after the Windows
  installation. PaperPet was still present; the running installer was 2.0.1.
  Physical verification of the 2.0.2 removal upgrade remains pending.

- User subsequently confirmed the 2.0.2 upgrade works on the physical tablet.

The automated SSH test uses a local test server. It does not prove physical
tablet compatibility or successful recovery after a partial tablet install.

## Dependency preflight revision — 2026-10-01

- 27 automated tests covered across Windows and Linux: 21 passed on Windows
  (6 POSIX checks skipped); all 6 POSIX checks passed on Nostalgiczny.
- Missing tablet tools, XOVI extensions, Ed25519 support, disk space and SFTP
  stop installation before confirmation or tablet writes.
- Standalone EXE self-test and UI smoke both exited with status 0.
- Windows ZIP SHA-256: 1c28095c6b42bd6b8b34f44c6b47dc2dc76f9cb1ac2113ea85fb53a8a8e156b5.

## English installer revision — 2026-10-01

- All Windows installer labels, confirmations, errors, progress and dependency
  checks use English. Dialog buttons remain English on Polish Windows.
- 27 automated cases covered across Windows and POSIX hosts.
- Frozen EXE self-test exited 0; actual UI and missing-code error verified.
- Guide button names updated in both language versions.
- Windows ZIP SHA-256: 3db395988d2ad30af47b79aac7ba80fb5ba4a32682d009e9093d2e201aad429b.

## Optional tablet preparation — 2026-10-01

- New English Prepare tablet and install PaperDesk action, risk notice and
  unchecked acknowledgement; action stays disabled until acknowledgement.
- Supported automatic preparation: reMarkable 2, OS 3.29.0.149 only.
- Pinned official XOVI/resources v19, XOVI core 0.3.3, AppLoad 0.6.0,
  LiTerm backend 0.1.7. Download checksums and ARM32 binaries verified.
- 44 automated cases covered: 30 passed on Windows; 14 POSIX cases passed
  on Nostalgiczny, including fresh preparation, failure rollback, interrupted
  preparation recovery, incompatible dependencies and unknown extensions.
- Frozen EXE self-test with --check-dependencies exited 0 and verified all
  10 required files downloaded from upstream.
- Actual GUI warning, initially disabled action and Escape cancellation checked.
- 7 website tests passed; Polish and English guides updated.
- Physical clean-tablet bootstrap and recovery have not been tested.
- ZIP SHA-256: 55fe5d1aecb7d402088c724091fa1ef23b87b5a5c45f8d8ec896800329d7439b.
