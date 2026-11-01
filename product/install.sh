#!/bin/sh

set -eu
umask 077

PRODUCT="PaperDesk"
TARGET="/home/root/xovi/exthome/appload"
QRR_DIR="/home/root/xovi/exthome/qt-resource-rebuilder"
EXTENSIONS="/home/root/xovi/extensions.d"
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

for required in paperdesk paperterminal paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download papersketch shims; do
    if [ ! -d "$PAYLOAD/apps/$required" ]; then
        echo "Incomplete package: missing payload/apps/$required" >&2
        exit 1
    fi
done

# Paper Terminal loads its own plugin from the app directory. Reject an
# incomplete native payload before staging or changing the tablet.
for required in native/qmldir native/libpaperterminal_native.so native/paperterminal-askpass; do
    if [ ! -s "$PAYLOAD/apps/paperterminal/$required" ]; then
        echo "Incomplete package: missing Paper Terminal $required" >&2
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

# Sketch runs native Qt code inside Xochitl. A different firmware may have an
# incompatible ABI even when QML-only apps happen to launch successfully.
OS_VERSION=$(sed -n 's/^IMG_VERSION=//p' /etc/os-release | tr -d '\"')
if [ -z "$OS_VERSION" ]; then
    OS_VERSION=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '\"')
fi
if { [ "$OS_VERSION" != "3.29.0.149" ] && [ "$OS_VERSION" != "3.29.0.153" ]; } || [ "$(uname -m)" != "armv7l" ]; then
    echo "PaperDesk 4 requires the supported reMarkable 2 OS 3.29.0.149 or 3.29.0.153 / ARMv7 native ABI." >&2
    echo "No files have been installed. Check firmware compatibility before continuing." >&2
    exit 1
fi
if [ ! -f "$PAYLOAD/apps/papersketch/native/papersketch-raster.so" ]; then
    echo "Incomplete package: missing Paper Sketch native material renderer." >&2
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
NATIVE_STAGE=""
NATIVE_REPLACING=0
NATIVE_WAS_PRESENT=0
LEGACY_TERMINAL_RETIRED=0
INSTALL_COMPLETE=0
cleanup_staging() {
    if [ -n "$REPLACING_APP" ] && [ ! -e "$TARGET/$REPLACING_APP" ] &&
       [ -e "$STAGING/previous-$REPLACING_APP" ]; then
        # A signal between the two renames must put the previous app back.
        mv "$STAGING/previous-$REPLACING_APP" "$TARGET/$REPLACING_APP" || return 1
    fi
    if [ -n "$NATIVE_STAGE" ]; then rm -f "$NATIVE_STAGE"; NATIVE_STAGE=""; fi
    if [ "$NATIVE_REPLACING" = 1 ] && [ "$INSTALL_COMPLETE" != 1 ]; then
        if [ "$NATIVE_WAS_PRESENT" = 1 ]; then
            # Restore by rename too: interruption cannot leave a truncated .so.
            NATIVE_STAGE=$(mktemp "$EXTENSIONS/.papersketch-restore.XXXXXX")
            if ! { cp -p "$BACKUP/system/papersketch-raster.so" "$NATIVE_STAGE" &&
                   mv "$NATIVE_STAGE" "$EXTENSIONS/papersketch-raster.so"; }; then
                echo "Could not restore the previous Sketch renderer; keep backup $BACKUP." >&2
            fi
        else
            rm -f "$EXTENSIONS/papersketch-raster.so"
        fi
    fi
    if [ -n "$NATIVE_STAGE" ]; then rm -f "$NATIVE_STAGE"; fi
    if [ "$INSTALL_COMPLETE" = 0 ] && [ "$LEGACY_TERMINAL_RETIRED" = 1 ] &&
       [ ! -e "$TARGET/literm" ] && [ -e "$STAGING/legacy-literm" ]; then
        mv "$STAGING/legacy-literm" "$TARGET/literm" || return 1
    fi
    rm -rf "$STAGING"
}
trap cleanup_staging EXIT
trap 'exit 1' HUP INT TERM
cp -R "$PAYLOAD/apps/." "$STAGING/"
NATIVE_STAGE=$(mktemp "$EXTENSIONS/.papersketch-raster.XXXXXX")
cp "$PAYLOAD/apps/papersketch/native/papersketch-raster.so" "$NATIVE_STAGE"
chmod 644 "$NATIVE_STAGE"

# Capture the original installation once. Later upgrades must not replace this baseline.
ORIGINAL="$STATE/original"
if [ ! -f "$STATE/original-recorded" ] && [ ! -f "$STATE/current-version" ]; then
    mkdir -p "$ORIGINAL/apps" "$ORIGINAL/system"
    for app in paperdesk paperterminal literm paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download papersketch paperpet shims; do
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

