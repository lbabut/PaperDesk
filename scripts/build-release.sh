#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '\r\n' < "$ROOT/product/VERSION")
OUT="$ROOT/dist/paperdesk-$VERSION.zip"
MANIFEST="$ROOT/website/update/latest.json"
SIGNATURE="$ROOT/website/update/latest.json.sig"
SIGNING_KEY=${PAPERDESK_SIGNING_KEY:-/home/lukasz/.config/paperdesk/release-signing-key.pem}
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT INT TERM

mkdir -p "$ROOT/dist"
rm -f "$OUT"
"$ROOT/scripts/update-product-checksums.sh"
mkdir -p "$STAGE/paperdesk-$VERSION"
cp -a "$ROOT/product/." "$STAGE/paperdesk-$VERSION/"
(cd "$STAGE" && zip -qr "$OUT" "paperdesk-$VERSION")
(cd "$ROOT/dist" && sha256sum "paperdesk-$VERSION.zip" > SHA256SUMS)
ARCHIVE_SHA=$(sha256sum "$OUT" | awk '{print $1}')
ARCHIVE_SIZE=$(wc -c < "$OUT" | tr -d ' ')
PUBLISHED_AT=$(sed -n 's/.*"releaseDate": "\([^"]*\)".*/\1/p' "$ROOT/product/release.json")
mkdir -p "$ROOT/website/update"
{
    printf '{\n'
    printf '  "product": "PaperDesk",\n'
    printf '  "channel": "stable",\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "publishedAt": "%s",\n' "$PUBLISHED_AT"
    printf '  "archiveUrl": "/download/paperdesk-%s.zip",\n' "$VERSION"
    printf '  "archiveSha256": "%s",\n' "$ARCHIVE_SHA"
    printf '  "archiveSize": %s,\n' "$ARCHIVE_SIZE"
    printf '  "releaseNotes": [\n'
    awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); notes[++n]=$0 } END { for (i=1; i<=n; ++i) printf "    \"%s\"%s\n", notes[i], (i<n ? "," : "") }' "$ROOT/product/RELEASE_NOTES.txt"
    printf '  ]\n'
    printf '}\n'
} > "$MANIFEST"
rm -f "$SIGNATURE"
if [ -f "$SIGNING_KEY" ]; then
    openssl pkeyutl -sign -rawin -inkey "$SIGNING_KEY" -in "$MANIFEST" -out "$SIGNATURE"
    openssl pkeyutl -verify -rawin -pubin \
        -inkey "$ROOT/product/payload/system/paperdesk-release-public.pem" \
        -sigfile "$SIGNATURE" -in "$MANIFEST" >/dev/null
else
    printf 'WARNING: release manifest was not signed; set PAPERDESK_SIGNING_KEY for an official build.\n' >&2
fi
printf 'Built %s\n' "$OUT"
