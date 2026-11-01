#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TOOLCACHE=${PAPERDESK_TOOLCACHE:-/home/lukasz/Documents/Codex/2026-09-25/m-2/work}
# The native plugin is built against Qt 6.8. Use matching host QtTest tools;
# mixing the older cached Qt 6.4 test libraries with it is ABI-incompatible.
# These packages are extracted locally; the runner never installs host packages.
QT_TEST_ROOT=${PAPERDESK_QT_TEST_ROOT:-$ROOT/work/terminal-qt-tests/root}
QT_TEST_USR="$QT_TEST_ROOT/usr"
QML_RUNNER=${PAPERDESK_QML_RUNNER:-$QT_TEST_USR/lib/qt6/bin/qmltestrunner}
if [ ! -x "$QML_RUNNER" ]; then
    printf 'Qt 6.8 qmltestrunner not found. Set PAPERDESK_QML_RUNNER and PAPERDESK_QT_TEST_ROOT.\n' >&2
    exit 1
fi

export PAPERDESK_TOOLCACHE="$TOOLCACHE"
export LD_LIBRARY_PATH="$QT_TEST_USR/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML2_IMPORT_PATH="$ROOT/tests/qml/imports:$QT_TEST_USR/lib/x86_64-linux-gnu/qt6/qml:/usr/lib/x86_64-linux-gnu/qt6/qml"
export QT_PLUGIN_PATH="$QT_TEST_USR/lib/x86_64-linux-gnu/qt6/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export QML_XHR_ALLOW_FILE_READ=1

TEST_CONFIG=$(mktemp -d)
QML_OUTPUT=$(mktemp)
QML_STAGE=$(mktemp -d)
trap 'rm -rf "$TEST_CONFIG"; rm -f "$QML_OUTPUT"; rm -rf "$QML_STAGE"' EXIT INT TERM
export XDG_CONFIG_HOME="$TEST_CONFIG"
export XDG_DATA_HOME="$TEST_CONFIG/data"
export XDG_CACHE_HOME="$TEST_CONFIG/cache"

python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
# Exercise the real native QML plugin, built for the host, in an isolated
# copy. The shipped ARM plugin and application files remain untouched.
mkdir -p "$ROOT/work/terminal-native-tests"
"${CXX:-g++}" -std=c++17 -O2 -Wall -Wextra -Werror \
    "$ROOT/tests/terminal-core.cpp" -o "$ROOT/work/terminal-native-tests/terminal-core"
"$ROOT/work/terminal-native-tests/terminal-core"
python3 "$ROOT/scripts/build-terminal.py" --test
mkdir -p "$QML_STAGE/tests" "$QML_STAGE/work/papersketch-tests"
cp -a "$ROOT/tests/qml" "$QML_STAGE/tests/"
cp -a "$ROOT/tests/device" "$QML_STAGE/tests/"
cp -a "$ROOT/product" "$QML_STAGE/product"
cp "$ROOT/work/terminal-native-host/libpaperterminal_native.so" \
    "$QML_STAGE/product/payload/apps/paperterminal/native/libpaperterminal_native.so"
# The installed location is fixed in the resource's qmldir. Point this
# isolated host copy at its matching native plugin instead.
sed -i "s|/home/root/xovi/exthome/appload/paperterminal/native|$QML_STAGE/product/payload/apps/paperterminal/native|" \
    "$QML_STAGE/product/payload/apps/paperterminal/native/qmldir"
"$QML_RUNNER" -input "$QML_STAGE/tests/qml" -import "$ROOT/tests/qml/imports" | tee "$QML_OUTPUT"
grep -Eq '^Totals: [0-9]+ passed, 0 failed,' "$QML_OUTPUT"
