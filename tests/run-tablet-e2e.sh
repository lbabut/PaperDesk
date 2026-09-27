#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKDIR=${PAPERDESK_WORKDIR:-$ROOT/work}
HOST=${PAPERDESK_TABLET_HOST:-10.11.99.1}
KEY=${PAPERDESK_TABLET_KEY:-$WORKDIR/keys/remarkable2_ed25519}
KNOWN_HOSTS=${PAPERDESK_KNOWN_HOSTS:-$WORKDIR/keys/known_hosts}
REMOTE=root@$HOST
SSH=(ssh -i "$KEY" -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes "$REMOTE")
SCP=(scp -i "$KEY" -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes)
RUN_STARTED=$(date +%s)
ARTIFACT_DIR=${PAPERDESK_ARTIFACT_DIR:-$WORKDIR/tests/tablet-e2e}
TOOLCHAIN="$WORKDIR/arm-toolchain/root"
TARGET=${PAPERDESK_E2E_TARGET:-all}
JOURNEY_LOOPS=${PAPERDESK_E2E_LOOPS:-2}
CAPTURE_SCREEN=${PAPERDESK_E2E_CAPTURE:-1}
BASE_PID=""
declare -A LOG_EXPECTED=()

remote() { "${SSH[@]}" "$@"; }

