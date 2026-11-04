#!/bin/sh
# Website + immutable archives only. Never replace global Caddy config or state.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOST=azureuser@128.251.8.232
KEY=/home/lukasz/Downloads/Pazuzu-key.pem
DEST=/home/azureuser/PaperDesk
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="$DEST.backup-$STAMP"
SSH="ssh -i $KEY -o StrictHostKeyChecking=yes -o BatchMode=yes"
VERSION=$(tr -d '\r\n' <"$ROOT/product/VERSION")
for file in "paperdesk-$VERSION.zip" "paperdesk-sources-$VERSION.tar.gz"; do
    test -s "$ROOT/dist/$file"
done
test -s "$ROOT/website/update/stable.json.sig"
test -s "$ROOT/website/update/latest.json.sig"
BASELINE=$($SSH "$HOST" "cd '$DEST'; find website -type f ! -path '*/__pycache__/*' ! -path 'website/data/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1")
if [ -n "${PAPERDESK_EXPECTED_PRODUCTION_BASELINE:-}" ] && [ "$BASELINE" != "$PAPERDESK_EXPECTED_PRODUCTION_BASELINE" ]; then
    echo 'Production differs from the reviewed release baseline; nothing staged.' >&2
    exit 1
fi
NEXT=$($SSH "$HOST" "set -e; umask 022; next=\$(mktemp -d '$DEST.next.XXXXXX'); cp -a '$DEST/.' \"\$next/\"; printf '%s\n' \"\$next\"")
case "$NEXT" in /home/azureuser/PaperDesk.next.??????) ;; *) echo 'Unsafe staging path' >&2; exit 1;; esac
if [ "$(printenv PAPERDESK_RELEASE_ONLY || true)" = 1 ]; then
    for feed in latest.json latest.json.sig stable.json stable.json.sig; do
        scp -q -i "$KEY" -o StrictHostKeyChecking=yes "$ROOT/website/update/$feed" "$HOST:$NEXT/website/update/$feed"
    done
    for file in "paperdesk-$VERSION.zip" "paperdesk-$VERSION.zip.sha256" "paperdesk-sources-$VERSION.tar.gz" "paperdesk-sources-$VERSION.tar.gz.sha256"; do
        scp -q -i "$KEY" -o StrictHostKeyChecking=yes "$ROOT/dist/$file" "$HOST:$NEXT/dist/$file"
    done
    scp -q -i "$KEY" -o StrictHostKeyChecking=yes "$ROOT/scripts/prepare-release-stage.py" "$HOST:$NEXT/.release-stage.py"
    $SSH "$HOST" python3 "$NEXT/.release-stage.py" "$NEXT" "$DEST" "$VERSION"
    $SSH "$HOST" rm -- "$NEXT/.release-stage.py"
else
# Do not --delete: retain production-only assets and older download URLs.
rsync -ac --exclude=data/ --exclude=__pycache__/ -e "ssh -i $KEY -o StrictHostKeyChecking=yes -o BatchMode=yes" "$ROOT/website/" "$HOST:$NEXT/website/"
rsync -ac --exclude=windows/ -e "ssh -i $KEY -o StrictHostKeyChecking=yes -o BatchMode=yes" "$ROOT/dist/" "$HOST:$NEXT/dist/"
fi
scp -q -i "$KEY" -o StrictHostKeyChecking=yes "$ROOT/product/payload/system/paperdesk-release-public.pem" "$HOST:$NEXT/.release-public.pem"
$SSH "$HOST" sh -s -- "$NEXT" "$DEST" "$BACKUP" "$BASELINE" "$STAMP" "$VERSION" <<'REMOTE'
set -eu
next=$1 dest=$2 backup=$3 baseline=$4 stamp=$5 version=$6
exec 9>/home/azureuser/.paperdesk-release.lock
flock -n 9 || { echo 'Another production deployment is running.' >&2; exit 1; }
current=$(cd "$dest"; find website -type f ! -path '*/__pycache__/*' ! -path 'website/data/*' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
test "$current" = "$baseline" || { echo 'Production changed during staging; nothing promoted.' >&2; exit 1; }
for feed in latest stable; do
    openssl pkeyutl -verify -rawin -pubin -inkey "$next/.release-public.pem" -in "$next/website/update/$feed.json" -sigfile "$next/website/update/$feed.json.sig"
done
(cd "$next/dist" && sha256sum -c SHA256SUMS)
# SQLite online backup includes a consistent database, not a raw live-file copy.
python3 - "$stamp" <<'PY'
from contextlib import closing
from pathlib import Path
import sqlite3, sys
folder = Path('/var/lib/paperdesk/backups')
folder.mkdir(mode=0o750, exist_ok=True)
target = folder / ('stats-before-' + sys.argv[1] + '.sqlite3')
with closing(sqlite3.connect('/var/lib/paperdesk/stats.sqlite3')) as src, closing(sqlite3.connect(target)) as dst:
    src.backup(dst)
    assert dst.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    print('Verified download-statistics backup:', target)
PY
before=$(curl -fsS http://127.0.0.1:8090/api/download-count | python3 -c 'import json,sys; print(json.load(sys.stdin)["downloaded"])')
test ! -e "$backup"
mv "$dest" "$backup"
if ! mv "$next" "$dest"; then mv "$backup" "$dest"; exit 1; fi
rollback() {
    failed="$dest.failed-$stamp"
    test ! -e "$failed" || return 1
    mv "$dest" "$failed"
    mv "$backup" "$dest"
    sudo systemctl restart paperdesk-prod.service
    echo "Site rolled back; failed candidate retained at $failed" >&2
}
if ! sudo systemctl restart paperdesk-prod.service; then rollback; exit 1; fi
ready=0
for attempt in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8090/healthz >/dev/null; then ready=1; break; fi
    sleep 1
done
if test "$ready" != 1; then rollback; exit 1; fi
after=$(curl -fsS http://127.0.0.1:8090/api/download-count | python3 -c 'import json,sys; print(json.load(sys.stdin)["downloaded"])')
if test "$after" -lt "$before"; then rollback; echo 'Counter unexpectedly decreased; inspect state.' >&2; exit 1; fi
printf 'Download counter preserved: %s -> %s\nSite rollback directory: %s\n' "$before" "$after" "$backup"
REMOTE
curl -fsS https://paperdesk.lukaszbabut.info/healthz
printf 'PaperDesk %s deployed to https://paperdesk.lukaszbabut.info/\n' "$VERSION"
