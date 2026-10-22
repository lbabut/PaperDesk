#!/bin/sh

set -eu

TABLET=${1:-10.11.99.1}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REMOTE_DIR="/home/root/paperdesk-install"
CONFIG=${PAPERDESK_CONFIG:-$SCRIPT_DIR/paperdesk.local.conf}

if [ -f "$CONFIG" ]; then
    # This file is intentionally excluded from Git and release publishing.
    . "$CONFIG"
fi

run_ssh() {
    if [ -n "${USB_MANAGEMENT_CODE:-}" ]; then
        DISPLAY=paperdesk:0 SSH_ASKPASS_REQUIRE=force \
            SSH_ASKPASS="$SCRIPT_DIR/usb-askpass.sh" \
            PAPERDESK_USB_CODE="$USB_MANAGEMENT_CODE" \
            setsid -w ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no "$@"
    else
        ssh "$@"
    fi
}

echo "Sending PaperDesk to root@$TABLET..."
run_ssh "root@$TABLET" "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"
tar -C "$SCRIPT_DIR" --exclude='./paperdesk.local.conf' -cf - . | \
    run_ssh "root@$TABLET" "tar -xf - -C '$REMOTE_DIR'"
run_ssh "root@$TABLET" "chmod 755 '$REMOTE_DIR/install.sh' && '$REMOTE_DIR/install.sh'"
run_ssh "root@$TABLET" "/home/root/xovi/start"

echo "PaperDesk is installed, and XOVI has restarted."
