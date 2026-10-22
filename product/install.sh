#!/bin/sh

set -eu
umask 077

PRODUCT="PaperDesk"
TARGET="/home/root/xovi/exthome/appload"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"
STATE="/home/root/.local/share/paperdesk"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD="$SCRIPT_DIR/payload"
VERSION=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")

printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$' || {
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

for required in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download shims; do
    if [ ! -d "$PAYLOAD/apps/$required" ]; then
        echo "Incomplete package: missing payload/apps/$required" >&2
        exit 1
    fi
done

for required in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml paperdesk-update-agent paperdesk-update.service paperdesk-update.path paperdesk-release-public.pem; do
    if [ ! -f "$PAYLOAD/system/$required" ]; then
        echo "Incomplete package: missing payload/system/$required" >&2
        exit 1
    fi
done

if [ ! -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]; then
    echo "The qt-resource-rebuilder extension required by the AppLoad patch is missing." >&2
    exit 1
fi

# Manual installs deserve the same payload-integrity check as Care. Verify
# before touching services, backups or installed files.
(cd "$SCRIPT_DIR" && sha256sum -c SHA256SUMS >/dev/null) || {
    echo "The PaperDesk package is damaged. Installation has not started." >&2
    exit 1
}
exec 8>/run/paperdesk-install.lock
flock -n 8 || { echo "Another PaperDesk installation is running." >&2; exit 1; }

# Stage every app first. A full filesystem or interrupted copy must leave the
# currently installed apps intact. Renames below remain on the same filesystem.
STAGING=$(mktemp -d "$TARGET/.paperdesk-install.XXXXXX")
REPLACING_APP=""
cleanup_staging() {
    if [ -n "$REPLACING_APP" ] && [ ! -e "$TARGET/$REPLACING_APP" ] &&
       [ -e "$STAGING/previous-$REPLACING_APP" ]; then
        # A signal between the two renames must put the previous app back.
        mv "$STAGING/previous-$REPLACING_APP" "$TARGET/$REPLACING_APP" || return 1
    fi
    rm -rf "$STAGING"
}
trap cleanup_staging EXIT
trap 'exit 1' HUP INT TERM
cp -R "$PAYLOAD/apps/." "$STAGING/"

# Capture the original installation once. Later upgrades must not replace this baseline.
ORIGINAL="$STATE/original"
if [ ! -f "$STATE/original-recorded" ] && [ ! -f "$STATE/current-version" ]; then
    mkdir -p "$ORIGINAL/apps" "$ORIGINAL/system"
    for app in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download paperpet shims; do
        if [ -e "$TARGET/$app" ]; then
            cp -R "$TARGET/$app" "$ORIGINAL/apps/$app"
        fi
    done
    for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
        if [ -f "$QRR_DIR/$resource" ]; then
            cp "$QRR_DIR/$resource" "$ORIGINAL/system/$resource"
        fi
    done
    for service in paperdesk-update.service paperdesk-update.path; do
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

cp "$PAYLOAD/system/paperdesk-update.service" /etc/systemd/system/paperdesk-update.service
cp "$PAYLOAD/system/paperdesk-update.path" /etc/systemd/system/paperdesk-update.path
mkdir -p /home/root/.local/lib/paperdesk
cp "$PAYLOAD/system/paperdesk-update-agent" /home/root/.local/lib/paperdesk/paperdesk-update-agent
cp "$PAYLOAD/system/paperdesk-release-public.pem" /home/root/.local/lib/paperdesk/release-public.pem
cp "$SCRIPT_DIR/uninstall.sh" /home/root/.local/lib/paperdesk/paperdesk-uninstall
chmod 755 /home/root/.local/lib/paperdesk/paperdesk-update-agent \
    /home/root/.local/lib/paperdesk/paperdesk-uninstall
chmod 644 /home/root/.local/lib/paperdesk/release-public.pem
# Retire the legacy private download service. Document downloads now use the
# bounded AppLoad worker below and My files import, not a background daemon.
systemctl disable --now paperdesk-download.path 2>/dev/null || true
rm -f /etc/systemd/system/paperdesk-download.path \
    /etc/systemd/system/paperdesk-download.service \
    /home/root/.local/lib/paperdesk/paperdesk-download-agent
