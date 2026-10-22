#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PRODUCT="$ROOT/product"
OUTPUT="$PRODUCT/SHA256SUMS"
TEMP=$(mktemp)
trap 'rm -f -- "$TEMP"' EXIT INT TERM

(
    cd "$PRODUCT"
    find . -type f \
        ! -path './SHA256SUMS' \
        ! -path './paperdesk.local.conf' \
        -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
) > "$TEMP"
mv "$TEMP" "$OUTPUT"
trap - EXIT INT TERM
