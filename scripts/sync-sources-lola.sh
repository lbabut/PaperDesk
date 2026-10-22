#!/usr/bin/env bash
# Copy sources only. Never deploy or restart a service.
set -euo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CANONICAL=/home/lukasz/Documents/Codex/PaperDesk
HOST=lola
DEST=/home/lukasz/PaperDesk-sources
ARCHIVE=/home/lukasz/PaperDesk-source-snapshots
MODE=${1:---check}
if [[ $# -gt 1 || ( "$MODE" != --check && "$MODE" != --apply ) ]]; then
    echo 'Usage: bash scripts/sync-sources-lola.sh [--check|--apply]' >&2
    exit 2
fi
if [[ "$ROOT" != "$CANONICAL" ]]; then
    echo "Refusing: run from the authoritative project: $CANONICAL" >&2
    exit 2
fi
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10)
EXCLUDES=(
    --exclude=/.git/ --exclude=/work/ --exclude=/build/
    --exclude=__pycache__/ --exclude=.pytest_cache/
    '--exclude=*.pyc' '--exclude=*.log'
    --exclude=/website/data/ --exclude=/product/paperdesk.local.conf
    --exclude=/.paperdesk-history.bundle --exclude=/.paperdesk-source.sha256
    --exclude=/.paperdesk-snapshot.txt
)
if [[ "$MODE" == --check ]]; then
    # -n is intentional: --delete only reports obsolete paths; it removes nothing.
    rsync -rlnic --delete -e "${SSH[*]}" "${EXCLUDES[@]}" \
        "$ROOT/" "$HOST:$DEST/"
    exit
fi

mkdir -p -- /home/lukasz/Documents/Codex/PaperDesk-backups
exec 9>/home/lukasz/Documents/Codex/PaperDesk-backups/source-sync.lock
flock -n 9 || { echo 'Another source sync is running.' >&2; exit 1; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOCAL=$(mktemp -d "/home/lukasz/Documents/Codex/PaperDesk-backups/sources-$STAMP-XXXXXX")
echo "Local source backup: $LOCAL"
rsync -a --checksum --chmod=D700,Fgo-rwx "${EXCLUDES[@]}" "$ROOT/" "$LOCAL/"
git -C "$ROOT" bundle create "$LOCAL/.paperdesk-history.bundle" --all
git -C "$ROOT" bundle verify "$LOCAL/.paperdesk-history.bundle"
printf 'Captured at: %s\nAuthoritative source: %s\nCommitted HEAD: %s\nUncommitted and untracked source files are included separately from the Git bundle.\n' \
    "$STAMP" "$ROOT" "$(git -C "$ROOT" rev-parse HEAD)" >"$LOCAL/.paperdesk-snapshot.txt"

# A changing source tree is not a coherent snapshot; leave the backup and stop.
CHANGES=$(rsync -rlnic --delete "${EXCLUDES[@]}" "$ROOT/" "$LOCAL/")
if [[ -n "$CHANGES" ]]; then
    printf 'Source changed during capture. Nothing published. Retry after coordination:\n%s\n' "$CHANGES" >&2
    exit 1
fi
(
    cd -- "$LOCAL"
    find . -type f ! -name .paperdesk-source.sha256 -print0 |
        LC_ALL=C sort -z | xargs -0 sha256sum >.paperdesk-source.sha256
    sha256sum --quiet -c .paperdesk-source.sha256
)
REMOTE=$("${SSH[@]}" "$HOST" "mkdir -p '$ARCHIVE'; chmod 700 '$ARCHIVE'; mktemp -d '$ARCHIVE/sources-$STAMP-XXXXXX'")
if [[ ! "$REMOTE" =~ ^/home/lukasz/PaperDesk-source-snapshots/sources-[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9]{6}$ ]]; then
    echo 'Unexpected snapshot path; refusing to continue.' >&2
    exit 1
fi
rsync -a --checksum --chmod=D700,Fgo-rwx -e "${SSH[*]}" "$LOCAL/" "$HOST:$REMOTE/"
"${SSH[@]}" "$HOST" "cd '$REMOTE'; sha256sum --quiet -c .paperdesk-source.sha256"
CHANGES=$(rsync -rlnic --delete -e "${SSH[*]}" "$LOCAL/" "$HOST:$REMOTE/")
if [[ -n "$CHANGES" ]]; then
    printf 'Snapshot verification mismatch; pointer unchanged:\n%s\n' "$CHANGES" >&2
    exit 1
fi
# Check again before publication in case another author edited during transfer.
CHANGES=$(rsync -rlnic --delete "${EXCLUDES[@]}" "$ROOT/" "$LOCAL/")
if [[ -n "$CHANGES" ]]; then
    printf 'Source changed during transfer; pointer unchanged. Captured copies retained:\n%s\n' "$CHANGES" >&2
    exit 1
fi
"${SSH[@]}" "$HOST" bash -s -- "$REMOTE" <<'REMOTE_SCRIPT'
set -euo pipefail
umask 077
snapshot=$1
exec 9>/home/lukasz/PaperDesk-source-snapshots/.publish.lock
flock -n 9 || { echo 'Another publication is running.' >&2; exit 1; }
dest=/home/lukasz/PaperDesk-sources
if [[ -e "$dest" && ! -L "$dest" ]]; then
    preserved="/home/lukasz/PaperDesk-source-snapshots/previous-mirror-${snapshot##*/}"
    test ! -e "$preserved"
    mv -- "$dest" "$preserved"
    echo "Previous mirror preserved: $preserved"
fi
link="/home/lukasz/.PaperDesk-sources-${snapshot##*/}"
ln -s -- "$snapshot" "$link"
mv -T -- "$link" "$dest"
test "$(readlink -f -- "$dest")" = "$snapshot"
echo "Verified source pointer: $dest -> $snapshot"
REMOTE_SCRIPT
echo 'Source snapshot synchronized. No deployment or service restart performed.'
