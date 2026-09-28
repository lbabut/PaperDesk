#!/bin/sh

set -eu

TARGET="/home/root/xovi/exthome/appload"
STATE="/home/root/.local/share/paperdesk"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"

if [ "$(id -u)" != "0" ]; then
    echo "Run the uninstaller as root." >&2
    exit 1
fi

for app in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrss papercare shims; do
    rm -rf "$TARGET/$app"
    if [ -f "$STATE/original-recorded" ] && [ -e "$STATE/original/apps/$app" ]; then
        cp -R "$STATE/original/apps/$app" "$TARGET/$app"
    fi
done

rm -f /home/root/.local/bin/rmssh-menu
if [ -f "$STATE/original-recorded" ] && [ -f "$STATE/original/system/rmssh-menu" ]; then
    cp "$STATE/original/system/rmssh-menu" /home/root/.local/bin/rmssh-menu
fi
systemctl disable xovi-autostart.service 2>/dev/null || true
systemctl disable --now paperdesk-update.path 2>/dev/null || true
rm -f /etc/systemd/system/xovi-autostart.service
rm -f /etc/systemd/system/paperdesk-update.path /etc/systemd/system/paperdesk-update.service
rm -rf /home/root/.local/lib/paperdesk
if [ -f "$STATE/original-recorded" ]; then
    for service in xovi-autostart.service paperdesk-update.service paperdesk-update.path; do
        if [ -f "$STATE/original/system/$service" ]; then
            cp "$STATE/original/system/$service" "/etc/systemd/system/$service"
        fi
    done
fi
systemctl daemon-reload
if [ -f "$STATE/original-recorded" ]; then
    for service in xovi-autostart.service paperdesk-update.service paperdesk-update.path; do
        if [ -f "$STATE/original/system/$service.enabled" ]; then
            systemctl enable "$service"
        fi
    done
fi

LAST_BACKUP=""
if [ -f "$STATE/last-backup" ]; then
    LAST_BACKUP=$(sed -n '1p' "$STATE/last-backup")
fi
for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
    if [ -f "$STATE/original-recorded" ]; then
        if [ -f "$STATE/original/system/$resource" ]; then
            cp "$STATE/original/system/$resource" "$QRR_DIR/$resource"
        else
            rm -f "$QRR_DIR/$resource"
        fi
    elif [ -n "$LAST_BACKUP" ] && [ -f "$LAST_BACKUP/system/$resource" ]; then
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
echo "PaperDesk removed. Connection data and backups remain on the tablet."
if [ "${1:-}" != "--from-care" ]; then
    echo "Restart XOVI to reload the AppLoad resources."
fi
