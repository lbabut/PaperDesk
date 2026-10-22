#!/bin/sh
# Explicit website deployment only; separate from sync-sources-lola.sh.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST=/home/lukasz/PaperDesk
NEXT=$(ssh -o BatchMode=yes lola "set -e; next=\$(mktemp -d '$DEST.next.XXXXXX'); cp -a '$DEST/.' \"\$next/\"; printf '%s\n' \"\$next\"")
case "$NEXT" in /home/lukasz/PaperDesk.next.??????) ;; *) echo 'Unsafe Lola staging path' >&2; exit 1;; esac
rsync -ac --exclude=data/ --exclude=__pycache__/ "$ROOT/website/" "lola:$NEXT/website/"
rsync -ac --exclude=windows/ "$ROOT/dist/" "lola:$NEXT/dist/"
scp -q "$ROOT/product/VERSION" "lola:$NEXT/VERSION"
scp -q "$ROOT/AGENTS.md" "lola:$NEXT/AGENTS.md"
scp -q "$ROOT/deploy/paperdesk-site-state.conf" "lola:$NEXT/.paperdesk-site-state.conf"
ssh -o BatchMode=yes lola sh -s -- "$NEXT" "$DEST" "$STAMP" <<'REMOTE'
set -eu
next=$1 dest=$2 stamp=$3
backup="$dest.backup-$stamp"
exec 9>/home/lukasz/.paperdesk-site-deploy.lock
flock -n 9 || { echo 'Another Lola site deployment is active.' >&2; exit 1; }
(cd "$next/dist" && sha256sum -c SHA256SUMS)
test ! -e "$backup"
unitdir=/home/lukasz/.config/systemd/user/paperdesk-site.service.d
mkdir -p "$unitdir" /home/lukasz/.local/share/paperdesk-site
chmod 700 /home/lukasz/.local/share/paperdesk-site
if test -f "$unitdir/paperdesk-state.conf"; then
    cp -a "$unitdir/paperdesk-state.conf" "$next/.previous-paperdesk-state.conf"
fi
cp "$next/.paperdesk-site-state.conf" "$unitdir/paperdesk-state.conf"
mv "$dest" "$backup"
if ! mv "$next" "$dest"; then mv "$backup" "$dest"; exit 1; fi
systemctl --user daemon-reload
systemctl --user restart paperdesk-site.service
ready=0
for attempt in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:8090/healthz >/dev/null; then ready=1; break; fi
    sleep 1
done
if test "$ready" != 1; then
    mv "$dest" "$dest.failed-$stamp"
    mv "$backup" "$dest"
    systemctl --user restart paperdesk-site.service
    echo 'Lola site rolled back; failed candidate retained.' >&2
    exit 1
fi
printf 'Lola deployment version: '; cat "$dest/VERSION"
printf 'Lola rollback directory: %s\n' "$backup"
REMOTE
curl -fsS http://192.168.1.40:8090/healthz
