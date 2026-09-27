#!/bin/sh

set -eu

PRODUCT="PaperDesk"
VERSION="1.0.5"
TARGET="/home/root/xovi/exthome/appload"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"
STATE="/home/root/.local/share/paperdesk"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD="$SCRIPT_DIR/payload"

if [ "$(id -u)" != "0" ]; then
    echo "Uruchom instalator jako root." >&2
    exit 1
fi

if [ ! -d "/home/root/xovi" ] || [ ! -d "$TARGET" ]; then
    echo "Nie znaleziono aktywnej instalacji XOVI/AppLoad." >&2
    exit 1
fi

for required in paperdesk literm paperweb paperrdp-login paperrdp paperrss shims; do
    if [ ! -d "$PAYLOAD/apps/$required" ]; then
        echo "Niepelna paczka: brak payload/apps/$required" >&2
        exit 1
    fi
done

for required in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml xovi-autostart.service; do
    if [ ! -f "$PAYLOAD/system/$required" ]; then
        echo "Niepelna paczka: brak payload/system/$required" >&2
        exit 1
    fi
done

cp "$PAYLOAD/system/xovi-autostart.service" /etc/systemd/system/xovi-autostart.service
systemctl daemon-reload
systemctl enable xovi-autostart.service

if [ ! -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]; then
    echo "Brak rozszerzenia qt-resource-rebuilder wymaganego przez poprawke AppLoad." >&2
    exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$STATE/backups/$STAMP"
mkdir -p "$BACKUP/apps" "$BACKUP/system" "$TARGET" /home/root/.local/bin \
    /home/root/.config/literm /home/root/.config/rmssh "$QRR_DIR"

echo "$PRODUCT $VERSION — instalacja"
echo "Kopia poprzedniej wersji: $BACKUP"

for app in paperdesk literm paperweb paperrdp-login paperrdp paperrss shims; do
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
chmod 755 /home/root/.local/bin/rmssh-menu "$TARGET/paperrdp/paperrdp"

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
echo "Gotowe. Uruchom ponownie XOVI poleceniem /home/root/xovi/start."
echo "Po restarcie tabletu XOVI i PaperDesk uruchomia sie automatycznie."
echo "Konfiguracje polaczen i dane aplikacji zostaly zachowane."
