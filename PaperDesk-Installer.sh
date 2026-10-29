#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v python3 >/dev/null 2>&1 || {
    printf 'Install Python 3 and Tkinter before running the PaperDesk assistant.\n' >&2
    exit 1
}
python3 -c 'import tkinter' || {
    printf 'Install the Python 3 Tkinter package for your Linux distribution.\n' >&2
    exit 1
}
# Source checkout and packaged bundle use the same manual assistant.
if [ -f "$ROOT/wizard/manual_wizard.py" ]; then
    WIZARD="$ROOT/wizard/manual_wizard.py"
else
    WIZARD="$ROOT/windows/manual_wizard.py"
fi
exec python3 "$WIZARD" "$@"
