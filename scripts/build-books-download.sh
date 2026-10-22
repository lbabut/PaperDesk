#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
TOOLS="$CACHE/arm-toolchain/root"
HEADERS=${PAPERDESK_CURL_HEADERS:-/usr/include/x86_64-linux-gnu/curl}
mkdir -p "$ROOT/work/tests"
STAGED=$(mktemp "$ROOT/work/tests/books-download.XXXXXX")
trap 'rm -f "$STAGED"' EXIT INT TERM
export LD_LIBRARY_PATH="$TOOLS/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$TOOLS/usr/bin/arm-linux-gnueabihf-gcc-12" --sysroot="$TOOLS" -std=c11 -O2 -Wall -Wextra \
    -Wno-deprecated-declarations -iquote "$HEADERS" \
    "$ROOT/product/payload/apps/paperbooks-download/book-download.c" -ldl -o "$STAGED"
"$TOOLS/usr/bin/arm-linux-gnueabihf-strip" "$STAGED"
chmod 755 "$STAGED"
mv "$STAGED" "$ROOT/product/payload/apps/paperbooks-download/book-download"
