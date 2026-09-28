#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PRODUCT="$ROOT/product"
ASKPASS="$PRODUCT/usb-askpass.sh"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"

fail() {
    zenity --error --title="PaperDesk Installer" --text="$1" 2>/dev/null || true
    exit 1
}

command -v zenity >/dev/null 2>&1 || {
    printf 'Install zenity before running PaperDesk Installer.\n' >&2
    exit 1
}
for tool in ssh ssh-keyscan ssh-keygen sha256sum setsid tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done
[ -f "$PRODUCT/SHA256SUMS" ] || fail "The product package is missing."
(
    cd "$PRODUCT"
    sha256sum -c SHA256SUMS >/dev/null
) || fail "Package checksum verification failed."

HOST=$(zenity --entry --title="PaperDesk Installer" \
    --text="reMarkable 2 address (connect USB first)" --entry-text="10.11.99.1") || exit 0
case "$HOST" in
    ""|*[!a-zA-Z0-9.:_-]*) fail "Invalid tablet address." ;;
esac
CODE=$(zenity --password --title="PaperDesk Installer" \
    --text="USB management code from tablet settings") || exit 0
[ -n "$CODE" ] || fail "USB management code is required."
export USB_MANAGEMENT_CODE="$CODE"
export PAPERDESK_USB_CODE="$CODE"
export PAPERDESK_CONFIG="/nonexistent/paperdesk.local.conf"
unset CODE

HOST_KEY=$(ssh-keyscan -T 6 -t ed25519 "$HOST" 2>/dev/null |
    awk '$2 == "ssh-ed25519" { print; exit }')
[ -n "$HOST_KEY" ] || fail "Cannot read the tablet SSH key."
PUBLIC_KEY=$(printf '%s\n' "$HOST_KEY" | awk '{print $3}')
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$KNOWN_HOSTS"
chmod 600 "$KNOWN_HOSTS"
if ssh-keygen -F "$HOST" -f "$KNOWN_HOSTS" 2>/dev/null | grep -qv '^#'; then
    ssh-keygen -F "$HOST" -f "$KNOWN_HOSTS" 2>/dev/null |
        grep -Fq "$PUBLIC_KEY" || fail "The tablet SSH identity changed. Installation stopped."
else
    FINGERPRINT=$(printf '%s\n' "$HOST_KEY" | ssh-keygen -lf - -E sha256 |
        awk '{print $2}')
    zenity --question --title="Trust this tablet?" \
        --text="First connection to $HOST.\nSSH fingerprint: $FINGERPRINT\n\nTrust this device?" ||
        exit 0
    printf '%s\n' "$HOST_KEY" >> "$KNOWN_HOSTS"
fi

remote() {
    DISPLAY=paperdesk:0 SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ASKPASS" \
        setsid -w ssh -o StrictHostKeyChecking=yes \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -o ConnectTimeout=12 "root@$HOST" "$1"
}

CHECK=$(remote 'test -d /home/root/xovi &&
    test -d /home/root/xovi/exthome/appload &&
    test -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so || exit 22
    printf "VERSION="
    cat /home/root/.local/share/paperdesk/current-version 2>/dev/null || true
    for app in paperdesk literm paperweb paperrdp-login paperrdp paperrss papercare shims; do
        if test -e "/home/root/xovi/exthome/appload/$app"; then
            printf "APP=%s\n" "$app"
        fi
    done' 2>&1) || fail "Tablet check failed:\n$CHECK"
VERSION=$(printf '%s\n' "$CHECK" | sed -n 's/^VERSION=//p' | head -1)
APPS=$(printf '%s\n' "$CHECK" | sed -n 's/^APP=//p' | paste -sd ',' -)
[ -n "$VERSION" ] || VERSION="none"
[ -n "$APPS" ] || APPS="none"
zenity --question --title="Install PaperDesk" --width=520 \
    --text="Current PaperDesk: $VERSION\nExisting app IDs: $APPS\n\nMatching IDs will be backed up and replaced. Other apps are untouched. Continue?" ||
    exit 0

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT INT TERM
if ! "$PRODUCT/install-from-computer.sh" "$HOST" >"$LOG" 2>&1; then
    DETAIL=$(tail -25 "$LOG")
    fail "Installation failed:\n$DETAIL"
fi
zenity --info --title="PaperDesk Installer" \
    --text="PaperDesk installed. XOVI restarted." 2>/dev/null || true
