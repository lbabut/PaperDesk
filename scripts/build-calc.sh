#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
RCC="$CACHE/qt-rcc-pkg/root/usr/lib/qt5/bin/rcc"
cd "$ROOT/product/payload/apps/papercalc"
"$RCC" --binary application.qrc -o resources.rcc
printf 'Built Paper Calc resources\n'
