#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\r\n' < "$ROOT/product/VERSION")
OUT="$ROOT/dist/paperdesk-linux-installer-$VERSION.tar.gz"
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT INT TERM
mkdir -p "$ROOT/dist" "$STAGE/paperdesk-linux-installer-$VERSION"
(
    cd "$ROOT/product"
    sha256sum -c SHA256SUMS >/dev/null
)
cp -a "$ROOT/product" "$STAGE/paperdesk-linux-installer-$VERSION/"
cp "$ROOT/PaperDesk-Installer.sh" "$STAGE/paperdesk-linux-installer-$VERSION/"
chmod 755 "$STAGE/paperdesk-linux-installer-$VERSION/PaperDesk-Installer.sh"
rm -f "$STAGE/paperdesk-linux-installer-$VERSION/product/paperdesk.local.conf"
tar -C "$STAGE" -czf "$OUT" "paperdesk-linux-installer-$VERSION"
(cd "$ROOT/dist" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
printf 'Built %s\n' "$OUT"
