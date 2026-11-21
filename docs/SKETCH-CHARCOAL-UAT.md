# Sketch charcoal UAT — 2026-11-21

Test branch only, not a production release or a complete PaperDesk package.
Baseline: GitHub main b4798ba00544c0ca1a50a10c93669346e099e209.
The existing canonical dirty source tree is not overwritten.

## Change

Normal and soft charcoal retain more pigment on repeated passes, with
paper-space clumps rather than a smooth airbrush-like deposit. Only charcoal
tools 4/5 change. Saved pages are not automatically re-rendered or migrated.
The fast fresh-paper guide uses a fixed centerline sample cohort: averaging
only painted pixels incorrectly made high pressure appear lighter when the
footprint widened. Pencil lookup tables remain unchanged.

## Verification

Run `python3 scripts/test-sketch-native.py` with the cached Qt SDK described
by that script. It now includes `preview-core` and `charcoal-deposit`.
The old pre-optimization fixture remains intact. `charcoal-speed` compares
the new contract against a frozen scalar reference with cache and row worker
disabled. `charcoal-deposit` independently compares graphite/ink/eraser state
against the pre-change model, and checks twenty-layer darkening, bounded
pigment, conservative smudge, kneaded lift and zero-pressure no-op.
The finger-transport test now measures charcoal removal relative to available
darkness (30%), retaining exact mass conservation and increasing transport.
Its former absolute 60-gray-level threshold was unreachable on the old light
deposit as well; the corrected test is checked against both old and new models.

Build both modules with `python3 scripts/build-sketch-raster.py` and
`sh scripts/build-sketch-native.sh`. Candidate SHA256:

* raster: 227dd2ffedc7c1f867080d08ace59c40f545c09c333efd60537b4c8120f3e975
* ink: 5fb519b9ca50bd6c3697494ab82804d6c2748e1d8504ea5df01825e185b318e7

## USB UAT scope and recovery

`scripts/install-sketch-charcoal-uat.py` replaces only the shared native
modules on the explicitly verified old baseline. It requires owner permission
for a UI restart, strict trusted SSH identity, ARM ELF payloads and unchanged
installed baseline hashes. It retains both original modules and a rollback
script in a new directory under `/home/root/.local/state/` on the tablet.
No notebook, app resource, personal setting, public feed or stable download
is changed. Since native modules are global, the installed Sketch app DOES
use the UAT renderer until rollback; this is not a parallel isolated app.

Pass `--key`, `--known-hosts`, optional `--host-key-alias`,
`--safe-state-confirmed` and a local `--output` receipt path. Do not bypass a
baseline mismatch or host verification. Recovery is `sh BACKUP/rollback.sh`
on that same tablet while personal work is saved/closed. Startup and hash
checks are not user acceptance: test normal/soft charcoal, repeated shading,
pressure, smudge, erasing, save/reopen and pen responsiveness before promotion.
Physical realism and human drawing feel still require user acceptance.

## Verified UAT checkpoint

On 2026-11-21 the candidate was installed on the USB reMarkable 2 running
3.29.0.153. Both installed module hashes matched the candidate above and the
UI restarted successfully. The stable public channel and GitHub main were
not changed. Host regressions completed successfully: 31 C++ executables and
2 C executables, plus 4 fault-injected UAT installer tests. Product checksums
passed. The corrected finger-transport test also passed against the old model.

The actual tablet workflow test passed saved-page reopening, atomic PNG
export/collision handling, stable page deletion, discard and metadata recovery
in a unique test namespace. It restored the previous UI configuration and
verified the original Sketch document setting and 17 material/cache files;
this is not a full notebook-library audit. A technical PNG was retained under
Documents. No production release or human acceptance is implied.
The synthetic evdev pen/finger input probe also passed on the installed UAT
modules. Its settings and the same 17 original material/cache files were
preserved. Final checks found xochitl active, the failure monitor restored to
static, event2 at d:42, the old app RCC unchanged and the candidate raster
actually mapped into the running UI process. This does not measure physical
panel latency or replace drawing with a real stylus for human acceptance.