cleanup() {
    set +e
    remote 'set +e
if test -f /tmp/paperdesk-e2e-physical-dev; then
    systemctl stop xochitl
    PHYSICAL=$(cat /tmp/paperdesk-e2e-physical-dev)
    rm -f /dev/input/event2
    mknod /dev/input/event2 c ${PHYSICAL%:*} ${PHYSICAL#*:}
    chown root:input /dev/input/event2
    chmod 660 /dev/input/event2
fi
if test -f /tmp/paperdesk-e2e-xochitl.conf; then
    cp /tmp/paperdesk-e2e-xochitl.conf /home/root/.config/remarkable/xochitl.conf
fi
awk '\''
BEGIN { in_e2e=0 }
/^\[PaperDeskE2E\]$/ { in_e2e=1; next }
/^\[/ { in_e2e=0 }
!in_e2e { print }
'\'' /home/root/.config/remarkable/xochitl.conf > /tmp/paperdesk-e2e-clean.conf
mv /tmp/paperdesk-e2e-clean.conf /home/root/.config/remarkable/xochitl.conf
printf "quit\n" >/tmp/paperdesk-touch.fifo 2>/dev/null || true
sleep 1
for helper_pid in $(pidof paperdesk-rm-touchd || true); do
    kill -9 "$helper_pid" 2>/dev/null || true
done
rm -f /tmp/paperdesk-touch.fifo /tmp/paperdesk-touch.ready
rm -f /tmp/paperdesk-e2e-physical-dev /tmp/paperdesk-e2e-xochitl.conf
systemctl reset-failed xochitl
systemctl start xochitl
sleep 8
' >/dev/null
}
trap cleanup EXIT INT TERM

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
    remote "printf 'tap %s %s\\n' '$1' '$2' >/tmp/paperdesk-touch.fifo"
}

swipe() {
    remote "printf 'swipe %s %s %s %s %s\\n' '$1' '$2' '$3' '$4' '$5' >/tmp/paperdesk-touch.fifo"
}

pinch() {
    remote "printf 'pinch %s %s %s %s %s %s %s %s %s\\n' '$1' '$2' '$3' '$4' '$5' '$6' '$7' '$8' '$9' >/tmp/paperdesk-touch.fifo"
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
LD_LIBRARY_PATH="$TOOLCHAIN/usr/lib/x86_64-linux-gnu" \
    "$TOOLCHAIN/usr/bin/arm-linux-gnueabihf-gcc-12" \
    --sysroot="$TOOLCHAIN" -O2 -Wall -Wextra \
    "$ROOT/tests/rm-touchd.c" -o "$WORKDIR/tests/rm-touchd"
"${SCP[@]}" "$WORKDIR/tests/rm-touchd" "$REMOTE:/tmp/paperdesk-rm-touchd"

remote 'set -eu
chmod 700 /tmp/paperdesk-rm-touchd
PHYSICAL=$(cat /sys/class/input/event2/dev)
echo "$PHYSICAL" >/tmp/paperdesk-e2e-physical-dev
cp /home/root/.config/remarkable/xochitl.conf /tmp/paperdesk-e2e-xochitl.conf
systemctl stop xochitl
awk '\''
BEGIN { in_e2e=0 }
/^\[PaperDeskE2E\]$/ { in_e2e=1; next }
/^\[/ { in_e2e=0 }
!in_e2e { print }
'\'' /home/root/.config/remarkable/xochitl.conf > /tmp/paperdesk-e2e-base.conf
mv /tmp/paperdesk-e2e-base.conf /home/root/.config/remarkable/xochitl.conf
printf "\n[PaperDeskE2E]\nautostart=true\napplicationId=paperdesk\nscenarioVersion=20260927\ntraceTouches=true\nwebFixture=true\nwebTraceGestures=true\nrssLongArticle=true\nrssStressParser=true\nrssTraceScroll=true\n" >>/home/root/.config/remarkable/xochitl.conf
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
elif [[ "$TARGET" == "care" ]]; then
    AUTOSTART_APPLICATION=papercare
    remote 'sed -i '\''s/^applicationId=.*/applicationId=papercare/; s/^autostart=.*/autostart=true/'\'' /home/root/.config/remarkable/xochitl.conf
systemctl restart xochitl
sleep 28'
fi

wait_for_log "PaperDesk E2E autostart $AUTOSTART_APPLICATION" 40
wait_for_log 'Application starting with' 10
BASE_PID=$(remote 'pidof xochitl' | awk '{print $1}')
assert_tablet_healthy 'startup'
capture_screen "$ARTIFACT_DIR/paperdesk-autostart.png"
sleep 2

case "$TARGET" in
    showcase)
        tap 360 500
        wait_for_log 'PaperDesk touch launching literm' 10
        tap 1120 50
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
            tap 1120 50
            wait_for_log 'PaperDesk Terminal shortcuts opened' 8
            tap 635 150
            wait_for_log 'PaperDesk Terminal shortcut' 8
            tap 1120 50
            wait_for_log 'PaperDesk Terminal shortcuts closed' 8
            tap 934 50
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
            tap 1360 213
            wait_for_log 'PaperWeb action zoom in' 8
            tap 1280 213
            wait_for_log 'PaperWeb action zoom out' 8
            tap 1310 52
            wait_for_log 'PaperWeb action close' 8
            sleep 2
            assert_tablet_healthy "Web journey $journey"

            echo "User journey $journey/$JOURNEY_LOOPS: RDP"
            tap 360 1250
            wait_for_log 'PaperDesk touch launching paperrdp-login' 10
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
            tap 940 52
            wait_for_log 'PaperRSS action favourite' 8
            tap 940 52
            wait_for_log 'PaperRSS action favourite' 8
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
        tap 1120 50
        wait_for_log 'PaperDesk Terminal shortcuts opened' 8
        tap 635 150
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
        tap 1360 213
        wait_for_log 'PaperWeb action zoom in' 8
        tap 1280 213
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
        tap 940 52
        wait_for_log 'PaperRSS action favourite' 8
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
        sleep 3
        capture_screen "$ARTIFACT_DIR/terminal.png"
        tap 1120 50
        wait_for_log 'PaperDesk Terminal shortcuts opened' 8
        capture_screen "$ARTIFACT_DIR/terminal-shortcuts.png"
        echo "PASS: physical tablet taps opened Terminal and its shortcuts"
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
    web-live-wp)
        tap 1040 500
        wait_for_log 'PaperDesk touch launching paperweb' 10
        wait_for_log 'PaperWeb HTML reader items' 30
        assert_tablet_healthy 'live WP reader load'
        capture_screen "$ARTIFACT_DIR/web-live-wp-pictures-off.png"
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
        tap 500 350
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
        tap 1060 60
        wait_for_log 'PaperDesk RDP keyboard opened' 8
        capture_screen "$ARTIFACT_DIR/rdp-keyboard.png"
        echo "PASS: physical tablet taps opened RDP and its keyboard"
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
    care)
        wait_for_log 'PaperDesk Care action check' 15
        wait_for_log 'PaperDesk Care manifest' 15
        tap 1117 56
        wait_for_log 'PaperDesk Care action check' 8
        wait_for_log 'PaperDesk Care manifest' 15
        tap 1174 1402
        wait_for_log 'PaperDesk Care action uninstall confirmation' 8
        sleep 1
        tap 944 1505
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
