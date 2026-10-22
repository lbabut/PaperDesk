#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKDIR=${PAPERDESK_WORKDIR:-$ROOT/work}
HOST=${PAPERDESK_TABLET_HOST:-10.11.99.1}
KEY=${PAPERDESK_TABLET_KEY:-$WORKDIR/keys/remarkable2_ed25519}
KNOWN_HOSTS=${PAPERDESK_KNOWN_HOSTS:-$WORKDIR/keys/known_hosts}
REMOTE=root@$HOST
SSH=(ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=7 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$REMOTE")
SCP=(scp -i "$KEY" -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes)
RUN_STARTED=$(date +%s)
ARTIFACT_DIR=${PAPERDESK_ARTIFACT_DIR:-$WORKDIR/tests/tablet-e2e}
TOOLCHAIN="$WORKDIR/arm-toolchain/root"
TARGET=${PAPERDESK_E2E_TARGET:-all}
JOURNEY_LOOPS=${PAPERDESK_E2E_LOOPS:-2}
CAPTURE_SCREEN=${PAPERDESK_E2E_CAPTURE:-0}
if [[ "$TARGET" == "dots" && -z "${PAPERDESK_E2E_CAPTURE+x}" ]]; then
    CAPTURE_SCREEN=0
fi
RDP_SCALE_75_X=439
RDP_COLOR_256_X=796
RDP_PERFORMANCE_Y=1286
RDP_CONNECT_X=702
RDP_CONNECT_Y=1416
RDP_PROFILE_NEW_X=351
RDP_PROFILE_EDIT_X=702
RDP_PROFILE_DELETE_X=1053
RDP_PROFILE_ACTION_Y=527
RDP_PROFILE_CANCEL_X=439
RDP_PROFILE_SAVE_X=965
RDP_DELETE_CONFIRM_X=911
RDP_DELETE_CONFIRM_Y=1068
RDP_PROFILE_FIRST_X=702
RDP_PROFILE_FIRST_Y=390
BASE_PID=""
TABLET_SETUP_STARTED=0
declare -A LOG_EXPECTED=()

remote() { "${SSH[@]}" "$@"; }

cleanup() {
    [[ "$TABLET_SETUP_STARTED" == "1" ]] || return 0
    set +e
    remote 'set +e
RESTORE_FAILED=0
if test -f /tmp/paperdesk-e2e-physical-dev; then
    systemctl stop xochitl || RESTORE_FAILED=1
    PHYSICAL=$(cat /tmp/paperdesk-e2e-physical-dev)
    rm -f /dev/input/event2
    mknod /dev/input/event2 c ${PHYSICAL%:*} ${PHYSICAL#*:} || RESTORE_FAILED=1
    chown root:input /dev/input/event2
    chmod 660 /dev/input/event2
fi
if test -f /tmp/paperdesk-e2e-xochitl.conf; then
    cp -p /tmp/paperdesk-e2e-xochitl.conf /home/root/.config/remarkable/xochitl.conf || RESTORE_FAILED=1
fi
if test -d /tmp/paperdesk-e2e-rdp-profile-backup; then
    rm -f /home/root/.config/paperrdp/profile /home/root/.config/paperrdp/profiles
    if test -f /tmp/paperdesk-e2e-rdp-profile-backup/profile; then
        cp /tmp/paperdesk-e2e-rdp-profile-backup/profile /home/root/.config/paperrdp/profile
    fi
    if test -f /tmp/paperdesk-e2e-rdp-profile-backup/profiles; then
        cp /tmp/paperdesk-e2e-rdp-profile-backup/profiles /home/root/.config/paperrdp/profiles
    fi
    rm -f /tmp/paperdesk-e2e-rdp-profile-backup/profile /tmp/paperdesk-e2e-rdp-profile-backup/profiles
    rmdir /tmp/paperdesk-e2e-rdp-profile-backup 2>/dev/null || true
fi
if test -p /tmp/paperdesk-touch.fifo && pidof paperdesk-rm-touchd >/dev/null; then
    timeout 2 sh -c '\''printf "quit\n" >/tmp/paperdesk-touch.fifo'\'' || true
fi
sleep 1
for helper_pid in $(pidof paperdesk-rm-touchd || true); do
    kill -9 "$helper_pid" 2>/dev/null || true
done
rm -f /tmp/paperdesk-touch.fifo /tmp/paperdesk-touch.ready
systemctl reset-failed xochitl
systemctl start xochitl || RESTORE_FAILED=1
if test -f /tmp/paperdesk-e2e-masked-failure; then
    systemctl unmask --runtime remarkable-fail.service
    rm -f /tmp/paperdesk-e2e-masked-failure
fi
sleep 8
systemctl is-active --quiet xochitl || RESTORE_FAILED=1
if test "$RESTORE_FAILED" = 0; then
    rm -f /tmp/paperdesk-e2e-physical-dev /tmp/paperdesk-e2e-xochitl.conf
else
    echo "Tablet cleanup failed; recovery backups retained in /tmp/paperdesk-e2e-*" >&2
fi
exit "$RESTORE_FAILED"
' >/dev/null
}
trap 'result=$?; cleanup || result=1; exit "$result"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_log() {
    local pattern=$1
    local attempts=${2:-30}
    local expected=$(( ${LOG_EXPECTED["$pattern"]:-0} + 1 ))
    local n count
    LOG_EXPECTED["$pattern"]=$expected
    for ((n = 0; n < attempts; ++n)); do
        count=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | grep -Fc "$pattern" || true)
        if (( count >= expected )); then
            return 0
        fi
        sleep 1
    done
    echo "Timed out waiting for tablet log: $pattern" >&2
    remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | tail -n 160 >&2
    return 1
}

assert_tablet_healthy() {
    local label=$1 pid
    remote 'systemctl is-active --quiet xochitl'
    pid=$(remote 'pidof xochitl' | awk '{print $1}')
    if [[ -n "$BASE_PID" && "$pid" != "$BASE_PID" ]]; then
        echo "xochitl restarted during $label: expected $BASE_PID, got $pid" >&2
        remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | tail -n 180 >&2
        return 1
    fi
    if remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        grep -Eq 'Watchdog timeout|Main process exited|Failed with result'; then
        echo "xochitl failure detected during $label" >&2
        remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | tail -n 180 >&2
        return 1
    fi
    remote 'test -e /tmp/paperdesk-touch.ready'
}

tap() {
    [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] &&
        (( $1 < 1404 && $2 < 1872 )) || { echo "Touch target is outside the tablet." >&2; return 1; }
    remote "printf 'tap %s %s\\n' '$1' '$2' >/tmp/paperdesk-touch.fifo"
}

tap_until_log() {
    local x=$1 y=$2 pattern=$3 retries=${4:-3}
    local expected=$(( ${LOG_EXPECTED["$pattern"]:-0} + 1 ))
    local retry poll count
    LOG_EXPECTED["$pattern"]=$expected
    for ((retry = 0; retry < retries; ++retry)); do
        tap "$x" "$y"
        for ((poll = 0; poll < 4; ++poll)); do
            count=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
                grep -Fc "$pattern" || true)
            if (( count >= expected )); then
                return 0
            fi
            sleep 1
        done
    done
    echo "Timed out after physical tablet taps waiting for log: $pattern" >&2
    remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | tail -n 160 >&2
    return 1
}

hold() {
    remote "printf 'hold %s %s %s\\n' '$1' '$2' '$3' >/tmp/paperdesk-touch.fifo"
}

swipe() {
    remote "printf 'swipe %s %s %s %s %s\\n' '$1' '$2' '$3' '$4' '$5' >/tmp/paperdesk-touch.fifo"
}

pinch() {
    remote "printf 'pinch %s %s %s %s %s %s %s %s %s\\n' '$1' '$2' '$3' '$4' '$5' '$6' '$7' '$8' '$9' >/tmp/paperdesk-touch.fifo"
}

select_rdp_performance_profile() {
    rdp_tap_action rdpProfileNewButton
    wait_for_log 'PaperDesk RDP profile add' 8
    rdp_tap_action rdpScaleButton_75
    wait_for_log 'PaperDesk RDP scale 75' 8
    rdp_tap_action rdpColorDepthButton_8
    wait_for_log 'PaperDesk RDP colors 8' 8
    rdp_tap_action rdpProfileCancelButton
    wait_for_log 'PaperDesk RDP profile edit cancelled' 8
}

