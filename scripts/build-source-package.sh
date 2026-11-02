#!/bin/sh
# Project source plus prepared tablet payload; no desktop binaries or secrets.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\r\n' < "$ROOT/product/VERSION")
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT INT TERM
NAME="paperdesk-sources-$VERSION"
mkdir -p "$STAGE/$NAME" "$ROOT/dist"
for entry in product windows scripts tests docs website README.md AGENTS.md LICENSES.md INSTALL-DESKTOP.md INSTALL-WINDOWS.md PaperDesk-Installer.sh; do
    test ! -e "$ROOT/$entry" || rsync -a --exclude=__pycache__/ --exclude=data/ --exclude='*.pyc' --exclude='*.exe' --exclude='*.spec' --exclude=paperdesk.local.conf "$ROOT/$entry" "$STAGE/$NAME/"
done
(cd "$STAGE/$NAME" && find . -type f ! -name SOURCE-SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > SOURCE-SHA256SUMS)
tar -czf "$ROOT/dist/$NAME.tar.gz" -C "$STAGE" "$NAME"
(cd "$ROOT/dist" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
(cd "$ROOT/dist" && find . -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' \) -printf '%f\0' | LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)
printf 'Built %s (source + prepared ARM files)\n' "$NAME.tar.gz"
