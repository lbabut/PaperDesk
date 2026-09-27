#!/bin/sh

set -eu

TARGET="/home/root/xovi/exthome/appload"
STATE="/home/root/.local/share/paperdesk"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"

if [ "$(id -u)" != "0" ]; then
    echo "Uruchom deinstalator jako root." >&2
    exit 1
fi

for app in paperdesk literm paperweb paperrdp-login paperrdp paperrss; do
    rm -rf "$TARGET/$app"
done

rm -f /home/root/.local/bin/rmssh-menu
systemctl disable xovi-autostart.service 2>/dev/null || true
rm -f /etc/systemd/system/xovi-autostart.service
systemctl daemon-reload

LAST_BACKUP=""
if [ -f "$STATE/last-backup" ]; then
    LAST_BACKUP=$(sed -n '1p' "$STATE/last-backup")
fi
for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
    if [ -n "$LAST_BACKUP" ] && [ -f "$LAST_BACKUP/system/$resource" ]; then
        cp "$LAST_BACKUP/system/$resource" "$QRR_DIR/$resource"
    else
        rm -f "$QRR_DIR/$resource"
    fi
done
if [ -f /home/root/.profile ]; then
    sed '/^# RMSSH-BEGIN/,/^# RMSSH-END/d' /home/root/.profile > /home/root/.profile.paperdesk-new
    mv /home/root/.profile.paperdesk-new /home/root/.profile
fi

rm -f "$STATE/current-version"
echo "PaperDesk usuniety. Dane polaczen i kopie zapasowe pozostaly na tablecie."
echo "Uruchom ponownie XOVI, aby przeladowac zasoby AppLoad."