rdp_tap_action() {
    local name=$1 coordinates target_x target_y attempt
    for attempt in 1 2 3 4 5 6; do
    # Wait for a post-layout trace instead of trusting stale fixed coordinates.
    sleep 1
    coordinates=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        awk -v name="$name" '{ for (i=1; i<=NF-3; ++i) if ($i=="target" && $(i+1)==name) print $(i+2), $(i+3) }' | tail -n1)
    read -r target_x target_y <<< "$coordinates"
    [[ "$target_x" =~ ^[0-9]+$ && "$target_y" =~ ^-?[0-9]+$ ]]
    if (( target_y >= 135 && target_y < 1820 )) ||
       [[ "$name" == rdpProfileSaveButton || "$name" == rdpProfileCancelButton || "$name" == rdpCloseButton || "$name" == rdpKeyboardButton ]]; then
        tap "$target_x" "$target_y"
        return
    fi
    if (( target_y < 135 )); then swipe 800 500 800 1400 650
    else swipe 800 1450 800 450 650; fi
    done
    echo "Could not reveal RDP $name by physical scrolling" >&2
    return 1
}

ssh_tap_action() {
    local name=$1 coordinates target_x target_y
    sleep 1
    coordinates=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        awk -v name="$name" '/PaperDesk SSH target/ { for (i=1; i<=NF-3; ++i) if ($i=="target" && $(i+1)==name) print $(i+2), $(i+3) }' | tail -n1)
    read -r target_x target_y <<< "$coordinates"
    [[ "$target_x" =~ ^[0-9]+$ && "$target_y" =~ ^[0-9]+$ ]]
    tap "$target_x" "$target_y"
}

rdp_engine_tap_action() {
    local name=$1 coordinates target_x target_y
    sleep 1
    coordinates=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        awk -v name="$name" '{ for (i=1;i<=NF-3;++i) if ($i=="target" && $(i+1)==name) print $(i+2),$(i+3) }' | tail -n1)
    read -r target_x target_y <<< "$coordinates"
    tap "$target_x" "$target_y"
}

books_observe() {
    remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        python3 "$ROOT/tests/tablet_books_trace.py" "$1" "$2"
}
books_tap_action() {
    local coordinates target_x target_y
    sleep 1
    coordinates=$(books_observe target "$1")
    read -r target_x target_y <<< "$coordinates"
    tap "$target_x" "$target_y"
    sleep 2
}

care_tap_geometry() {
    local name=$1 coordinates target_x target_y target_width target_height attempt
    for attempt in 1 2 3 4 5 6; do
        sleep 2
        coordinates=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk -v name="$name" '{ for (i=1; i<=NF-5; ++i) if ($i==name && $(i+1)=="geometry") print $(i+2), $(i+3), $(i+4), $(i+5) }' | tail -n1)
        read -r target_x target_y target_width target_height <<< "$coordinates"
        [[ "$target_x" =~ ^[0-9]+$ && "$target_y" =~ ^-?[0-9]+$ && "$target_width" =~ ^[0-9]+$ && "$target_height" =~ ^[0-9]+$ ]]
        if (( target_y >= 130 && target_y + target_height < 1840 )); then
            tap "$((target_x + target_width / 2))" "$((target_y + target_height / 2))"
            return
        fi
        if (( target_y < 130 )); then swipe 700 500 700 1500 700
        else swipe 700 1500 700 500 700; fi
    done
    echo "Could not reveal Care $name through physical scrolling." >&2
    return 1
}

dots_tap_action() {
    local name=$1 coordinates target_x target_y
    coordinates=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
        awk -v name="$name" '{ for (i=1; i<=NF-3; ++i) if ($i=="target" && $(i+1)==name) print $(i+2), $(i+3) }' | tail -n1)
    read -r target_x target_y <<< "$coordinates"
    [[ "$target_x" =~ ^[0-9]+$ && "$target_y" =~ ^[0-9]+$ ]]
    tap "$target_x" "$target_y"
    wait_for_log "PaperDots action $name" 10
    sleep 2
}

dots_choose_player() {
    dots_tap_action "dotsPlayer${1}PickerButton"
    dots_tap_action "dotsPlayer${1}Picker${2}Option"
}

dots_mark_computer_count() {
    LOG_EXPECTED['PaperDots computer move']=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | grep -Fc 'PaperDots computer move' || true)
}

capture_screen() {
    local output=$1
    local pid address skip window attempt
    if [[ "$CAPTURE_SCREEN" != "1" ]]; then
        return 0
    fi
    window=$((1404 * 1872 * 4))
    for attempt in 1 2 3; do
        pid=$(remote "pidof xochitl" | awk '{print $1}')
        address=$(remote "grep -C1 /dev/fb0 /proc/$pid/maps | tail -n1 | sed 's/-.*//'")
        skip=$((16#$address + 7))
        if remote "{ dd bs=1 skip=$skip count=0 && dd bs=$window count=1; } < /proc/$pid/mem 2>/dev/null" |
            ffmpeg -y -loglevel error -f rawvideo -pixel_format bgra \
                -video_size 1404x1872 -i - -frames:v 1 "$output"; then
            # Reading xochitl's mapped framebuffer briefly stalls its input
            # loop on current firmware. Let it resume before the next injected
            # hardware event, otherwise that first event can be dropped.
            sleep 2
            return 0
        fi
        sleep 1
    done
    echo "WARN: framebuffer capture unavailable for $output; continuing interaction checks" >&2
    rm -f "$output"
    return 0
}

mkdir -p "$ARTIFACT_DIR"
exec 9>"$ARTIFACT_DIR/input-test.lock"
flock -n 9 || { echo "Another tablet test owns the input device." >&2; exit 1; }
# A failed local build or unavailable tablet must never run device cleanup.
remote 'test ! -e /tmp/paperdesk-e2e-xochitl.conf && ! pidof paperdesk-rm-touchd >/dev/null'
LD_LIBRARY_PATH="$TOOLCHAIN/usr/lib/x86_64-linux-gnu" \
    "$TOOLCHAIN/usr/bin/arm-linux-gnueabihf-gcc-12" \
    --sysroot="$TOOLCHAIN" -O2 -Wall -Wextra \
    "$ROOT/tests/rm-touchd.c" -o "$WORKDIR/tests/rm-touchd"
"${SCP[@]}" "$WORKDIR/tests/rm-touchd" "$REMOTE:/tmp/paperdesk-rm-touchd"

TABLET_SETUP_STARTED=1
remote 'set -eu
umask 077
chmod 700 /tmp/paperdesk-rm-touchd
PHYSICAL=$(cat /sys/class/input/event2/dev)
echo "$PHYSICAL" >/tmp/paperdesk-e2e-physical-dev
case "$(systemctl is-enabled remarkable-fail.service 2>/dev/null || true)" in
    masked|masked-runtime) ;;
    *) touch /tmp/paperdesk-e2e-masked-failure; systemctl mask --runtime remarkable-fail.service ;;
