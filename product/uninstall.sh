#!/bin/sh

set -eu

TARGET="/home/root/xovi/exthome/appload"
STATE="/home/root/.local/share/paperdesk"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"

if [ "$(id -u)" != "0" ]; then
    echo "Run the uninstaller as root." >&2
    exit 1
fi

NATIVE_RESTORE_STAGE=""
trap 'if [ -n "$NATIVE_RESTORE_STAGE" ]; then rm -f "$NATIVE_RESTORE_STAGE"; fi' EXIT
trap 'exit 1' HUP INT TERM

for app in paperdesk paperterminal paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download papersketch papercalc paperpet shims; do
    rm -rf "$TARGET/$app"
    if { [ -f "$STATE/original-recorded" ] || { [ "$app" = papersketch ] && [ -f "$STATE/sketch-original-recorded" ]; } || { [ "$app" = papercalc ] && [ -f "$STATE/calc-original-recorded" ]; }; } && [ -e "$STATE/original/apps/$app" ]; then
        cp -R "$STATE/original/apps/$app" "$TARGET/$app"
    fi
done

# Restore the material renderer managed by v4. Preserve user sketchbooks and exports.
if [ -f "$STATE/sketch-original-recorded" ]; then
    if [ -f "$STATE/original/system/papersketch-raster.so" ]; then
        NATIVE_RESTORE_STAGE=$(mktemp /home/root/xovi/extensions.d/.papersketch-uninstall.XXXXXX)
        cp -p "$STATE/original/system/papersketch-raster.so" "$NATIVE_RESTORE_STAGE"
        mv "$NATIVE_RESTORE_STAGE" /home/root/xovi/extensions.d/papersketch-raster.so
        NATIVE_RESTORE_STAGE=""
    else
        rm -f /home/root/xovi/extensions.d/papersketch-raster.so
    fi
fi

# Only v4.2.8+ manages the fast-preview extension. Restore a development
# module captured at the first managed upgrade, or remove our installed copy.
if [ -f "$STATE/sketch-ink-original-recorded" ]; then
    if [ -f "$STATE/original/system/papersketch-ink.so" ]; then
        NATIVE_RESTORE_STAGE=$(mktemp /home/root/xovi/extensions.d/.papersketch-ink-uninstall.XXXXXX)
        cp -p "$STATE/original/system/papersketch-ink.so" "$NATIVE_RESTORE_STAGE"
        mv "$NATIVE_RESTORE_STAGE" /home/root/xovi/extensions.d/papersketch-ink.so
        NATIVE_RESTORE_STAGE=""
    else
        rm -f /home/root/xovi/extensions.d/papersketch-ink.so
    fi
fi

# A legacy terminal saved before the PaperDesk installation can be restored.
# Never remove or replace an app the user installed after this upgrade.
if [ ! -e "$TARGET/literm" ] && [ -f "$STATE/original-recorded" ] &&
   [ -e "$STATE/original/apps/literm" ]; then
    cp -R "$STATE/original/apps/literm" "$TARGET/literm"
fi

rm -f /home/root/.local/bin/rmssh-menu
if [ -f "$STATE/original-recorded" ] && [ -f "$STATE/original/system/rmssh-menu" ]; then
    cp "$STATE/original/system/rmssh-menu" /home/root/.local/bin/rmssh-menu
fi
systemctl disable --now paperdesk-update.path 2>/dev/null || true
systemctl disable --now paperdesk-download.path 2>/dev/null || true
rm -f /etc/systemd/system/paperdesk-update.path /etc/systemd/system/paperdesk-update.service \
    /etc/systemd/system/paperdesk-download.path /etc/systemd/system/paperdesk-download.service
rm -rf /home/root/.local/lib/paperdesk
if [ -f "$STATE/original-recorded" ]; then
    for service in paperdesk-update.service paperdesk-update.path paperdesk-download.service paperdesk-download.path; do
        if [ -f "$STATE/original/system/$service" ]; then
            cp "$STATE/original/system/$service" "/etc/systemd/system/$service"
        fi
    done
fi
systemctl daemon-reload
if [ -f "$STATE/original-recorded" ]; then
    for service in paperdesk-update.service paperdesk-update.path paperdesk-download.service paperdesk-download.path; do
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
