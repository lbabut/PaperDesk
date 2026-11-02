# PaperDesk source coordination

## Authoritative working tree

- The authoritative project is `/home/lukasz/Documents/Codex/PaperDesk` on
  nostalgiczny. Preserve all existing tracked and untracked changes.
- `/home/lukasz/PaperDesk-sources` on Lola is a snapshot pointer, NOT a second
  writable development repository. Never copy its whole tree or `.git` back
  over the authoritative project.
- `/home/lukasz/PaperDesk` on Lola serves the development website.
  It is a deployment, NOT the source of truth. Do not deploy or overwrite
  it as part of source synchronization. Production is separate as well.

## Concurrent work

- Check the current diff and agree on file ownership before changing shared
  files. In particular, coordinate installer, release metadata, checksums,
  shared launcher, README, and common test-runner changes.
- New feature work should use a separate Git branch/worktree based on an
  explicitly agreed current baseline. HEAD alone may be much older than the
  dirty working tree: do not start from it and assume it contains recent fixes.
- Until a baseline is agreed, edit only your feature's agreed files. PaperBooks
  belongs to its existing author; unrelated agents must not replace its files.
- Do not stage, commit, reset, stash, merge, or deploy another agent's changes
  without agreement. Never bulk-overwrite a shared working directory.

## Copies and releases

- Use `bash scripts/sync-sources-lola.sh` to preview source differences and
  `bash scripts/sync-sources-lola.sh --apply` to create and verify a new snapshot.
- Source synchronization must not run deployment scripts, restart services,
  publish releases, or change tablet state.
- See `docs/SOURCE-WORKFLOW.md` for paths, exclusions, and recovery.

## Production and GitHub

- User instruction (2026-11-02): every production publication, including a
  request phrased as "deploy", must also publish the corresponding code,
  tests and documentation to GitHub. Verify the production package and
  GitHub source commit agree before reporting deployment complete.
