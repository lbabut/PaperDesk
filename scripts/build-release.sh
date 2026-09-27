#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\r\n' < "$ROOT/product/VERSION")
OUT="$ROOT/dist/paperdesk-$VERSION.zip"
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT INT TERM

mkdir -p "$ROOT/dist"
rm -f "$OUT"
mkdir -p "$STAGE/paperdesk-$VERSION"
cp -a "$ROOT/product/." "$STAGE/paperdesk-$VERSION/"
(cd "$STAGE" && zip -qr "$OUT" "paperdesk-$VERSION")
(cd "$ROOT/dist" && sha256sum "paperdesk-$VERSION.zip" > SHA256SUMS)
printf 'Built %s\n' "$OUT"