esac
systemctl stop xochitl
cp -p /home/root/.config/remarkable/xochitl.conf /tmp/paperdesk-e2e-xochitl.conf
awk '\''
BEGIN { in_e2e=0 }
/^\[PaperDeskE2E\]$/ { in_e2e=1; next }
/^\[/ { in_e2e=0 }
!in_e2e { print }
'\'' /home/root/.config/remarkable/xochitl.conf > /tmp/paperdesk-e2e-base.conf
mv /tmp/paperdesk-e2e-base.conf /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nautostart=true\napplicationId=paperdesk\nscenarioVersion=20260927\ntraceTouches=true\nwebFixture=true\nwebBlockedFileFixture=false\nwebTraceGestures=true\nrssLongArticle=true\nrssAutoFullText=false\nrssStressParser=true\nrssTraceScroll=true\nrdpProfileCrud=false\n" >>/home/root/.config/remarkable/xochitl.conf
for helper_pid in $(pidof paperdesk-rm-touchd || true); do
    kill -9 "$helper_pid" 2>/dev/null || true
done
rm -f /tmp/paperdesk-touch.fifo /tmp/paperdesk-touch.ready
nohup /tmp/paperdesk-rm-touchd >/tmp/paperdesk-touch.log 2>&1 &
for n in $(seq 1 40); do test -e /tmp/paperdesk-touch.ready && break; sleep 0.1; done
test -e /tmp/paperdesk-touch.ready
VIRTUAL=""
for device in /sys/class/input/event*; do
    case "$(readlink -f "$device/device")" in
        /sys/devices/virtual/input/*) VIRTUAL=$(cat "$device/dev");;
    esac
done
test -n "$VIRTUAL"
rm -f /dev/input/event2
mknod /dev/input/event2 c ${VIRTUAL%:*} ${VIRTUAL#*:}
chown root:input /dev/input/event2
chmod 660 /dev/input/event2
systemctl reset-failed xochitl
systemctl start xochitl
'

AUTOSTART_APPLICATION=paperdesk
if [[ "$TARGET" == "showcase" ]]; then
    remote 'sed -i '\''s/^webFixture=true$/webFixture=false/; s/^rssLongArticle=true$/rssLongArticle=false/; s/^rssStressParser=true$/rssStressParser=false/; s/^rssTraceScroll=true$/rssTraceScroll=false/'\'' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web" || "$TARGET" == "journey" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedMobileMode=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-file-blocked" ]]; then
    remote 'printf "\n[PaperDeskE2E]\nwebBlockedFileFixture=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-wp" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\n[PaperDeskE2E]\nwebLiveWp=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-dynamic" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\n[PaperDeskE2E]\nwebLiveNineGag=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-linked-images" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\n[PaperDeskE2E]\nwebLiveLinkedImages=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-dense-cards" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\n[PaperDeskE2E]\nwebLiveDenseCards=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-article-journey" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\n[PaperDeskE2E]\nwebLiveArticleJourney=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-script-filter" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=true\n[PaperDeskE2E]\nwebLiveScriptFilter=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "web-live-polish-text" ]]; then
    remote 'printf "\n[PaperWeb]\nsavedShowPictures=false\nsavedMobileMode=true\n[PaperDeskE2E]\nwebLivePolishText=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "rss-auto-full" ]]; then
    remote 'sed -i '\''s/^rssLongArticle=true$/rssLongArticle=false/; s/^rssStressParser=true$/rssStressParser=false/'\'' /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nrssAutoFullText=true\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "rss-live-full" ]]; then
    remote 'sed -i '\''s/^rssLongArticle=true$/rssLongArticle=false/; s/^rssStressParser=true$/rssStressParser=false/'\'' /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nrssAutoFullText=true\nrssAutoFullTextUrl=https://www.sciencedaily.com/releases/2026/09/260929053536.htm\nrssAutoFullTextTitle=Sharks can hear nearly 250 feet away and pinpoint the source\n" >>/home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "care" ]]; then
    AUTOSTART_APPLICATION=papercare
    remote 'sed -i '\''s/^applicationId=.*/applicationId=papercare/; s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 28'
elif [[ "$TARGET" == "dots" || "$TARGET" == "dots-cache" || "$TARGET" == "dots-cache-large" ]]; then
    AUTOSTART_APPLICATION=paperdots
    if [[ "$TARGET" == "dots-cache-large" ]]; then
        # Bare JSON commas would be parsed as a QStringList, not a string.
        node "$ROOT/tests/dots-large-fixture.cjs" |
            python3 -c 'import json,sys; print("\n[PaperDeskDots]\ngame="+json.dumps(sys.stdin.read())+"\ncheckpoint=\n")' |
            remote 'cat >>/home/root/.config/remarkable/xochitl.conf'
    fi
    remote 'sed -i '\''s/^applicationId=.*/applicationId=paperdots/; s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\ndotsCapture=true\n" >> /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "ssh-sessions" ]]; then
    AUTOSTART_APPLICATION=literm
    remote 'sed -i '\''s/^applicationId=.*/applicationId=literm/; s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nsshSessionCrud=true\n[PaperDeskSSH]\nsessionsJson=[]\n" >> /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "books-live" ]]; then
    AUTOSTART_APPLICATION=paperbooks
    remote 'sed -i '\''s/^applicationId=.*/applicationId=paperbooks/; s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nbooksTrace=true\nbooksQuery=\n[PaperDeskBooks]\npreferredLanguages=pl\npreferredSources=gutenberg\n" >> /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
elif [[ "$TARGET" == "rdp-landscape" ]]; then
    remote 'set -eu
test ! -d /tmp/paperdesk-e2e-rdp-profile-backup
mkdir -p /tmp/paperdesk-e2e-rdp-profile-backup
chmod 0700 /tmp/paperdesk-e2e-rdp-profile-backup
for file in profile profiles; do
    if test -f /home/root/.config/paperrdp/$file; then
        cp -p /home/root/.config/paperrdp/$file /tmp/paperdesk-e2e-rdp-profile-backup/$file
    fi
done'
elif [[ "$TARGET" == "rdp" ]]; then
    remote 'set -eu
mkdir -p /tmp/paperdesk-e2e-rdp-profile-backup /home/root/.config/paperrdp
chmod 0700 /tmp/paperdesk-e2e-rdp-profile-backup /home/root/.config/paperrdp
if test -f /home/root/.config/paperrdp/profile; then
    cp /home/root/.config/paperrdp/profile /tmp/paperdesk-e2e-rdp-profile-backup/profile
fi
if test -f /home/root/.config/paperrdp/profiles; then
    cp /home/root/.config/paperrdp/profiles /tmp/paperdesk-e2e-rdp-profile-backup/profiles
fi
printf "v1\t7264702d6532652d6f6e65\t70617065726465736b2d74657374\t\t1\t\t75\t8\nv1\t7264702d6532652d74776f\t70617065726465736b2d74657374\t\t1\t\t100\t16\n" > /home/root/.config/paperrdp/profiles
chmod 0600 /home/root/.config/paperrdp/profiles
sed -i '''s/^rdpProfileCrud=false$/rdpProfileCrud=true/''' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 8'
fi

wait_for_log "PaperDesk E2E autostart $AUTOSTART_APPLICATION" 40
wait_for_log 'Application starting with' 10
BASE_PID=$(remote 'pidof xochitl' | awk '{print $1}')
assert_tablet_healthy 'startup'
capture_screen "$ARTIFACT_DIR/paperdesk-autostart.png"
sleep 2

case "$TARGET" in
    books-live)
        wait_for_log 'PaperBooks state' 20
        if ! remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            grep -E 'QSQLITE.*available drivers:|QSQLITE driver not loaded' >/dev/null; then
            echo 'Books live test requires settings fallback; SQLite library backup is not implemented.' >&2
            exit 1
        fi
        saved_ids=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            sed -n 's/.*target booksOpen_\([^ ]*\) .*/\1/p' | sort -u | paste -sd, -)
        shelf_before=$(books_observe state shelf)
        books_tap_action booksSearchTab
        books_tap_action booksSearchButton
        for attempt in $(seq 1 45); do
            results=$(books_observe state results)
            searching=$(books_observe state searching)
            if (( results >= 10 )) && [[ "$searching" == False ]]; then break; fi
            sleep 2
        done
        (( results >= 10 )) && [[ "$searching" == False ]]
        swipe 700 1450 700 650 650
        sleep 3
        before=$(books_observe state searchScroll)
        (( before > 300 ))
        target=$(books_observe unsaved-result "$saved_ids")
        books_tap_action "$target"
        for attempt in $(seq 1 45); do
            status=$(books_observe state status)
            [[ "$status" == 'Saved offline'* ]] && break
            sleep 2
        done
        [[ "$status" == 'Saved offline'* ]]
        after=$(books_observe state searchScroll)
        shelf_after=$(books_observe state shelf)
        (( shelf_after == shelf_before + 1 && after >= before - 3 && after <= before + 3 ))
        books_tap_action "$target"
        [[ "$(books_observe state view)" == reader ]]
        before_reader=$(books_observe state scroll)
        swipe 700 1400 700 650 500
        sleep 3
        after_reader=$(books_observe state scroll)
        (( after_reader > before_reader + 200 ))
        assert_tablet_healthy 'Books live download and scrolling'
        echo "PASS: Books real download kept list position $before -> $after px; physical reader swipe advanced text"
        ;;
    dots-cache|dots-cache-large)
        wait_for_log 'PaperDots ready' 60
        moves=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDots ready/ { for(i=1;i<NF;++i) if($i=="ready") count=$(i+2) } END { print count+0 }')
        if [[ "$TARGET" == "dots-cache-large" ]]; then (( moves == 431 )); fi
        sleep 2
        dots_tap_action dotsCloseButton
        remote 'sed -i '\''s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl'
        sleep 8
        BASE_PID=$(remote 'pidof xochitl' | awk '{print $1}')
        wait_for_log "PaperDots checkpoint restored $moves timeMs" 20
        milliseconds=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDots checkpoint restored/ { for(i=1;i<NF;++i) if($i=="timeMs") value=$(i+1) } END { print value+0 }')
        (( milliseconds < 2000 ))
        assert_tablet_healthy 'Dots checkpoint cold load'
        echo "PASS: Dots $moves moves restored from validated checkpoint in $milliseconds ms"
        ;;
    ssh-sessions)
        tap 155 158
        wait_for_log 'PaperDesk SSH state list' 10
        ssh_tap_action sshSessionNew
        wait_for_log 'PaperDesk SSH state add' 8
        ssh_tap_action sshSessionHostInput
        sleep 2
        viewport=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDesk SSH state add/ { for (i=1;i<NF;++i) if ($i=="state") print $(i+4) }' | tail -n1)
        [[ "$viewport" =~ ^[0-9]+$ ]] && (( viewport > 0 ))
        ssh_tap_action sshSessionSave
        wait_for_log 'PaperDesk SSH state list 1' 8
        ssh_tap_action sshSessionEdit
        wait_for_log 'PaperDesk SSH state edit' 8
        ssh_tap_action sshSessionSave
        sleep 2
        ssh_tap_action sshSessionOpen
        wait_for_log 'PaperDesk SSH opening saved session' 8
        sleep 3
        remote 'grep -q "^closed " /home/root/.config/rmssh/state'
        tap 155 158
        wait_for_log 'PaperDesk SSH state list 1' 8
        ssh_tap_action sshSessionDelete
        ssh_tap_action sshSessionDeleteCancel
        ssh_tap_action sshSessionDelete
        ssh_tap_action sshSessionDeleteConfirm
        wait_for_log 'PaperDesk SSH state list 0' 8
        ssh_tap_action sshSessionsBack
        tap 1305 56
        wait_for_log 'PaperDesk Terminal action close' 8
        assert_tablet_healthy 'SSH saved sessions and native keyboard'
        echo 'PASS: physical taps covered SSH New, native keyboard, Save, Edit, Open, delete cancellation and confirmation'
        ;;
    dots)
        wait_for_log 'PaperDots ready' 60
        restored_moves=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDots restoring/ { for(i=1;i<NF;i++) if($i=="restoring") count=$(i+1) } END { print count+0 }')
        if (( restored_moves > 64 )); then
            dots_tap_action dotsUndoButton
            wait_for_log 'PaperDots undo' 10
            wait_for_log 'PaperDots ready' 60
            assert_tablet_healthy 'Dots large saved-game restore and Undo'
        fi
        dots_tap_action dotsNewButton
        dots_tap_action dotsDialogCancelButton
        dots_tap_action dotsNewButton
        dots_tap_action dotsSmallBoardButton
        dots_choose_player 1 Human
        dots_choose_player 2 Computer
        dots_tap_action dotsRelaxedButton
        dots_tap_action dotsStartButton
        wait_for_log 'PaperDots new game 15 19 relaxed human computer' 10
        tap 702 1000
        wait_for_log 'PaperDots human move' 10
        wait_for_log 'PaperDots computer move' 20
        assert_tablet_healthy 'Dots AI reply'
        dots_tap_action dotsUndoButton
        wait_for_log 'PaperDots undo 0' 10

        # Hot-seat: both physical board taps must be accepted, with no AI turn.
        dots_tap_action dotsNewButton
        dots_tap_action dotsExtraBoardButton
        dots_choose_player 2 Human
        dots_tap_action dotsStartButton
        wait_for_log 'PaperDots new game 29 33 relaxed human human' 10
        tap 702 1000
        wait_for_log 'PaperDots human move' 10
        tap 800 1100
        wait_for_log 'PaperDots human move' 10
        dots_tap_action dotsUndoButton
        wait_for_log 'PaperDots undo 1' 10
        assert_tablet_healthy 'Dots two human players'

        # Computer first: opening reply and the second player's real tap.
        dots_tap_action dotsNewButton
        dots_tap_action dotsLargeBoardButton
        dots_choose_player 1 Computer
        dots_tap_action dotsTacticalButton
        dots_tap_action dotsStartButton
        wait_for_log 'PaperDots new game 19 23 tactical computer human' 10
        wait_for_log 'PaperDots computer move' 20
        tap 800 1100
        wait_for_log 'PaperDots human move' 10
        dots_tap_action dotsPauseButton
        wait_for_log 'PaperDots pause true' 10
        assert_tablet_healthy 'Dots computer opening'

        # Both colours run the same bounded AI. Pause and Undo must stop it.
        dots_tap_action dotsNewButton
        dots_tap_action dotsExtraBoardButton
        dots_choose_player 2 Computer
        dots_tap_action dotsRelaxedButton
        dots_mark_computer_count
        dots_tap_action dotsStartButton
        wait_for_log 'PaperDots new game 29 33 relaxed computer computer' 10
        wait_for_log 'PaperDots computer move' 25
        wait_for_log 'PaperDots computer move' 25
        dots_tap_action dotsPauseButton
        wait_for_log 'PaperDots pause true' 10
        dots_tap_action dotsUndoButton
        dots_mark_computer_count
        dots_tap_action dotsPauseButton
        wait_for_log 'PaperDots pause false' 10
        wait_for_log 'PaperDots computer move' 25
        dots_tap_action dotsPauseButton
        wait_for_log 'PaperDots pause true' 10
        SAVED_DOTS_MOVES=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDots pause true moves/ { for(i=1;i<NF;i++) if($i=="moves") count=$(i+1) } END { print count }')
        [[ "$SAVED_DOTS_MOVES" =~ ^[0-9]+$ ]]
        dots_tap_action dotsCloseButton
        wait_for_log 'PaperDots close' 10
        assert_tablet_healthy 'Dots close'
        # Restart once deliberately to validate actual QSettings restoration,
        # not only an in-memory engine replay.
        remote 'sed -i '\''s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl'
        sleep 10
        BASE_PID=$(remote 'pidof xochitl' | awk '{print $1}')
        wait_for_log "PaperDots ready restored $SAVED_DOTS_MOVES" 30
        wait_for_log "PaperDots match 29 33 computer computer paused true moves $SAVED_DOTS_MOVES" 10
        sleep 2 # Input handlers settle after the restored frontend appears.
        capture_screen "$ARTIFACT_DIR/dots-restored.png"
        # Close was exercised above in the interactive session. The test-only
        # autostart can construct a restored window before native navigation
        # is ready, so verify persisted state here rather than tapping through
        # the native navigator. Cleanup returns to the regular launcher.
        assert_tablet_healthy 'Dots saved game restoration'
        echo 'PASS: Dots physical dropdowns, all three boards, all four player modes, pause/resume, undo, close and saved-mode restoration'
        ;;
    showcase)
        tap 360 500
        wait_for_log 'PaperDesk touch launching literm' 10
        tap 1249 158
        wait_for_log 'PaperDesk Terminal shortcuts opened' 8
        capture_screen "$ARTIFACT_DIR/showcase-terminal.png"
        tap 1306 52
        wait_for_log 'PaperDesk Terminal action close' 8
        sleep 2

        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        sleep 8
        capture_screen "$ARTIFACT_DIR/showcase-web.png"
        tap 1310 52
        wait_for_log 'PaperWeb action close' 8
        sleep 2

        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        sleep 3
        capture_screen "$ARTIFACT_DIR/showcase-rdp.png"
        tap 1280 60
        wait_for_log 'PaperDesk RDP action close' 8
        sleep 2

        tap 1040 1250
        wait_for_log 'PaperDesk touch launching paperrss' 10
        sleep 5
        if remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | grep -Fq 'PaperRSS E2E full text ready'; then
            echo 'RSS showcase unexpectedly entered the hardware test fixture' >&2
            exit 1
        fi
        capture_screen "$ARTIFACT_DIR/showcase-rss.png"
        tap 1304 52
        wait_for_log 'PaperRSS action close' 30
        echo "PASS: real tablet showcase captures contain current production UI without RSS fixtures"
        ;;
    journey)
        for ((journey = 1; journey <= JOURNEY_LOOPS; ++journey)); do
            echo "User journey $journey/$JOURNEY_LOOPS: Terminal"
            tap 360 500
            wait_for_log 'PaperDesk touch launching literm' 10
            tap 1249 158
            wait_for_log 'PaperDesk Terminal shortcuts opened' 8
            tap 635 262
            wait_for_log 'PaperDesk Terminal shortcut' 8
            tap 1249 158
            wait_for_log 'PaperDesk Terminal shortcuts closed' 8
            tap 975 158
            wait_for_log 'PaperDesk Terminal keyboard hidden' 8
            tap 975 158
            wait_for_log 'PaperDesk Terminal keyboard opened' 8
            tap 1306 52
            wait_for_log 'PaperDesk Terminal action close' 8
            sleep 2
            assert_tablet_healthy "Terminal journey $journey"

            echo "User journey $journey/$JOURNEY_LOOPS: Web"
            tap 1040 500
            wait_for_log 'PaperDesk touch launching paperweb' 10
            wait_for_log 'PaperWeb E2E fixture ready' 10
            tap 500 160
            wait_for_log 'PaperWeb keyboard opened' 8
            tap 700 600
            wait_for_log 'PaperWeb keyboard hidden' 8
            tap 910 235
            wait_for_log 'PaperWeb view mode computer' 8
            tap 910 235
            wait_for_log 'PaperWeb view mode mobile' 8
            swipe 700 1400 700 500 700
            wait_for_log 'PaperWeb E2E content scrolled' 8
            swipe 700 500 700 1400 700
            pinch 600 900 800 900 450 900 950 900 700
            wait_for_log 'PaperWeb E2E zoom gesture' 8
            pinch 450 900 950 900 600 900 800 900 700
            wait_for_log 'PaperWeb E2E zoom gesture' 8
            tap 1360 252
            wait_for_log 'PaperWeb action zoom in' 8
            tap 1280 252
            wait_for_log 'PaperWeb action zoom out' 8
            tap 1310 52
            wait_for_log 'PaperWeb action close' 8
            sleep 2
            assert_tablet_healthy "Web journey $journey"

            echo "User journey $journey/$JOURNEY_LOOPS: RDP"
            tap 360 1250
            wait_for_log 'PaperDesk touch launching paperrdp-login' 10
            select_rdp_performance_profile
            tap 1060 60
            wait_for_log 'PaperDesk RDP keyboard opened' 8
            tap 1280 60
            wait_for_log 'PaperDesk RDP action close' 8
            sleep 2
            assert_tablet_healthy "RDP journey $journey"

            echo "User journey $journey/$JOURNEY_LOOPS: RSS"
            tap 1040 1250
            wait_for_log 'PaperDesk touch launching paperrss' 10
            wait_for_log 'PaperRSS E2E stress parser ready 12' 20
            wait_for_log 'PaperRSS E2E full text ready' 15
            swipe 700 1400 700 500 700
            wait_for_log 'PaperRSS E2E full text scrolled' 10
            swipe 700 500 700 1400 700
            pinch 600 900 800 900 450 900 950 900 700
            wait_for_log 'PaperRSS E2E zoom gesture' 10
            pinch 450 900 950 900 600 900 800 900 700
            wait_for_log 'PaperRSS E2E zoom gesture' 10
            tap 100 52
            wait_for_log 'PaperRSS action articles' 8
            tap 160 504
            wait_for_log 'PaperRSS action select feed https://physicsworld.com/feed/' 8
            tap 920 52
            wait_for_log 'PaperRSS action refresh' 8
            wait_for_log 'PaperRSS refresh complete 1 0' 45
            assert_tablet_healthy "live Physics World refresh $journey"
            tap 160 246
            wait_for_log 'PaperRSS action all articles' 8
            # rebuildArticles() is synchronous. Wait for the freshly rebuilt
            # ListModel to settle before sending the next physical gesture;
            # an evdev tap delivered while Qt is rebuilding can be discarded.
            sleep 2
            tap 1112 52
            wait_for_log 'PaperRSS action add feed view' 8
            tap 123 67
            wait_for_log 'PaperRSS action cancel add' 8
            tap 1304 52
            wait_for_log 'PaperRSS action close' 8
            sleep 2
            assert_tablet_healthy "RSS journey $journey"
        done
        capture_screen "$ARTIFACT_DIR/user-journey-final.png"
        echo "PASS: $JOURNEY_LOOPS repeated physical user journeys covered hub, Terminal, Web, RDP and RSS without a process restart or watchdog failure"
        ;;
    all)
        tap 360 500
        wait_for_log 'PaperDesk touch launching literm' 10
        tap 1249 158
        wait_for_log 'PaperDesk Terminal shortcuts opened' 8
        tap 635 262
        wait_for_log 'PaperDesk Terminal shortcut' 8
        capture_screen "$ARTIFACT_DIR/all-terminal.png"
        tap 1306 52
        wait_for_log 'PaperDesk Terminal action close' 8
        sleep 2

        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb E2E fixture ready' 10
        swipe 700 1400 700 500 700
        wait_for_log 'PaperWeb E2E content scrolled' 8
        pinch 600 900 800 900 450 900 950 900 700
        wait_for_log 'PaperWeb E2E zoom gesture' 8
        tap 1360 252
        wait_for_log 'PaperWeb action zoom in' 8
        tap 1280 252
        wait_for_log 'PaperWeb action zoom out' 8
        tap 1310 148
        wait_for_log 'PaperWeb action go' 8
        tap 50 160
        wait_for_log 'PaperWeb action back' 8
        capture_screen "$ARTIFACT_DIR/all-web.png"
        tap 1310 52
        wait_for_log 'PaperWeb action close' 8
        sleep 2

        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        select_rdp_performance_profile
        tap 1060 60
        wait_for_log 'PaperDesk RDP keyboard opened' 8
        capture_screen "$ARTIFACT_DIR/all-rdp-keyboard.png"
        tap 1280 60
        wait_for_log 'PaperDesk RDP action close' 8
        sleep 2

        tap 1040 1250
        wait_for_log 'PaperDesk touch launching paperrss' 10
        wait_for_log 'PaperRSS E2E full text ready' 15
        swipe 700 1400 700 500 700
        wait_for_log 'PaperRSS E2E full text scrolled' 10
        pinch 600 900 800 900 450 900 950 900 700
        wait_for_log 'PaperRSS E2E zoom gesture' 10
        tap 100 52
        wait_for_log 'PaperRSS action articles' 8
        tap 920 52
        wait_for_log 'PaperRSS action refresh' 8
        tap 920 52
        wait_for_log 'PaperRSS action stop refresh' 8
        tap 1112 52
        wait_for_log 'PaperRSS action add feed view' 8
        tap 123 67
        wait_for_log 'PaperRSS action cancel add' 8
        tap 160 246
        wait_for_log 'PaperRSS action all articles' 8
        # Give the synchronous ListModel rebuild time to finish. This keeps the
        # next hardware tap representative of a real user action.
        sleep 2
        capture_screen "$ARTIFACT_DIR/all-rss-list.png"
        tap 1304 52
        # /proc framebuffer capture can pause xochitl's event loop for more
        # than ten seconds on OS 3.29. Keep the single user tap and allow it
        # to drain instead of hiding the stall with repeated clicks.
        wait_for_log 'PaperRSS action close' 30
        echo "PASS: one physical tablet session covered every safe menu action, scrolling, pinch zoom, keyboard and close flows"
        ;;
    terminal)
        tap 360 500
        wait_for_log 'PaperDesk touch launching literm' 10
        wait_for_log 'PaperDesk Terminal refresh startup' 8
        wait_for_log 'PaperDesk Terminal keyboard opened automatically' 8
        sleep 2
        capture_screen "$ARTIFACT_DIR/terminal-menu-startup.png"
        remote 'for terminal_pid in $(pidof rmssh-menu 2>/dev/null || true); do terminal_tty=$(readlink /proc/$terminal_pid/fd/1); printf "\r\nPAPERDESK TERMINAL OUTPUT TEST\r\n" >"$terminal_tty"; done'
        wait_for_log 'PaperDesk Terminal display changed' 8
        capture_screen "$ARTIFACT_DIR/terminal.png"
        tap 429 158
        wait_for_log 'PaperDesk Terminal display panel opened' 8
        capture_screen "$ARTIFACT_DIR/terminal-display-panel.png"
        tap 460 262
        wait_for_log 'PaperDesk Terminal display ansi tones' 8
        remote 'for terminal_pid in $(pidof rmssh-menu 2>/dev/null || true); do terminal_tty=$(readlink /proc/$terminal_pid/fd/1); printf "\r\n\033[31mRED\033[0m  \033[32mGREEN\033[0m  \033[34mBLUE\033[0m\r\n" >"$terminal_tty"; done'
        sleep 2
        assert_tablet_healthy 'Terminal ANSI tones'
        capture_screen "$ARTIFACT_DIR/terminal-ansi-tones.png"
        tap 944 262
        wait_for_log 'PaperDesk Terminal font size' 8
        tap 218 262
        wait_for_log 'PaperDesk Terminal display high contrast' 8
        tap 429 158
        wait_for_log 'PaperDesk Terminal display panel closed' 8
        tap 702 158
        wait_for_log 'PaperDesk Terminal mouse mode on' 8
        tap 700 600
        wait_for_log 'PaperDesk Terminal mouse left' 8
        hold 700 600 850
        wait_for_log 'PaperDesk Terminal mouse right' 8
        tap 702 158
        wait_for_log 'PaperDesk Terminal mouse mode off' 8
        tap 1249 158
        wait_for_log 'PaperDesk Terminal shortcuts opened' 8
        tap 975 158
        wait_for_log 'PaperDesk Terminal keyboard hidden' 8
        tap 975 158
        wait_for_log 'PaperDesk Terminal keyboard opened' 8
        capture_screen "$ARTIFACT_DIR/terminal-shortcuts.png"
        tap 1306 52
        wait_for_log 'PaperDesk Terminal action close' 8
        assert_tablet_healthy 'Terminal output, mouse, display modes, shortcuts, keyboard, and close'
        echo "PASS: physical tablet input covered terminal mouse clicks, output, display modes, font size, shortcuts, keyboard hide/show, and close"
        ;;
    web)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb E2E fixture ready' 10
        tap 500 160
        wait_for_log 'PaperWeb keyboard opened' 8
        wait_for_log 'PaperWeb address selected' 8
        wait_for_log 'PaperWeb address selection stable 23 23' 8
        capture_screen "$ARTIFACT_DIR/web-keyboard-open.png"
        tap 700 600
        wait_for_log 'PaperWeb keyboard hidden' 8
        tap 910 235
        wait_for_log 'PaperWeb view mode computer' 8
        tap 910 235
        wait_for_log 'PaperWeb view mode mobile' 8
        tap 50 160
        wait_for_log 'PaperWeb action back' 8
        assert_tablet_healthy 'Web contextual keyboard and mobile profile'
        capture_screen "$ARTIFACT_DIR/web-keyboard-hidden.png"
        echo "PASS: physical taps opened and dismissed the contextual keyboard, then requested a mobile document"
        ;;
    web-file-blocked)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10 || exit 1
        wait_for_log 'PaperWeb E2E blocked file fixture ready' 10 || exit 1
        tap 190 349
        wait_for_log 'PaperWeb link activated https://paperdesk.lukaszbabut.info/download/SHA256SUMS' 8 || exit 1
        wait_for_log 'PaperWeb request profile mobile' 8 || exit 1
        wait_for_log 'PaperWeb file download blocked https://paperdesk.lukaszbabut.info/download/SHA256SUMS' 8 || exit 1
        assert_tablet_healthy 'unsupported PaperWeb file response' || exit 1
        capture_screen "$ARTIFACT_DIR/web-file-blocked.png"
        echo "PASS: a physical file-link tap was refused cleanly without restarting Xochitl"
        ;;
    web-live-wp)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'live WP reader load'
        capture_screen "$ARTIFACT_DIR/web-live-wp-pictures-off.png"
        tap 143 160
        wait_for_log 'PaperWeb action reload' 8
        wait_for_log 'PaperWeb request profile mobile' 8
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'live WP reload'
        tap 910 235
        wait_for_log 'PaperWeb view mode computer' 8
        wait_for_log 'PaperWeb request profile desktop' 8
        wait_for_log 'PaperWeb renderer computer page' 45
        assert_tablet_healthy 'live WP computer page'
        capture_screen "$ARTIFACT_DIR/web-live-wp-computer.png"
        tap 910 235
        wait_for_log 'PaperWeb view mode mobile' 8
        wait_for_log 'PaperWeb request profile mobile' 8
        wait_for_log 'PaperWeb renderer mobile reader' 30
        assert_tablet_healthy 'live WP mobile reader restored'
        capture_screen "$ARTIFACT_DIR/web-live-wp-mobile.png"
        tap 1095 235
        wait_for_log 'PaperWeb pictures shown' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        sleep 5
        assert_tablet_healthy 'live WP pictures shown'
        capture_screen "$ARTIFACT_DIR/web-live-wp-pictures-on.png"
        tap 1095 235
        wait_for_log 'PaperWeb pictures hidden' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        swipe 700 1450 700 550 700
        sleep 3
        assert_tablet_healthy 'live WP reader scroll'
        capture_screen "$ARTIFACT_DIR/web-live-wp-scrolled.png"
        echo "PASS: live WP.pl toggled pictures and scrolled on the physical tablet"
        ;;
    web-live-dynamic)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb embedded reader items' 30
        assert_tablet_healthy 'generic embedded-data reader load'
        capture_screen "$ARTIFACT_DIR/web-live-dynamic-pictures-off.png"
        tap 1095 235
        wait_for_log 'PaperWeb pictures shown' 10
        wait_for_log 'PaperWeb embedded reader items' 30
        sleep 5
        assert_tablet_healthy 'generic embedded-data pictures shown'
        capture_screen "$ARTIFACT_DIR/web-live-dynamic-pictures-on.png"
        swipe 700 1450 700 550 700
        sleep 3
        assert_tablet_healthy 'generic embedded-data reader scroll'
        capture_screen "$ARTIFACT_DIR/web-live-dynamic-scrolled.png"
        tap 910 235
        wait_for_log 'PaperWeb view mode computer' 10
        wait_for_log 'PaperWeb request profile desktop' 10
        wait_for_log 'PaperWeb embedded reader items' 30
        assert_tablet_healthy 'desktop application-shell reader fallback'
        capture_screen "$ARTIFACT_DIR/web-live-dynamic-desktop-fallback.png"
        echo "PASS: a live JavaScript-driven site rendered from generic embedded data, scrolled, and retained the reader fallback in Computer mode"
        ;;
    web-live-linked-images)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'linked-image reader load'
        tap 1095 235
        wait_for_log 'PaperWeb pictures shown' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        sleep 5
        assert_tablet_healthy 'linked pictures shown'
        capture_screen "$ARTIFACT_DIR/web-live-linked-images.png"
        echo "PASS: separately linked story pictures rendered in Mobile mode on the physical tablet"
        ;;
    web-live-dense-cards)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'dense-card reader load'
        tap 1095 235
        wait_for_log 'PaperWeb pictures shown' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        sleep 12
        assert_tablet_healthy 'dense-card pictures shown'
        capture_screen "$ARTIFACT_DIR/web-live-dense-cards.png"
        echo "PASS: dense desktop markup became compact title-first Mobile cards on the physical tablet"
        ;;
    web-live-article-journey)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'live article list load'
        tap 500 384
        wait_for_log 'PaperWeb link activated https://kryminalne.o2.pl/' 12
        wait_for_log 'PaperWeb article reader DOM' 30
        assert_tablet_healthy 'live article opened through physical link tap'
        capture_screen "$ARTIFACT_DIR/web-live-article-journey.png"
        echo "PASS: a physical tablet tap opened a live article and rendered its body"
        ;;
    web-live-script-filter)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        wait_for_log 'PaperWeb E2E technical content clean' 10
        if remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | grep -Fq 'PaperWeb E2E technical content leaked'; then
            echo 'Technical page payload leaked into visible reader text' >&2
            exit 1
        fi
        swipe 700 1450 700 550 700
        sleep 3
        assert_tablet_healthy 'live technical-content filter'
        capture_screen "$ARTIFACT_DIR/web-live-script-filter.png"
        echo "PASS: live page scripts stayed out of the reader during physical scrolling"
        ;;
    web-live-polish-text)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 35
        wait_for_log 'PaperWeb E2E Polish text clean' 10
        if remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" | grep -Fq 'PaperWeb E2E Polish text broken'; then
            echo 'Broken Polish encoding reached visible reader text' >&2
            exit 1
        fi
        swipe 700 1450 700 550 700
        sleep 3
        assert_tablet_healthy 'live Polish text decoding'
        capture_screen "$ARTIFACT_DIR/web-live-polish-text.png"
        echo "PASS: live Polish headlines rendered without mojibake or numeric entities"
        ;;
    rdp)
        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        sleep 3
        capture_screen "$ARTIFACT_DIR/rdp.png"
        rdp_tap_action rdpProfileNewButton
        wait_for_log 'PaperDesk RDP profile add' 8
        wait_for_log 'PaperDesk RDP E2E new profile prepared' 8
        rdp_tap_action usernameInput
        sleep 2
        viewport=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/PaperDesk RDP viewport/ { for (i=1;i<NF;++i) if ($i=="viewport") print $(i+1) }' | tail -n1)
        [[ "$viewport" =~ ^[0-9]+$ ]] && (( viewport > 0 ))
        save_y=$(remote "journalctl -u xochitl --since '@$RUN_STARTED' --no-pager" |
            awk '/target rdpProfileSaveButton / { for (i=1;i<NF;++i) if ($i=="target") print $(i+3) }' | tail -n1)
        [[ "$save_y" =~ ^[0-9]+$ ]]
        (( save_y < 1872 - viewport ))
        swipe 800 950 800 420 650
        sleep 2
        rdp_tap_action portInput
        sleep 1
        rdp_tap_action rdpProfileCancelButton
        wait_for_log 'PaperDesk RDP profile edit cancelled' 8
        remote 'test "$(grep -c "^v1" /home/root/.config/paperrdp/profiles)" -eq 2'

        rdp_tap_action rdpProfileNewButton
        wait_for_log 'PaperDesk RDP profile add' 8
        wait_for_log 'PaperDesk RDP E2E new profile prepared' 8
        rdp_tap_action rdpProfileSaveButton
        wait_for_log 'PaperDesk RDP action save profile' 8
        wait_for_log 'PaperDesk RDP profile saved 0' 8
        sleep 2
        remote 'test "$(grep -Ec "^v[12]" /home/root/.config/paperrdp/profiles)" -eq 3
