#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 -c "from pathlib import Path; Path('work').mkdir(exist_ok=True); Path('work/test-settings.ini').unlink(missing_ok=True)"
node tests/calc-engine.cjs
QT_TEST_USR=${PAPERDESK_QT_TEST_USR:-/home/lukasz/Documents/Codex/PaperDesk/work/terminal-qt-tests/root/usr}
export LD_LIBRARY_PATH="$QT_TEST_USR/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML2_IMPORT_PATH="$PWD/tests/calc-imports:$QT_TEST_USR/lib/x86_64-linux-gnu/qt6/qml:/usr/lib/x86_64-linux-gnu/qt6/qml"
export QT_PLUGIN_PATH="$QT_TEST_USR/lib/x86_64-linux-gnu/qt6/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins"
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
TEST_CONFIG=$(mktemp -d)
CALC_STAGE=$(mktemp -d)
mkdir -p "$CALC_STAGE/tests/qml"
cp tests/qml/tst_papercalc.qml tests/qml/tst_calcgraph.qml "$CALC_STAGE/tests/qml/"
ln -s "$PWD/product" "$CALC_STAGE/product"
ln -s "$PWD/work" "$CALC_STAGE/work"
trap 'rm -rf "$TEST_CONFIG" "$CALC_STAGE"' EXIT INT TERM
export XDG_CONFIG_HOME="$TEST_CONFIG"
"$QT_TEST_USR/lib/qt6/bin/qmltestrunner" -input "$CALC_STAGE/tests/qml"
