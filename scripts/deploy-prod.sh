#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOST=${PAPERDESK_PROD_HOST:-azureuser@128.251.8.232}
KEY=${PAPERDESK_PROD_KEY:?Set PAPERDESK_PROD_KEY to the production SSH key}
DEST=${PAPERDESK_PROD_DEST:-/home/azureuser/PaperDesk}
NEXT="${DEST}.next"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="${DEST}.backup-${STAMP}"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new"
VERSION=$(tr -d '\r\n' <"$ROOT/product/VERSION")

test -f "$ROOT/dist/paperdesk-$VERSION.zip"

$SSH "$HOST" "rm -rf '$NEXT' && mkdir -p '$NEXT/website' '$NEXT/dist'"
rsync -a --delete \
    --exclude data/ \
    -e "ssh -i $KEY -o StrictHostKeyChecking=accept-new" \
    "$ROOT/website/" "$HOST:$NEXT/website/"
rsync -a --delete \
    -e "ssh -i $KEY -o StrictHostKeyChecking=accept-new" \
    "$ROOT/dist/" "$HOST:$NEXT/dist/"

$SSH "$HOST" "
set -eu
if test -d '$DEST'; then mv '$DEST' '$BACKUP'; fi
mv '$NEXT' '$DEST'
"

scp -i "$KEY" -o StrictHostKeyChecking=accept-new \
    "$ROOT/deploy/paperdesk-prod.service" "$HOST:/tmp/paperdesk-prod.service"
$SSH "$HOST" '
set -eu
sudo install -o root -g root -m 0644 /tmp/paperdesk-prod.service /etc/systemd/system/paperdesk-prod.service
rm -f /tmp/paperdesk-prod.service
sudo systemctl daemon-reload
sudo systemctl enable paperdesk-prod.service >/dev/null
sudo systemctl restart paperdesk-prod.service
'

attempt=0
until $SSH "$HOST" 'curl -fsS http://127.0.0.1/healthz >/dev/null'; do
    attempt=$((attempt + 1))
    if test "$attempt" -ge 20; then
        $SSH "$HOST" 'sudo systemctl status paperdesk-prod.service --no-pager -l' >&2
        exit 1
    fi
    sleep 1
done

curl -fsS "http://${HOST#*@}/healthz"
printf 'PaperDesk production deployed to http://%s/\n' "${HOST#*@}"