grep -q "7264702d6532652d63726561746564" /home/root/.config/paperrdp/profiles
test "$(stat -c %a /home/root/.config/paperrdp/profiles)" = 600'

        rdp_tap_action rdpProfileEditButton
        wait_for_log 'PaperDesk RDP profile edit 0' 8
        wait_for_log 'PaperDesk RDP E2E profile edit prepared' 8
        rdp_tap_action rdpProfileSaveButton
        wait_for_log 'PaperDesk RDP action save profile' 8
        wait_for_log 'PaperDesk RDP profile saved 0' 8
        sleep 2
        remote 'test "$(grep -Ec "^v[12]" /home/root/.config/paperrdp/profiles)" -eq 3
grep -q "7264702d6532652d656469746564" /home/root/.config/paperrdp/profiles
! grep -q "7264702d6532652d63726561746564" /home/root/.config/paperrdp/profiles'
        capture_screen "$ARTIFACT_DIR/rdp-performance.png"
        rdp_tap_action rdpProfileDeleteButton
        wait_for_log 'PaperDesk RDP profile delete confirmation 0' 8
        rdp_tap_action rdpDeleteConfirmButton
        wait_for_log 'PaperDesk RDP profile deleted 0' 8
        sleep 2
        remote 'test "$(grep -c "^v1" /home/root/.config/paperrdp/profiles)" -eq 2