# Older PaperDesk installations already have original-recorded. Capture a
# pre-existing development Sketch app/module once when first upgrading to v4.
if [ ! -f "$STATE/sketch-original-recorded" ]; then
    mkdir -p "$ORIGINAL/apps" "$ORIGINAL/system"
    if [ -e "$TARGET/papersketch" ] && [ ! -e "$ORIGINAL/apps/papersketch" ]; then
        cp -R "$TARGET/papersketch" "$ORIGINAL/apps/papersketch"
    fi
    if [ -f "$EXTENSIONS/papersketch-raster.so" ]; then
        cp -p "$EXTENSIONS/papersketch-raster.so" "$ORIGINAL/system/papersketch-raster.so"
    fi
    touch "$STATE/sketch-original-recorded"
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
if [ -f "$EXTENSIONS/papersketch-raster.so" ]; then
    cp -p "$EXTENSIONS/papersketch-raster.so" "$BACKUP/system/papersketch-raster.so"
    NATIVE_WAS_PRESENT=1
fi

# Retire the experimental PaperPet app, retaining its previous installation
# in the version backup. User data and original snapshots remain untouched.
if [ -e "$TARGET/paperpet" ]; then
    cp -R "$TARGET/paperpet" "$BACKUP/apps/paperpet"
    rm -rf "$TARGET/paperpet"
fi
for app in paperdesk paperterminal paperweb paperweb-download paperrdp-login paperrdp paperrdp-profile paperrss papercare paperdots paperbooks paperbooks-download papersketch shims; do
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

# Retire only the old app frontend, after the independent terminal has been
# installed. Keep its global extension and configuration as user data.
if [ -e "$TARGET/literm" ]; then
    cp -R "$TARGET/literm" "$BACKUP/apps/literm"
    LEGACY_TERMINAL_RETIRED=1
    mv "$TARGET/literm" "$STAGING/legacy-literm"
fi

if [ -f /home/root/.local/bin/rmssh-menu ]; then
    cp /home/root/.local/bin/rmssh-menu "$BACKUP/system/rmssh-menu"
fi
cp "$PAYLOAD/system/rmssh-menu" /home/root/.local/bin/rmssh-menu
chmod 755 /home/root/.local/bin/rmssh-menu "$TARGET/paperrdp/paperrdp" \
    "$TARGET/paperrdp-profile/profile-manager" "$TARGET/paperbooks-download/book-download" \
    "$TARGET/paperweb-download/web-download" "$TARGET/paperterminal/native/paperterminal-askpass"

# Preserve legacy connection profiles and host aliases in this version backup
# while retaining their active user-owned copies.
if [ -f /home/root/.config/rmssh/profiles ]; then
    cp /home/root/.config/rmssh/profiles "$BACKUP/system/rmssh-profiles"
fi
if [ -f /home/root/.config/rmssh/hosts ]; then
    cp /home/root/.config/rmssh/hosts "$BACKUP/system/rmssh-hosts"
fi
# Existing connection profiles and host aliases remain user data.

for resource in paperdesk-appload-compat.qrr paperdesk-appload-window.qml paperdesk-appload.qml; do
    if [ -f "$QRR_DIR/$resource" ]; then
        cp "$QRR_DIR/$resource" "$BACKUP/system/$resource"
    fi
    cp "$PAYLOAD/system/$resource" "$QRR_DIR/$resource"
done

if [ -f /home/root/.config/literm/settings.ini ]; then
    cp /home/root/.config/literm/settings.ini "$BACKUP/system/literm-settings.ini"
fi

# The native terminal launches rmssh-menu directly. Remove only PaperDesk's
# old login-shell hook so unrelated local shells no longer enter the menu.
if [ -f /home/root/.profile ] && grep -q '^# RMSSH-BEGIN' /home/root/.profile; then
    cp /home/root/.profile "$BACKUP/system/profile"
    sed '/^# RMSSH-BEGIN/,/^# RMSSH-END/d' /home/root/.profile > /home/root/.profile.paperdesk-new
    mv /home/root/.profile.paperdesk-new /home/root/.profile
fi

# The extension is replaced by a same-filesystem rename only after the app
# payload and resources succeeded. The exit trap restores it on later failure.
NATIVE_REPLACING=1
mv "$NATIVE_STAGE" "$EXTENSIONS/papersketch-raster.so"
NATIVE_STAGE=""
mkdir -p "$STATE/sketch"
chmod 700 "$STATE/sketch"

printf '%s\n' "$VERSION" > "$STATE/current-version"
printf '%s\n' "$BACKUP" > "$STATE/last-backup"
INSTALL_COMPLETE=1

echo
echo "Done. Restart XOVI with /home/root/xovi/start."
echo "For recovery safety, PaperDesk does not start XOVI automatically after reboot."
echo "Start it deliberately with /home/root/xovi/start or xovi-tripletap."
echo "Connection profiles and app data have been preserved."
