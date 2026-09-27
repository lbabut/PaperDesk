#!/bin/sh

set -eu

TABLET=${1:-10.11.99.1}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REMOTE_DIR="/home/root/paperdesk-install"

echo "Wysylam PaperDesk do root@$TABLET..."
ssh "root@$TABLET" "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"
scp -r "$SCRIPT_DIR"/. "root@$TABLET:$REMOTE_DIR/"
ssh -t "root@$TABLET" "chmod 755 '$REMOTE_DIR/install.sh' && '$REMOTE_DIR/install.sh'"
ssh "root@$TABLET" "/home/root/xovi/start"

echo "PaperDesk jest zainstalowany, a XOVI zostal uruchomiony ponownie."
