#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOST=${PAPERDESK_LOLA_HOST:-lola}

ssh "$HOST" 'mkdir -p /home/lukasz/PaperDesk /home/lukasz/.config/systemd/user /srv/lola/landing'
rsync -a --delete --exclude .git --exclude website/data/ "$ROOT/" "$HOST:/home/lukasz/PaperDesk/"
scp "$ROOT/deploy/paperdesk-site.service" "$HOST:/home/lukasz/.config/systemd/user/paperdesk-site.service"
scp "$ROOT/deploy/lola-landing/index.html" "$HOST:/srv/lola/landing/index.html"
scp "$ROOT/deploy/lola-landing/server.py" "$HOST:/srv/lola/landing/server.py"
ssh "$HOST" 'chmod 700 /srv/lola/landing /home/lukasz/PaperDesk/website; chmod 600 /srv/lola/landing/index.html /srv/lola/landing/server.py; systemctl --user disable --now lola-landing.service >/dev/null 2>&1 || true; rm -f /home/lukasz/.config/systemd/user/lola-landing.service; systemctl --user daemon-reload; systemctl --user enable paperdesk-site.service >/dev/null; systemctl --user restart paperdesk-site.service; old=$(pgrep -f "^/usr/bin/python3 /srv/lola/landing/server.py$" || true); if [ -n "$old" ]; then kill $old; fi'

attempt=0
until curl -fsS "http://192.168.1.40/health" >/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 20 ] || { echo 'Lola landing did not recover' >&2; exit 1; }
    sleep 1
done

curl -fsS "http://192.168.1.40:8090/healthz"
curl -fsS "http://192.168.1.40/health"
printf 'PaperDesk deployed to http://192.168.1.40:8090/\n'
