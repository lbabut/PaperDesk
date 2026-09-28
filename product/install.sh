#!/bin/sh

set -eu

PRODUCT="PaperDesk"
TARGET="/home/root/xovi/exthome/appload"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"
STATE="/home/root/.local/share/paperdesk"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD="$SCRIPT_DIR/payload"
VERSION=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")

printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "Invalid PaperDesk package version." >&2
    exit 1
}

if [ "$(id -u)" != "0" ]; then
    echo "Run the installer as root." >&2
    exit 1
fi

if [ ! -d "/home/root/xovi" ] || [ ! -d "$TARGET" ]; then
    echo "No active XOVI/AppLoad installation was found." >&2
    exit 1
fi

for required in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrss papercare shims; do
    if [ ! -d "$PAYLOAD/apps/$required" ]; then
        echo "Incomplete package: missing payload/apps/$required" >&2
        exit 1
    fi
done

for required in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml xovi-autostart.service paperdesk-update-agent paperdesk-update.service paperdesk-update.path paperdesk-release-public.pem; do
    if [ ! -f "$PAYLOAD/system/$required" ]; then
        echo "Incomplete package: missing payload/system/$required" >&2
        exit 1
    fi
done

if [ ! -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]; then
    echo "The qt-resource-rebuilder extension required by the AppLoad patch is missing." >&2
    exit 1
fi

# Capture the original installation once. Later upgrades must not replace this baseline.
ORIGINAL="$STATE/original"
if [ ! -f "$STATE/original-recorded" ] && [ ! -f "$STATE/current-version" ]; then
    mkdir -p "$ORIGINAL/apps" "$ORIGINAL/system"
    for app in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrss papercare shims; do
        if [ -e "$TARGET/$app" ]; then
            cp -R "$TARGET/$app" "$ORIGINAL/apps/$app"
        fi
    done
    for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
        if [ -f "$QRR_DIR/$resource" ]; then
            cp "$QRR_DIR/$resource" "$ORIGINAL/system/$resource"
        fi
    done
    for service in xovi-autostart.service paperdesk-update.service paperdesk-update.path; do
        if [ -f "/etc/systemd/system/$service" ]; then
            cp "/etc/systemd/system/$service" "$ORIGINAL/system/$service"
            if systemctl is-enabled --quiet "$service"; then
                touch "$ORIGINAL/system/$service.enabled"
            fi
        fi
    done
    if [ -f /home/root/.local/bin/rmssh-menu ]; then
        cp /home/root/.local/bin/rmssh-menu "$ORIGINAL/system/rmssh-menu"
    fi
    touch "$STATE/original-recorded"
fi

cp "$PAYLOAD/system/xovi-autostart.service" /etc/systemd/system/xovi-autostart.service
cp "$PAYLOAD/system/paperdesk-update.service" /etc/systemd/system/paperdesk-update.service
cp "$PAYLOAD/system/paperdesk-update.path" /etc/systemd/system/paperdesk-update.path
mkdir -p /home/root/.local/lib/paperdesk
cp "$PAYLOAD/system/paperdesk-update-agent" /home/root/.local/lib/paperdesk/paperdesk-update-agent
cp "$PAYLOAD/system/paperdesk-release-public.pem" /home/root/.local/lib/paperdesk/release-public.pem
cp "$SCRIPT_DIR/uninstall.sh" /home/root/.local/lib/paperdesk/paperdesk-uninstall
chmod 755 /home/root/.local/lib/paperdesk/paperdesk-update-agent /home/root/.local/lib/paperdesk/paperdesk-uninstall
chmod 644 /home/root/.local/lib/paperdesk/release-public.pem
systemctl daemon-reload
systemctl enable xovi-autostart.service
systemctl enable --now paperdesk-update.path

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$STATE/backups/$STAMP"
mkdir -p "$BACKUP/apps" "$BACKUP/system" "$TARGET" /home/root/.local/bin \
    /home/root/.config/literm /home/root/.config/rmssh "$QRR_DIR"

echo "$PRODUCT $VERSION — installation"
echo "Previous-version backup: $BACKUP"

for app in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrss papercare shims; do
    if [ -e "$TARGET/$app" ]; then
        cp -R "$TARGET/$app" "$BACKUP/apps/$app"
    fi
    rm -rf "$TARGET/$app"
    cp -R "$PAYLOAD/apps/$app" "$TARGET/$app"
done

if [ -f /home/root/.local/bin/rmssh-menu ]; then
    cp /home/root/.local/bin/rmssh-menu "$BACKUP/system/rmssh-menu"
fi
cp "$PAYLOAD/system/rmssh-menu" /home/root/.local/bin/rmssh-menu
chmod 755 /home/root/.local/bin/rmssh-menu "$TARGET/paperrdp/paperrdp" \
    "$TARGET/paperweb-download/download"

for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
    if [ -f "$QRR_DIR/$resource" ]; then
        cp "$QRR_DIR/$resource" "$BACKUP/system/$resource"
    fi
    cp "$PAYLOAD/system/$resource" "$QRR_DIR/$resource"
done

if [ -f /home/root/.config/literm/settings.ini ]; then
    cp /home/root/.config/literm/settings.ini "$BACKUP/system/literm-settings.ini"
else
    cp "$PAYLOAD/system/literm-settings.ini" /home/root/.config/literm/settings.ini
fi

if [ ! -f /home/root/.config/rmssh/profiles ]; then
    cp "$PAYLOAD/system/profiles.example" /home/root/.config/rmssh/profiles
fi
chmod 600 /home/root/.config/rmssh/profiles

touch /home/root/.profile
if ! grep -q '^# RMSSH-BEGIN' /home/root/.profile; then
    cp /home/root/.profile "$BACKUP/system/profile"
    printf '\n' >> /home/root/.profile
    sed -n '/^# RMSSH-BEGIN/,/^# RMSSH-END/p' "$PAYLOAD/system/profile-hook.sh" >> /home/root/.profile
fi

printf '%s\n' "$VERSION" > "$STATE/current-version"
printf '%s\n' "$BACKUP" > "$STATE/last-backup"

echo
echo "Done. Restart XOVI with /home/root/xovi/start."
echo "XOVI and PaperDesk will start automatically after a device reboot."
echo "Connection profiles and app data have been preserved."