systemctl daemon-reload
systemctl enable --now paperdesk-update.path

# PaperDesk 1.0.5 through 1.1.8 installed this exact boot service. On an rM2,
# a broken XOVI extension can then repeat on every boot while hardware recovery
# requires a pogo-pin adapter. Remove only PaperDesk's known legacy unit; never
# touch a differently described service belonging to the user.
if [ -f "$STATE/current-version" ] && [ -f /etc/systemd/system/xovi-autostart.service ] &&
   grep -Fxq 'Description=Start Xovi extensions after the reMarkable interface' /etc/systemd/system/xovi-autostart.service &&
   grep -Fxq 'ExecStart=/home/root/xovi/start' /etc/systemd/system/xovi-autostart.service; then
    systemctl disable xovi-autostart.service 2>/dev/null || true
    # Updaters through 1.1.8 use this disabled unit once, immediately after
    # install, to reload XOVI. Delay deleting its file so that safe one-shot
    # handoff can finish; disabling above already removes boot persistence.
    systemd-run --unit="paperdesk-remove-legacy-autostart-$$" --collect \
        --on-active=30s /bin/rm -f /etc/systemd/system/xovi-autostart.service >/dev/null
    touch "$STATE/legacy-autostart-removed"
fi

STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$STATE/backups"
BACKUP=$(mktemp -d "$STATE/backups/$STAMP-XXXXXX")
mkdir -p "$BACKUP/apps" "$BACKUP/system" "$TARGET" /home/root/.local/bin \
    /home/root/.config/literm /home/root/.config/rmssh "$QRR_DIR"

echo "$PRODUCT $VERSION — installation"
echo "Previous-version backup: $BACKUP"

# Retire the experimental PaperPet app, retaining its previous installation
# in the version backup. User data and original snapshots remain untouched.
if [ -e "$TARGET/paperpet" ]; then
    cp -R "$TARGET/paperpet" "$BACKUP/apps/paperpet"
    rm -rf "$TARGET/paperpet"
fi
for app in paperdesk literm paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download shims; do
    REPLACING_APP=$app
    if [ -e "$TARGET/$app" ]; then
        cp -R "$TARGET/$app" "$BACKUP/apps/$app"
        mv "$TARGET/$app" "$STAGING/previous-$app"
    fi
    if ! mv "$STAGING/$app" "$TARGET/$app"; then
        if [ -e "$STAGING/previous-$app" ]; then
            mv "$STAGING/previous-$app" "$TARGET/$app"
        fi
        echo "Could not replace $app. Backups are in $BACKUP." >&2
        exit 1
    fi
    REPLACING_APP=""
done

if [ -f /home/root/.local/bin/rmssh-menu ]; then
    cp /home/root/.local/bin/rmssh-menu "$BACKUP/system/rmssh-menu"
fi
cp "$PAYLOAD/system/rmssh-menu" /home/root/.local/bin/rmssh-menu
chmod 755 /home/root/.local/bin/rmssh-menu "$TARGET/paperrdp/paperrdp" \
    "$TARGET/paperrdp-profile/profile-manager" "$TARGET/paperbooks-download/book-download" \
    "$TARGET/paperweb-download/web-download"

# PaperDesk 2 keeps Terminal deliberately stateless. Preserve the retired
# profile and alias files in this version backup, then remove their active
# copies so upgrades cannot bring the old UI model back.
if [ -f /home/root/.config/rmssh/profiles ]; then
    cp /home/root/.config/rmssh/profiles "$BACKUP/system/rmssh-profiles"
fi
if [ -f /home/root/.config/rmssh/hosts ]; then
    cp /home/root/.config/rmssh/hosts "$BACKUP/system/rmssh-hosts"
fi
rm -f /home/root/.config/rmssh/profiles /home/root/.config/rmssh/hosts

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
echo "For recovery safety, PaperDesk does not start XOVI automatically after reboot."
echo "Start it deliberately with /home/root/xovi/start or xovi-tripletap."
echo "Connection profiles and app data have been preserved."
