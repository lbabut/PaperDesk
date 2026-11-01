#!/bin/sh
# Reproducible client/native-regression build using the verified local ARM SDK.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
TOOLS="$CACHE/arm-toolchain/root"
SDK="$CACHE/arm-sysroot/root"
FREERDP="$CACHE/FreeRDP"
BUILD="$FREERDP/build-rm2e"
SOURCE="$ROOT/product/payload/apps/paperrdp/paperrdp.cpp"
OUT="$ROOT/product/payload/apps/paperrdp/paperrdp"
case ${1:-} in
    --tests) SOURCE="$ROOT/tests/rdp-regression.cpp"; OUT="$ROOT/work/tests/rdp-regression" ;;
    --e2e) OUT="$ROOT/work/tests/paperrdp-e2e" ;;
    '') ;;
    *) echo 'Usage: build-rdp.sh [--tests|--e2e]' >&2; exit 64 ;;
esac
mkdir -p "$ROOT/work/tests"
STAGED=$(mktemp "$ROOT/work/tests/rdp-build.XXXXXX")
trap 'rm -f "$STAGED"' EXIT INT TERM
export LD_LIBRARY_PATH="$TOOLS/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EXTRA_DEFINE=
if [ "${1:-}" = --e2e ]; then EXTRA_DEFINE=-DPAPERDESK_E2E; fi
"$TOOLS/usr/bin/arm-linux-gnueabihf-g++-12" --sysroot="$TOOLS" \
    -std=c++17 -O2 -marm -mfpu=neon -mfloat-abi=hard $EXTRA_DEFINE \
    -I"$FREERDP/include" -I"$BUILD/include" -I"$FREERDP/winpr/include" -I"$BUILD/winpr/include" \
    -I"$SDK/usr/include" -I"$SDK/usr/include/arm-linux-gnueabihf" \
    "$SOURCE" "$ROOT/product/payload/apps/paperrdp/qtfb-client.cpp" \
    -L"$SDK/usr/lib/arm-linux-gnueabihf" \
    -Wl,--start-group "$BUILD/libfreerdp/libfreerdp3.a" "$BUILD/winpr/libwinpr/libwinpr3.a" \
    -Wl,--end-group -lssl -lcrypto -lz -ldl -lpthread -lrt -lm -o "$STAGED"
"$TOOLS/usr/bin/arm-linux-gnueabihf-strip" "$STAGED"
chmod 755 "$STAGED"
mv "$STAGED" "$OUT"
printf 'Built %s\n' "$OUT"
