# Source of truth and concurrent development

Agreed layout, 2026-10-17:

| Location | Purpose | Writable development source? |
| --- | --- | --- |
| nostalgiczny: `/home/lukasz/Documents/Codex/PaperDesk` | Authoritative current working tree, including uncommitted changes | Yes, with coordinated file ownership |
| Lola: `/home/lukasz/PaperDesk-sources` | Pointer to the latest verified source snapshot | No |
| Lola: `/home/lukasz/PaperDesk-source-snapshots/` | Retained source snapshots and the previous mirror | No |
| Lola: `/home/lukasz/PaperDesk` | Development website on port 8090 (deployed version in VERSION) | Deployment only |
| Pazuzu production | Public released website and downloads | Deployment only |

The authoritative working tree currently contains changes newer than Git HEAD.
A fresh clone of HEAD is not a current feature baseline. The source snapshots
include the working tree and a Git bundle of committed refs; the bundle alone
does not contain uncommitted changes. Restoring a snapshot requires its files
as well as its bundle. Restore into a NEW directory, never over active work.

## Sync without deployment

Run from the authoritative project:

```sh
bash scripts/sync-sources-lola.sh           # read-only comparison
bash scripts/sync-sources-lola.sh --apply   # new snapshot + checksum verification
```

The apply command first captures a local snapshot in the sibling
`PaperDesk-backups` directory. It includes current source files, untracked
feature files, tests, assets, release artifacts, and committed Git history.
It intentionally excludes `.git` internals, local `work/` (including keys),
`build/`, Python caches, logs, `website/data/`, and the tablet's local config.
This is a source copy, not a full machine/data backup. It does not publish
unfinished apps or make the existing release archives contain them.

Each copy gets a new directory on Lola. SHA-256 checks and a full rsync
comparison must succeed before the `PaperDesk-sources` pointer changes. A
concurrent local edit aborts publication; retry after the author has finished.
The initial pre-existing mirror is moved into the snapshot archive, not
deleted. Previous snapshots are never automatically pruned or overwritten.
No service is restarted and no running website directory is touched.

## Parallel changes

Prefer one branch/worktree per feature from an agreed up-to-date baseline.
Before that baseline exists, coordinate which files each author owns. Shared
installer/release/checksum changes need a single integration pass. Keep the
current PaperBooks author's files intact. Integration and release require
review of the combined diff, the normal automated tests, and relevant tablet
tests. Copying sources is not proof that an unfinished feature works.

For recovery, choose a retained snapshot, check `.paperdesk-source.sha256`,
and restore to a fresh directory. The `.paperdesk-history.bundle` can seed a
new Git checkout. Keep that checkout's `.git` while overlaying snapshot files,
and account for files deleted relative to the committed baseline. Do not
blindly merge two complete directory trees or run rsync with `--delete` over
another author's working tree.