! grep -q "7264702d6532652d656469746564" /home/root/.config/paperrdp/profiles'
        rdp_tap_action rdpSavedProfileButton_0
        wait_for_log 'PaperDesk RDP profile selected rdp-e2e-one paperdesk-test' 8
        rdp_tap_action rdpConnectLabel
        wait_for_log 'PaperDesk RDP profile open 0' 8
        for n in $(seq 1 20); do
            if remote 'pidof paperrdp >/dev/null'; then break; fi
            sleep 1
        done
        remote 'pidof paperrdp >/dev/null'
        assert_tablet_healthy 'RDP profile management'
        echo "PASS: physical tablet taps covered RDP New, Cancel, Save, Edit, confirmed Delete, and Connect"
        ;;
    rdp-landscape)
        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        sleep 3
        profile_index=${PAPERDESK_RDP_PROFILE_INDEX:-0}
        [[ "$profile_index" =~ ^[0-7]$ ]]
        rdp_tap_action "rdpSavedProfileButton_$profile_index"
        rdp_tap_action rdpProfileEditButton
        wait_for_log 'PaperDesk RDP profile edit' 8
        swipe 800 1450 800 450 650
        sleep 2
        rdp_tap_action rdpOrientationButton_landscape
        wait_for_log 'PaperDesk RDP orientation landscape' 8
        rdp_tap_action rdpProfileSaveButton
        wait_for_log 'PaperDesk RDP profile saved' 8
        swipe 800 1450 800 450 650
        sleep 2
        rdp_tap_action rdpConnectLabel
        wait_for_log 'PaperDesk RDP action connect' 8
        wait_for_log 'PaperDesk RDP orientation landscape logical=1872x1404' 20
        wait_for_log 'PaperDesk RDP connected' 30
        sleep 4
        # Read only this client's shared raster, not xochitl's live fb mapping.
        # It is safe to inspect locally and cannot stall the display service.
        remote 'set -eu; p=$(pidof paperrdp); p=${p%% *};
