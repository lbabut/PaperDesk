#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLCACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
RUNTIME="$TOOLCACHE/qt6-test-runtime/usr"
QML_RUNNER="$TOOLCACHE/qt6-qml-tools/root/usr/lib/qt6/bin/qmltestrunner"

export PAPERDESK_TOOLCACHE="$TOOLCACHE"

export LD_LIBRARY_PATH="$RUNTIME/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML2_IMPORT_PATH="$ROOT/tests/qml/imports:$RUNTIME/lib/x86_64-linux-gnu/qt6/qml"
export QT_PLUGIN_PATH="$RUNTIME/lib/x86_64-linux-gnu/qt6/plugins"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export QML_XHR_ALLOW_FILE_READ=1

TEST_CONFIG=$(mktemp -d)
trap 'rm -rf "$TEST_CONFIG"' EXIT INT TERM
export XDG_CONFIG_HOME="$TEST_CONFIG"

python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
"$QML_RUNNER" -input "$ROOT/tests/qml" -import "$ROOT/tests/qml/imports"
