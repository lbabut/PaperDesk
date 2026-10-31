#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
SYSROOT="$CACHE/arm-toolchain/root"
export LD_LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$SYSROOT/usr/bin/arm-linux-gnueabihf-gcc-12" --sysroot="$SYSROOT" -O2 -fPIC -shared -marm \
    "$ROOT/product/payload/apps/papersketch/native/papersketch-ink.c" -ldl -lpthread \
    -o "$ROOT/product/payload/apps/papersketch/native/papersketch-ink.so"