raster=$(grep -o "/dev/shm/qtfb_[0-9]*" /proc/$p/maps);
test -n "$raster"; test -f "$raster"; cat "$raster"' > "$ARTIFACT_DIR/rdp-landscape.rgb565"
        ffmpeg -y -loglevel error -f rawvideo -pixel_format rgb565le -video_size 1404x1872 \
            -i "$ARTIFACT_DIR/rdp-landscape.rgb565" -vf transpose=2 -frames:v 1 "$ARTIFACT_DIR/rdp-landscape.png"
        # Physical coordinates, NOT QML mouseClick: every event goes through
        # the tablet touch device, QTFB, inverse rotation and FreeRDP.
        tap 700 900
        tap 700 900
        wait_for_log 'PaperDesk RDP double click' 8
        hold 650 850 850
        wait_for_log 'PaperDesk RDP right click' 8
        pinch 550 800 850 800 400 800 1000 800 700
        sleep 3
        swipe 650 950 850 1050 700
        sleep 2
        pinch 400 800 1000 800 550 800 850 800 700
        sleep 3
        # Landscape toolbar: keyboard is physically on the right edge.
        rdp_engine_tap_action paperdeskRdpKeyboardButton
        wait_for_log 'PaperDesk RDP native keyboard shown' 8
        wait_for_log 'PaperDesk RDP native keyboard visible true' 8
        wait_for_log 'PaperDesk RDP native keyboard layout 90 1872 1404' 8
        sleep 2
        # The ACTUAL native panel now shares the raster/chrome rotation.
        # Hide stays on the landscape top edge; no mid-click geometry jump.
        rdp_engine_tap_action paperdeskRdpKeyboardButton
        # Firmware may consume the outside press while dismissing its panel,
        # so assert the actual panel state, not the QML button handler log.
        wait_for_log 'PaperDesk RDP native keyboard visible false' 8
        sleep 2
        rdp_engine_tap_action paperdeskRdpShortcutsButton
        wait_for_log 'PaperDesk RDP shortcuts opened' 8
        rdp_engine_tap_action paperdeskRdpShortcut_7
        wait_for_log 'PaperDesk RDP shortcut 7' 8
        rdp_engine_tap_action paperdeskRdpShortcutsButton
        wait_for_log 'PaperDesk RDP shortcuts opened' 8
        # Back in the rotated shortcuts panel, then rotated Close.
        rdp_engine_tap_action paperdeskRdpShortcutsBackButton
        sleep 2
        rdp_engine_tap_action paperdeskRdpCloseButton
        wait_for_log 'PaperDesk AppLoad window hidden before close PaperDesk RDP Engine' 8
        sleep 2
        remote '! pidof paperrdp >/dev/null'
        # Exercise the foreground restored after engine Close without a
        # service restart: an orphan QTFB window must not steal these taps.
        rdp_tap_action rdpProfileEditButton
        wait_for_log 'PaperDesk RDP profile edit' 8
        rdp_tap_action rdpProfileCancelButton
        wait_for_log 'PaperDesk RDP profile edit cancelled' 8
        rdp_tap_action rdpCloseButton
        wait_for_log 'PaperDesk RDP action close' 8
        tap 360 500
        wait_for_log 'PaperDesk touch launching literm' 10
        tap 1306 52
        wait_for_log 'PaperDesk Terminal action close' 8
        assert_tablet_healthy 'landscape RDP gestures, native keyboard and Close'
        echo 'PASS: landscape RDP profile, real connection, physical taps, double-click, long-press, pinch, pan, native keyboard, shortcuts, Close and responsive frontend/SSH without restarting xochitl'
        ;;
    rdp-live)
        expected_scale=$(remote "awk -F= '\$1==\"scale_percent\" { print \$2 }' /home/root/.config/paperrdp/profile")
        expected_colors=$(remote "awk -F= '\$1==\"color_depth\" { print \$2 }' /home/root/.config/paperrdp/profile")
        test -n "$expected_scale" && test -n "$expected_colors"
        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        sleep 3
        # Use the user's selected profile as-is. Performance controls are
        # intentionally locked outside Edit mode, so tapping them here no
        # longer changes anything after the profile-manager redesign.
        rdp_tap_action rdpConnectLabel
        wait_for_log 'PaperDesk RDP action connect' 10
        for n in $(seq 1 30); do
            if remote 'pidof paperrdp >/dev/null'; then break; fi
            sleep 1
        done
        remote 'pidof paperrdp >/dev/null'
        wait_for_log "PaperDesk RDP performance scale=$expected_scale colors=$expected_colors" 15
        sleep 12
        remote 'p=$(pidof paperrdp); p=${p%% *}; grep -Eq "[[:space:]]01[[:space:]]" /proc/$p/net/tcp'
        assert_tablet_healthy 'live RDP connection'
        capture_screen "$ARTIFACT_DIR/rdp-live-scaled.png"
        tap 1240 1540
        tap 1240 1540
        wait_for_log 'PaperDesk RDP double click' 8
        hold 1160 1460 850
        wait_for_log 'PaperDesk RDP right click' 8
        pinch 600 900 800 900 450 900 950 900 700
        sleep 3
        hold 700 1000 850
        wait_for_log 'PaperDesk RDP right click' 8
        pinch 450 900 950 900 600 900 800 900 700
        sleep 3
        rdp_engine_tap_action paperdeskRdpKeyboardButton
        sleep 3
        remote 'pidof paperrdp >/dev/null'
        rdp_engine_tap_action paperdeskRdpKeyboardButton
        sleep 2
        rdp_engine_tap_action paperdeskRdpShortcutsButton
        sleep 3
        remote 'pidof paperrdp >/dev/null'
        rdp_engine_tap_action paperdeskRdpShortcutsBackButton
        sleep 12
        assert_tablet_healthy 'live RDP overlay and refresh soak'
        remote 'pidof paperrdp >/dev/null'
        rdp_engine_tap_action paperdeskRdpCloseButton
        sleep 3
        if remote 'pidof paperrdp >/dev/null'; then
            echo 'Live RDP did not close after the physical Close tap' >&2
            exit 1
        fi
        echo "PASS: live RDP used the saved fast profile, handled double-click, zoomed and unzoomed right-clicks, overlays and refresh soak, then closed from a physical tap"
        ;;
    rdp-doubleclick)
        expected_scale=$(remote "awk -F= '\$1==\"scale_percent\" { print \$2 }' /home/root/.config/paperrdp/profile")
        expected_colors=$(remote "awk -F= '\$1==\"color_depth\" { print \$2 }' /home/root/.config/paperrdp/profile")
        test -n "$expected_scale" && test -n "$expected_colors"
        tap 360 1250
        wait_for_log 'PaperDesk touch launching paperrdp-login' 10
        sleep 3
        rdp_tap_action rdpConnectLabel
        wait_for_log 'PaperDesk RDP action connect' 10
        for n in $(seq 1 30); do
            if remote 'pidof paperrdp >/dev/null'; then break; fi
            sleep 1
        done
        remote 'pidof paperrdp >/dev/null'
        wait_for_log "PaperDesk RDP performance scale=$expected_scale colors=$expected_colors" 15
        sleep 8
        tap 800 900
        tap 800 900
        wait_for_log 'PaperDesk RDP double click' 8
        sleep 2
        rdp_engine_tap_action paperdeskRdpCloseButton
        sleep 3
        if remote 'pidof paperrdp >/dev/null'; then
            echo 'RDP did not close after the double-click probe' >&2
            exit 1
        fi
        assert_tablet_healthy 'live RDP double-click probe'
        echo "PASS: physical tablet taps produced the RDP double-click completion trace"
        ;;
    rss)
        tap 1040 1250
        wait_for_log 'PaperDesk touch launching paperrss' 10
        wait_for_log 'PaperRSS E2E full text ready' 15
        capture_screen "$ARTIFACT_DIR/rss-before-scroll.png"
        swipe 700 1400 700 500 700
        wait_for_log 'PaperRSS E2E full text scrolled' 10
        capture_screen "$ARTIFACT_DIR/rss-full-text-scrolled.png"
        tap 85 50
        sleep 2
        capture_screen "$ARTIFACT_DIR/rss-list.png"
        tap 1120 50
        sleep 2
        capture_screen "$ARTIFACT_DIR/rss-add-feed.png"
        echo "PASS: physical input covered RSS reader, scroll, list, and add-feed view"
        ;;
    rss-auto-full)
        tap 1040 1250
        wait_for_log 'PaperDesk touch launching paperrss' 10
        wait_for_log 'PaperRSS E2E automatic full text ready' 15
        wait_for_log 'PaperRSS full text request https://example.com' 15
        assert_tablet_healthy 'RSS automatic full-text request'
        tap 1304 52
        wait_for_log 'PaperRSS action close' 15
        echo "PASS: opening an RSS article with a physical tablet tap requested its full text automatically"
        ;;
    rss-live-full)
        tap 1040 1250
        wait_for_log 'PaperDesk touch launching paperrss' 10
        wait_for_log 'PaperRSS E2E automatic full text ready' 15
        wait_for_log 'PaperRSS full text request https://www.sciencedaily.com/releases/2026/09/260929053536.htm' 15
        wait_for_log 'PaperRSS full text response' 20
        wait_for_log 'PaperRSS full text ready hardware-auto-full-text' 10
        capture_screen "$ARTIFACT_DIR/rss-live-full-text.png"
        assert_tablet_healthy 'RSS live full-text response'
        tap 1304 52
        wait_for_log 'PaperRSS action close' 15
        echo "PASS: a physical tablet tap opened RSS and downloaded a live full article"
        ;;
    care)
        wait_for_log 'PaperDesk Care action check' 15
        wait_for_log 'PaperDesk Care manifest' 15
        tap 1117 56
        wait_for_log 'PaperDesk Care action check' 8
        wait_for_log 'PaperDesk Care manifest' 15
        wait_for_log 'PaperDesk Care E2E uninstall geometry' 8
        care_tap_geometry uninstall
        wait_for_log 'PaperDesk Care action uninstall confirmation' 8
        wait_for_log 'PaperDesk Care E2E cancel geometry' 8
        care_tap_geometry cancel
        wait_for_log 'PaperDesk Care action uninstall cancel' 8
        tap 1300 56
        wait_for_log 'PaperDesk Care action close' 8
        assert_tablet_healthy 'PaperDesk Care check, uninstall cancellation, and close'
        echo "PASS: physical input checked updates, opened and cancelled uninstall, and closed PaperDesk Care"
        ;;
    *)
        echo "Unknown PAPERDESK_E2E_TARGET: $TARGET" >&2
        exit 2
        ;;
esac
