import hashlib
import struct
from datetime import date
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RELEASE = ROOT / "product"
TOOLCACHE = pathlib.Path(
    os.environ.get(
        "PAPERDESK_TOOLCACHE",
        "/home/lukasz/Documents/Codex/2026-09-25/m-2/work",
    )
)



def resource_bytes_without_timestamps(path):
    data = bytearray(path.read_bytes())
    assert data[:4] == b"qres"
    version, tree = struct.unpack_from(">II", data, 4)
    assert version in (2, 3)
    assert (len(data) - tree) % 22 == 0
    for offset in range(tree, len(data), 22):
        data[offset + 14:offset + 22] = b"\0" * 8
    return data

class PackageRegressionTests(unittest.TestCase):
    def test_visual_controls_avoid_the_unavailable_tablet_accessibility_attachment(self):
        # Desktop Qt exposes Accessible; the tested tablet firmware does not.
        # An attached property would prevent the whole app from loading there.
        for name in ('paperterminal', 'paperweb', 'paperrdp-login', 'paperrss', 'papercare', 'paperbooks', 'paperdots'):
            for qml in (RELEASE / 'payload/apps' / name / 'ui').glob('*.qml'):
                self.assertNotIn('Accessible.', qml.read_text(), str(qml))

    def test_qtfb_shim_source_package_is_self_contained(self):
        source = RELEASE / "third_party_source/qtfb-shim/src/qtfb-client"
        client = RELEASE / "payload/apps/paperrdp"
        self.assertTrue(source.is_dir())
        self.assertFalse(source.is_symlink())
        for name in ("qtfb-client.cpp", "qtfb-client.h", "common.h"):
            self.assertEqual((source / name).read_bytes(), (client / name).read_bytes())

    def test_safe_appload_close_compatibility_patch_is_shipped(self):
        system = RELEASE / "payload/system"
        mapping = (system / "paperdesk-appload-compat.qrr").read_text()
        self.assertIn("R /appload/qml/window.qml", mapping)
        self.assertIn("R /appload/qml/appload.qml", mapping)

        window = (system / "paperdesk-appload-window.qml").read_text()
        self.assertIn("loader.item?.unloading", window)
        self.assertIn("loaderScaled.item?.unloading", window)
        self.assertIn("property bool closing: false", window)
        self.assertIn("if(root.closing) return", window)
        self.assertIn("root.enabled = false", window)
        self.assertIn("root.visible = false", window)
        self.assertIn("root.z = -1", window)
        self.assertIn("qtfbKey != -1 && framebufferWasActive", window)
        self.assertIn("if(root.virtualKeyboardRef &&", window)
        self.assertIn('objectName: "paperdeskKeyboardClickTarget"', window)
        self.assertIn('"HIDE KEYBOARD"', window)
        self.assertIn("toggleVirtualKeyboard()", window)
        self.assertIn("function notifyGainedFocus()", window)
        self.assertNotIn('"MENU"', window)
        for unsupported in (
            "sendFlippedRotationToClient",
            "supportsRotation",
            "fbRotation",
            "fillMode: FBController.PreserveAspectFit",
        ):
            self.assertNotIn(unsupported, window)

        appload = (system / "paperdesk-appload.qml").read_text()
        snapshot = appload.split("function snapshotApplication", 1)[1].split(
            "function launchWindow", 1
        )[0]
        self.assertIn('typeof modelData.name !== "string"', snapshot)
        self.assertLess(
            appload.index("const application = snapshotApplication(modelData)"),
            appload.index("windowArchetype.createObject"),
        )
        self.assertIn("function launchApplicationById", appload)
        self.assertIn('category: "PaperDeskE2E"', appload)
        self.assertIn("PaperDesk E2E autostart", appload)
        self.assertIn("library.reloadList()", appload)
        self.assertIn("registerPaperDeskWindow(win)", appload)
        self.assertIn("unregisterPaperDeskWindow(closingWindow)", appload)
        self.assertIn("previous.enabled = false", appload)
        self.assertIn("previous.notifyGainedFocus()", appload)
        self.assertIn("stableApplicationId", appload)
        self.assertIn('application.id !== "paperdesk"', appload)
        self.assertIn('application.id !== "external::paperrdp"', appload)
        self.assertIn('application.id !== "external::paperweb-download"', appload)
        self.assertIn("model: launcherApplications", appload)
        close_handler = appload.split("win.closed.connect(() => {", 1)[1].split("});", 1)[0]
        self.assertLess(
            close_handler.index("virtualKeyboardRef.active = false"),
            close_handler.index("closingWindow.destroy()"),
        )
        self.assertIn("Qt.callLater(function()", close_handler)
        self.assertLess(
            close_handler.index("closingWindow.visible = false"),
            close_handler.index("closingWindow.destroy()"),
        )
        installer = (RELEASE / "install.sh").read_text()
        self.assertIn("qt-resource-rebuilder", installer)

    def test_hub_exposes_click_targets(self):
        qml = (RELEASE / "payload/apps/paperdesk/ui/main.qml").read_text()
        for name in ("terminalButton", "webButton", "rdpButton", "rssButton"):
            self.assertIn(f'objectName: "{name}"', qml)
        self.assertNotIn("closeAfterLaunch", qml)

    def test_every_product_action_has_a_stable_test_target(self):
        apps = RELEASE / "payload/apps"
        expected = {
            "paperterminal": (
                "terminalCloseButton", "terminalKeyboardButton",
                "terminalMouseButton",
                "terminalShortcutsButton", "terminalShortcut_",
                "terminalModifierCtrl", "terminalModifierAlt",
                "terminalShortcutKeysTab", "terminalShortcutFunctionTab",
                "terminalDisplayButton", "terminalDisplayHighContrast",
                "terminalDisplayAnsi", "terminalDisplaySmaller",
                "terminalDisplayLarger", "terminalDisplayRefresh",
            ),
            "paperweb": (
                "webBackButton", "webReloadButton", "webCloseButton",
                "webAddressInput", "webGoButton", "webZoomOutButton",
                "webZoomInButton",
            ),
            "paperrdp-login": (
                "rdpCloseButton", "rdpKeyboardButton", "serverInput",
                "usernameInput", "passwordInput", "portInput", "connectButton",
                "rdpRememberPasswordButton",
                "rdpSavedProfilesList", "rdpSavedProfileButton_",
                "rdpProfileNewButton", "rdpProfileCancelButton",
                "rdpProfileSaveButton",
                "rdpProfileEditButton", "rdpProfileDeleteButton",
                "rdpDeleteConfirmation", "rdpDeleteCancelButton",
                "rdpDeleteConfirmButton",
                "rdpScaleButton_", "rdpColorDepthButton_",
            ),
            "paperrss": (
                "rssRefreshButton", "rssAddFeedViewButton", "rssCloseButton",
                "rssAllArticlesButton", "rssDeleteFeedButton_", "readerTouch",
                "rssBackButton",
                "rssCancelAddButton", "rssAddButton", "rssFeedNameInput",
                "rssFeedUrlInput",
            ),
            "papercare": (
                "careCheckButton", "careInstallButton", "careCloseButton",
            ),
            "paperdots": (
                "dotsCloseButton", "dotsBoard", "dotsNewButton", "dotsUndoButton",
                "dotsPauseButton", "dotsDialogCancelButton", "dotsStartButton",
                "dotsSmallBoardButton", "dotsLargeBoardButton", "dotsExtraBoardButton",
                "dotsRelaxedButton", "dotsTacticalButton", "dotsPlayer1Picker", "dotsPlayer2Picker",
            ),
        }
        for app_name, targets in expected.items():
            qml = "\n".join(path.read_text() for path in
                            sorted((apps / app_name / "ui").glob("*.qml")))
            for target in targets:
                self.assertIn(target, qml, f"{app_name}: missing action target {target}")
        self.assertNotIn('objectName: "rssFavouriteButton"',
                         (apps / "paperrss/ui/main.qml").read_text())
        web = (apps / "paperweb/ui/main.qml").read_text()
        self.assertNotIn('objectName: "webDownloadButton"', web)
        self.assertNotIn('objectName: "webDownloadsButton"', web)

    def test_product_menus_use_touch_native_consistent_controls(self):
        apps = RELEASE / "payload/apps"
        terminal = (apps / "paperterminal/ui/main.qml").read_text()
        rdp = (apps / "paperrdp-login/ui/main.qml").read_text()
        web = (apps / "paperweb/ui/main.qml").read_text()
        rss = (apps / "paperrss/ui/main.qml").read_text()
        self.assertIn("readonly property int toolbarButtonWidth: 176", terminal)
        self.assertIn("anchors.right: keyboardButton.left", terminal)
        self.assertIn("anchors.right: mouseButton.left", terminal)
        self.assertIn("anchors.leftMargin: 24", terminal)
        self.assertIn("readonly property int toolbarButtonWidth: 176", rdp)
        self.assertIn("readonly property int toolbarButtonHeight: 76", rdp)
        self.assertIn("readonly property int actionFontPointSize: 16", rdp)
        self.assertNotIn("MouseArea {", terminal)
        self.assertNotIn("MouseArea {", web)
        self.assertNotIn("MouseArea {", rss)
        self.assertNotIn("\n                Button {", web)
        self.assertNotIn("\n                    Button {", rss)

    def test_editorial_eink_design_system_is_present_in_every_app(self):
        apps = RELEASE / "payload/apps"
        qml = {
            name: (apps / name / "ui/main.qml").read_text()
            for name in ("paperdesk", "paperterminal", "paperweb", "paperrdp-login", "paperrss", "papercare")
        }
        self.assertIn("PAPERDESK  /  E-INK WORKSPACE", qml["paperdesk"])
        for name in ("paperterminal", "paperweb", "paperrdp-login", "paperrss", "papercare"):
            self.assertIn("PAPERDESK  /", qml[name], name)
            self.assertIn("radius: 8", qml[name], name)
        self.assertIn("var commonCss", qml["paperweb"])
        self.assertIn("var compactCss", qml["paperweb"])
        self.assertIn("var computerCss", qml["paperweb"])
        self.assertIn("body *{color:#000!important", qml["paperweb"])
        self.assertIn("font.bold: false", qml["paperrss"])
        self.assertIn("width: Math.min(parent.width - 180, 1040)", qml["paperrdp-login"])

    def test_app_icons_share_one_eink_system_and_terminal_is_paper_terminal(self):
        apps = RELEASE / "payload/apps"
        visible = ("paperterminal", "paperweb", "paperrdp-login", "paperrss", "papercare", "paperdots")
        for name in visible:
            icon = (apps / name / "icon.png").read_bytes()
            self.assertTrue(icon.startswith(b"\x89PNG\r\n\x1a\n"), name)
            self.assertEqual(int.from_bytes(icon[16:20], "big"), 256, name)
            self.assertEqual(int.from_bytes(icon[20:24], "big"), 256, name)
            source = (apps / name / "assets/icon.svg").read_text()
            self.assertIn('x="12" y="12" width="232" height="232" rx="34"', source, name)
            self.assertIn('stroke-width="14"', source, name)
            self.assertNotIn("<text", source, name)

        manifest = json.loads((apps / "paperterminal/manifest.json").read_text())
        self.assertEqual(manifest["name"], "Paper Terminal")
        terminal = (apps / "paperterminal/ui/main.qml").read_text()
        self.assertIn('text: "Paper Terminal"', terminal)

    def test_release_documents_tested_firmware_and_extension_versions(self):
        readme = (RELEASE / "README.md").read_text()
        self.assertIn("3.29.0.149", readme)
        self.assertIn("AppLoad 0.6.0", readme)
        self.assertIn("No LiTerm app or global terminal extension is required.", readme)
        release = json.loads((RELEASE / "release.json").read_text())
        self.assertEqual(date.fromisoformat(release["releaseDate"]).isoformat(), release["releaseDate"])
        feed = json.loads((ROOT / "website/update/stable.json").read_text())
        self.assertEqual(release["releaseDate"], feed["publishedAt"])
        self.assertTrue((RELEASE / "CHANGELOG.md").read_text().startswith(
            f'# {release["version"]} — {release["releaseDate"]}\n'))
        self.assertEqual(release["testedWith"]["remarkableOS"], "3.29.0.149")
        self.assertEqual(release["testedWith"]["appLoad"], "0.6.0")
        self.assertNotIn("liTerm", release["testedWith"])

    def test_terminal_backend_is_self_contained_in_the_app(self):
        app = RELEASE / 'payload/apps/paperterminal'
        manifest = json.loads((app / 'manifest.json').read_text())
        self.assertEqual(manifest['id'], 'paperterminal')
        self.assertEqual(manifest['name'], 'Paper Terminal')
        self.assertFalse((RELEASE / 'payload/apps/literm').exists())
        self.assertIn('plugin paperterminal_native', (app / 'native/qmldir').read_text())
        for filename in ('libpaperterminal_native.so', 'paperterminal-askpass'):
            binary = (app / 'native' / filename).read_bytes()
            self.assertEqual(binary[:6], b'\x7fELF\x01\x01')
            self.assertEqual(binary[18:20], b'\x28\x00')
        qml = (app / 'ui/main.qml').read_text()
        self.assertIn('import "../native"', qml)
        self.assertNotIn('import literm', qml)
        installer = (RELEASE / 'install.sh').read_text()
        self.assertIn('native/libpaperterminal_native.so', installer)
        self.assertIn('native/paperterminal-askpass', installer)
        prep = (ROOT / 'windows/prepare_tablet.py').read_text()
        self.assertNotIn('github.com/asivery/rm-literm', prep)
        self.assertNotIn('appload.so literm.so;', prep)
        preflight = (ROOT / 'windows/preflight.py').read_text()
        self.assertNotIn("problem 'LiTerm", preflight)

    def test_installer_records_the_packaged_version(self):
        installer = (RELEASE / "install.sh").read_text()
        self.assertIn('VERSION=$(tr -d \'\\r\\n\' < "$SCRIPT_DIR/VERSION")', installer)
        self.assertNotIn('VERSION="1.1.4"', installer)
        self.assertNotIn("profiles.example", installer)
        self.assertIn("rmssh-profiles", installer)
        self.assertIn("rmssh-hosts", installer)
        self.assertFalse((RELEASE / "payload/system/profiles.example").exists())

    def test_care_displays_the_packaged_version(self):
        version = (RELEASE / "VERSION").read_text().strip()
        care = (RELEASE / "payload/apps/papercare/ui/main.qml").read_text()
        self.assertIn(f'readonly property string currentVersion: "{version}"', care)

    def test_appload_06_accepts_an_unset_aspect_ratio(self):
        qml = (RELEASE / "payload/system/paperdesk-appload.qml").read_text()
        self.assertIn(
            "if(!isFinite(realAspectRatio) || realAspectRatio <= 0)",
            qml,
        )

    def test_appload_keyboard_button_is_geometrically_centered_and_contextual(self):
        qml = (RELEASE / "payload/system/paperdesk-appload-window.qml").read_text()
        button = qml.split('objectName: "paperdeskKeyboardButton"', 1)[1]
        button = button.split("MouseArea {", 1)[0]
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", button)
        self.assertIn("width: 210", button)
        self.assertIn("radius: 8", button)
        self.assertIn("border.width: 2", button)
        self.assertIn("virtualKeyboardLayout !== null", button)
        self.assertNotIn("x:", button)

    def test_legacy_xovi_autostart_is_removed_without_touching_user_services(self):
        self.assertFalse((RELEASE / "payload/system/xovi-autostart.service").exists())
        installer = (RELEASE / "install.sh").read_text()
        self.assertNotIn("systemctl enable xovi-autostart.service", installer)
        self.assertIn('grep -Fxq \'Description=Start Xovi extensions after the reMarkable interface\'', installer)
        self.assertIn("legacy-autostart-removed", installer)
        self.assertIn('if [ -f "$STATE/current-version" ]', installer)
        self.assertIn('systemd-run --unit="paperdesk-remove-legacy-autostart-$$"', installer)
        self.assertLess(
            installer.index("systemctl disable xovi-autostart.service"),
            installer.index("paperdesk-remove-legacy-autostart-$$"),
        )
        uninstaller = (RELEASE / "uninstall.sh").read_text()
        self.assertNotIn("xovi-autostart.service", uninstaller)

    def test_updater_requires_signed_and_hashed_official_packages(self):
        system = RELEASE / "payload/system"
        agent = (system / "paperdesk-update-agent").read_text()
        care = (RELEASE / "payload/apps/papercare/ui/main.qml").read_text()
        official_url = "https://paperdesk.lukaszbabut.info"
        self.assertIn(f'{official_url}/update/stable.json', care)
        self.assertIn(f"PAPERDESK_UPDATE_BASE_URL:-{official_url}", agent)
        self.assertNotIn("192.168.1.40:8090", care)
        self.assertNotIn("192.168.1.40:8090", agent)
        self.assertIn("openssl pkeyutl -verify -rawin -pubin", agent)
        self.assertIn("sha256sum -c -", agent)
        self.assertIn("sha256sum -c SHA256SUMS", agent)
        self.assertIn("version_is_newer", agent)
        self.assertIn("52428800", agent)
        self.assertIn("The update size does not match", agent)
        self.assertIn('systemd-run --unit="paperdesk-xovi-reload-$$"', agent)
        self.assertIn("--on-active=2s", agent)
        self.assertNotIn("restart xovi-autostart.service", agent)
        self.assertIn("^/download/paperdesk-", agent)
        self.assertNotIn("eval ", agent)
        self.assertTrue((system / "paperdesk-release-public.pem").is_file())
        installer = (RELEASE / "install.sh").read_text()
        self.assertIn("systemctl enable --now paperdesk-update.path", installer)
        self.assertIn("paperdesk-update-agent", installer)
        self.assertIn("TriggerLimitIntervalSec=0", (system / "paperdesk-update.path").read_text())
        self.assertIn("StartLimitIntervalSec=0", (system / "paperdesk-update.service").read_text())

    def test_usb_management_code_is_local_and_never_copied(self):
        installer = (RELEASE / "install-from-computer.sh").read_text()
        self.assertIn("paperdesk.local.conf", installer)
        self.assertIn("--exclude='./paperdesk.local.conf'", installer)
        self.assertIn("SSH_ASKPASS_REQUIRE=force", installer)
        self.assertNotIn("sshpass", installer)
        self.assertIn("USB_MANAGEMENT_CODE=", (RELEASE / "paperdesk.conf.example").read_text())

    def test_rdp_engine_cannot_fall_back_to_legacy_login(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn(
            "if(!autoConnect && !app.profile.host.empty() && !app.profile.user.empty())",
            source,
        )
        self.assertIn('drawError(app,"OPEN PAPERDESK AND CHOOSE RDP")', source)
        self.assertNotIn("else drawLogin(app,true);", source)

    def test_rdp_coalesces_bands_and_skips_unchanged_pixels(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("burstSettled", source)
        self.assertIn("maxLatencyReached", source)
        self.assertIn("largeFrame", source)
        self.assertIn("DAMAGE_TILE_COUNT", source)
        self.assertIn("constexpr int DAMAGE_TILE_W = 88", source)
        self.assertIn("constexpr int SPARSE_FRAME_MIN_GAP_MS = 80", source)
        self.assertIn("constexpr int DENSE_FRAME_MIN_GAP_MS = 700", source)
        self.assertIn("changedTileCount>DAMAGE_TILE_COUNT/3", source)
        self.assertIn("a.update(0,BAR_H,W,RDP_H)", source)
        self.assertIn("physicalRect(profile.landscape,logical)", source)
        self.assertIn("next-row<2", source)
        self.assertIn("if(*out!=pixel)", source)
        self.assertIn("merged.x2-merged.x1,merged.y2-merged.y1", source)
        self.assertIn("sourceX[dx]", source)
        self.assertIn("sourceY[dy]", source)
        self.assertIn("CLEAN_REFRESH_IDLE_MS = 4500", source)
        self.assertIn("CLEAN_REFRESH_MIN_GAP_MS = 15000", source)
        self.assertIn("now-a.lastDirty<std::chrono::milliseconds(CLEAN_REFRESH_IDLE_MS)", source)

    def test_rdp_event_storm_has_a_per_turn_budget(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("packetBudget<64", source)

    def test_native_rdp_chrome_cannot_open_obsolete_bitmap_toolbar(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        start = source.index("void processRemoteTouch(App& a,int x,int y)")
        self.assertIn("if(a.launchedFromNativeLogin && y<BAR_H) return;", source[start:start+400])

    def test_rdp_profiles_scale_and_color_depth_are_end_to_end(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        login = (RELEASE / "payload/apps/paperrdp-login/ui/main.qml").read_text()
        for value in ("scale_percent", "color_depth", "--scale-percent", "--color-depth", "--domain-hex"):
            self.assertIn(value, source)
            self.assertIn(value, login)
        manager = (RELEASE / "payload/apps/paperrdp-profile/profile-manager").read_text()
        # Connecting persists only the last connection. Explicit GUI Save/Delete
        # owns the bounded saved list, preventing native writes racing its lock.
        save_profile = source.split("bool saveProfile(const Profile& p) {", 1)[1].split(
            "void loadProfile(Profile& p)", 1
        )[0]
        self.assertIn('profilePath=directory+"/profile"', save_profile)
        self.assertIn("return writePrivateFile(path,temp,data)", save_profile)
        self.assertNotIn('directory+"/profiles"', save_profile)
        self.assertNotIn("profilesPath", save_profile)
        self.assertNotIn("listData", save_profile)
        self.assertIn('PROFILES="$CONFIG_DIR/profiles"', manager)
        self.assertIn('LOCK="$CONFIG_DIR/.profile-manager.lock"', manager)
        self.assertIn('mkdir "$LOCK"', manager)
        self.assertIn('"$EXPECTED" != "$CURRENT_REVISION"', manager)
        self.assertIn("++count>8", manager)
        self.assertIn("kept++<7", manager)
        self.assertIn('chmod 0600 "$TMP" && sync && mv "$TMP" "$PROFILES"', manager)
        self.assertIn("paperrdp-profile", (RELEASE / "install.sh").read_text())
        self.assertIn("paperrdp-profile", (RELEASE / "uninstall.sh").read_text())
        self.assertIn('return ["--save", String(index)', login)
        self.assertIn('return ["--delete", String(index)]', login)
        self.assertIn('String(scalePercent), String(colorDepth), orientation, "v2"', login)
        self.assertIn('"external::paperrdp-profile"', login)
        self.assertIn('"Confirm delete"', login)
        self.assertIn('flickableDirection: Flickable.VerticalFlick', login)
        self.assertNotIn('rdpProfileOpenButton', login)
        self.assertIn('root.editorMode === "edit" ? "Save changes" : "Save new profile"', login)
        self.assertIn('visible: root.editorMode === ""', login)
        self.assertIn('readOnly: root.editorMode === ""', login)
        self.assertIn("property bool rememberPassword: true", login)
        self.assertIn('rememberPassword ? passwordInput.text : ""', login)
        self.assertIn("0600", source)
        self.assertIn("sessionWidth=static_cast<UINT32>(W*a.profile.scalePercent/100)", source)
        self.assertIn("sessionHeight=static_cast<UINT32>(RDP_H*a.profile.scalePercent/100)", source)
        self.assertIn("FreeRDP_ColorDepth,a.profile.colorDepth", source)
        self.assertIn("FreeRDP_AllowUnanouncedOrdersFromServer,TRUE", source)
        self.assertIn("const int rx=remoteX(a,x)", source)
        self.assertIn("const int ry=remoteY(a,y)", source)
        self.assertIn("outputScaleX(a)", source)
        self.assertNotIn("FreeRDP_DesktopScaleFactor", source)
        for flag in (
            "FreeRDP_DisableWallpaper", "FreeRDP_AllowFontSmoothing",
            "FreeRDP_DisableFullWindowDrag", "FreeRDP_DisableMenuAnims",
            "FreeRDP_DisableThemes", "FreeRDP_AllowDesktopComposition",
        ):
            self.assertIn(flag, source)
        self.assertIn("Lower values are faster", login)

    def test_rdp_touch_mouse_gestures_are_explicit(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("beginDoubleTap", source)
        self.assertIn("flushDoubleClickSecond", source)
        self.assertIn("PaperDesk RDP double click", source)
        self.assertIn("std::chrono::milliseconds(500)", source)
        self.assertIn("std::chrono::milliseconds(90)", source)
        self.assertIn("sendRemoteClick(a,x,y)", source)
        self.assertIn("sendRemoteClick(a,a.doubleClickX,a.doubleClickY)", source)
        self.assertIn("a.doubleClickX=a.pendingTapX", source)
        self.assertIn("maybeSendLongPress", source)
        self.assertIn("PTR_FLAGS_BUTTON2", source)
        self.assertIn("std::chrono::milliseconds(700)", source)
        zoomed_press = source.split(
            "if(press && a.touches.size()==1 && u.y>=BAR_H && a.zoom>1.001f)", 1
        )[1].split("if(press && a.touches.size()==2)", 1)[0]
        self.assertIn("a.mouseStartX=float(u.x)", zoomed_press)
        self.assertIn("a.mouseStartY=float(u.y)", zoomed_press)
        runner = (ROOT / "tests/run-tablet-e2e.sh").read_text()
        self.assertIn("hold 1160 1460 850", runner)
        self.assertIn("wait_for_log 'PaperDesk RDP right click'", runner)
        self.assertIn("rdp-doubleclick)", runner)
        self.assertIn("tap 800 900", runner)

    def test_rdp_gestures_publish_only_the_final_frame(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        pan_block = source.split("if(a.panActive) {", 1)[1].split("}", 1)[0]
        self.assertNotIn("redrawZoomedView", pan_block)
        self.assertIn("else if(finishPan) redrawZoomedView(a);", source)

    def test_rdp_native_header_uses_the_product_action_style(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("constexpr int BAR_H = 112;", source)
        self.assertIn("constexpr int ACTION_H = 68;", source)
        self.assertIn("constexpr int CLOSE_W = 176;", source)
        self.assertIn("constexpr int scale = 3;", source)
        self.assertIn('text(a,28,18,"PAPERDESK / REMOTE ACCESS",2,255);', source)
        self.assertIn("roundedFill(a,x,y,w,h,radius,0);", source)
        self.assertNotIn("label.size() > 8", source)

    def test_rdp_maps_both_return_and_enter(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("{0x01000004,0x1c}", source)
        self.assertIn("{0x01000005,0x1c}", source)

    def test_rdp_normalises_special_keys_from_every_keyboard_path(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        normalizer = source.split("uint32_t specialKeyToScan(int key) {", 1)[1].split(
            "BOOL sendKeyPacket", 1
        )[0]
        for key in (
            "0x01000003", "0xff08", "0x08", "0x7f",
            "0x01000004", "0x01000005", "0xff0d", "0x0a", "0x0d",
            "0x01000001", "0xff09", "0x09", "0x01000007", "0xffff",
            "0x01000010", "0xff50", "0x01000011", "0xff57",
            "0x01000012", "0xff51", "0x01000013", "0xff52",
            "0x01000014", "0xff53", "0x01000015", "0xff54",
            "0x01000016", "0xff55", "0x01000017", "0xff56",
        ):
            self.assertIn(f"case {key}:", normalizer)
        self.assertIn("remoteInputKey(a,u.x,true)", source)
        self.assertIn("remoteInputKey(a,u.x,false)", source)
        dispatch = source.split("void remoteInputKey(App& a,int rawKey,bool down) {", 1)[1].split(
            "void sendChord", 1
        )[0]
        # Bare Qt/X11 navigation goes through the physical-key normalizer.
        # Tagged Unicode normalizes only C0/DEL, preserving printable U+FFxx
        # characters whose codepoints happen to equal X11 keysyms.
        self.assertIn("if(handleClientCommand(a,rawKey,down)) return", dispatch)
        self.assertIn("if(a.mode!=Mode::Remote) return", dispatch)
        self.assertIn("if(encodedUnicode)", dispatch)
        self.assertIn("if((key<0x20 || key==0x7f) && specialKeyToScan(key)) remoteKey(a,key,down)", dispatch)
        self.assertIn("else if(down) sendUnicode(a,static_cast<uint16_t>(key))", dispatch)
        self.assertNotIn("if(specialKeyToScan(key))", dispatch)
        physical = source.split("void remoteKey(App& a,int key,bool down) {", 1)[1].split(
            "void sendUnicode", 1
        )[0]
        self.assertIn("uint32_t scan=specialKeyToScan(key)", physical)
        self.assertIn("if(!scan) scan=qtToScan(key)", physical)
        self.assertIn("sendKeyPacket(a.rdp->context->input,down,scan)", physical)
        packet = source.split("BOOL sendKeyPacket(rdpInput* input,BOOL down,UINT32 scan) {", 1)[1].split(
            "BOOL sendMousePacket", 1
        )[0]
        self.assertIn("RDP_SCANCODE_EXTENDED(scan) ? KBD_FLAGS_EXTENDED : 0", packet)
        self.assertIn("down ? 0 : KBD_FLAGS_RELEASE", packet)
        self.assertIn("freerdp_input_send_keyboard_event(input,flags,RDP_SCANCODE_CODE(scan))", packet)
        chord = source.split("void sendChord(App& a,", 1)[1].split("void sendShortcut(App& a,int index) {", 1)[0]
        self.assertIn("MAKE_RDP_SCANCODE(key.first,key.second)", chord)
        self.assertIn("MAKE_RDP_SCANCODE(it->first,it->second)", chord)
        self.assertNotIn("freerdp_input_send_keyboard_event_ex", chord)

    def test_rss_full_text_has_dedicated_touch_scroller(self):
        qml = (RELEASE / "payload/apps/paperrss/ui/main.qml").read_text()
        self.assertIn('objectName: "rssReaderCloseButton"', qml)
        self.assertIn('objectName: "readerTouch"', qml)
        self.assertIn('objectName: "readerFlick"', qml)
        self.assertIn("MultiPointTouchArea", qml)
        self.assertIn("readerFlick.contentY = Math.max", qml)
        self.assertIn("interactive: false", qml)
        self.assertIn("signal fullTextRequested(string url)", qml)
        self.assertIn("if (currentArticle.fullText)", qml)
        self.assertIn("Qt.callLater(function()", qml)
        self.assertIn("articles[i].fullText = true", qml)
        self.assertNotIn('objectName: "rssFullTextButton"', qml)
        runner = (ROOT / "tests/run-tablet-e2e.sh").read_text()
        self.assertIn("rss-auto-full)", runner)
        self.assertIn("PaperRSS full text request https://example.com", runner)

    def test_rss_never_loads_internal_or_qrc_links_as_articles(self):
        qml = (RELEASE / "payload/apps/paperrss/ui/main.qml").read_text()
        self.assertIn("function resolveHttpUrl(value, baseUrl)", qml)
        self.assertIn("function looksLikeApplicationSource(value)", qml)
        self.assertIn("function repairUnsafeCachedArticles()", qml)
        self.assertIn("function applyFullArticleResponse(html, sourceUrl, articleId, articleTitle, persist)", qml)
        self.assertIn("PaperRSS blocked non-web article link", qml)
        self.assertIn("PaperRSS blocked application source response", qml)
        self.assertNotIn("currentArticle.link = link", qml)

    def test_rss_parser_bounds_large_feeds_for_tablet_watchdog(self):
        qml = (RELEASE / "payload/apps/paperrss/ui/main.qml").read_text()
        self.assertIn("readonly property int feedItemLimit: 12", qml)
        self.assertIn("readonly property int feedBodyLimit: 12000", qml)
        self.assertIn("blocks.length < feedItemLimit", qml)
        self.assertIn("body = body.substring(0, feedBodyLimit)", qml)
        self.assertIn("PaperRSS E2E stress parser ready", qml)
        self.assertIn("pendingArticles = pendingArticles.concat(parsed)", qml)
        self.assertIn("function finishFeed(xhr, generation, feed, timedOut)", qml)
        self.assertIn("generation !== refreshGeneration", qml)
        self.assertIn("if (!selectedFeedUrl || candidate.url === selectedFeedUrl)", qml)
        self.assertIn("if (disposed || !xhr || xhr !== feedRequest", qml)
        self.assertIn("PaperRSS refresh complete", qml)

    def test_tablet_user_journey_covers_every_application_and_health(self):
        runner = (ROOT / "tests/run-tablet-e2e.sh").read_text()
        self.assertIn("journey)", runner)
        for label in ("Terminal journey", "Web journey", "RDP journey", "RSS journey"):
            self.assertIn(label, runner)
        self.assertIn("assert_tablet_healthy", runner)
        self.assertIn("Watchdog timeout|Main process exited|Failed with result", runner)
        self.assertIn("PaperRSS E2E stress parser ready 12", runner)
        self.assertIn("PaperRSS refresh complete 1 0", runner)
        self.assertIn("live Physics World refresh", runner)
        self.assertIn('cp -p /tmp/paperdesk-e2e-xochitl.conf /home/root/.config/remarkable/xochitl.conf', runner)
        self.assertNotIn("paperdesk-e2e-clean.conf", runner)
        self.assertIn('[[ "$TABLET_SETUP_STARTED" == "1" ]] || return 0', runner)
        self.assertIn("web-live-wp)", runner)
        self.assertIn("web-file-blocked)", runner)
        self.assertIn("PaperWeb file download blocked", runner)
        self.assertIn("PaperWeb HTML reader items", runner)
        self.assertIn("web-live-dynamic)", runner)
        self.assertIn("PaperWeb embedded reader items", runner)
        self.assertIn("care)", runner)
        self.assertIn("PaperDesk Care action check", runner)
        self.assertIn("rdpProfileCrud=true", runner)
        self.assertIn("PaperDesk RDP E2E new profile prepared", runner)
        self.assertIn("PaperDesk RDP E2E profile edit prepared", runner)
        self.assertIn("RDP New, Cancel, Save, Edit, confirmed Delete, and Connect", runner)
        self.assertIn("PaperDesk Terminal keyboard hidden", runner)
        self.assertIn("keyboard hide/show", runner)
        self.assertIn("LOG_EXPECTED", runner)

    def test_web_keyboard_is_contextual(self):
        qml = (RELEASE / "payload/apps/paperweb/ui/main.qml").read_text()
        gained_focus = qml.split("function gainedFocus()", 1)[1].split("property var request", 1)[0]
        self.assertNotIn("address.forceActiveFocus()", gained_focus)
        self.assertIn("function dismissKeyboard()", qml)
        self.assertIn("function selectAddressForEditing()", qml)
        self.assertIn("function finishAddressSelection()", qml)
        self.assertIn("address.selectAll()", qml)
        self.assertIn("Qt.callLater(finishAddressSelection)", qml)
        self.assertIn("PaperWeb address selection stable", qml)
        self.assertIn("PaperWeb address selected", qml)
        self.assertIn("selectByMouse: false", qml)
        self.assertIn("persistentSelection: true", qml)
        self.assertIn("onTapped: root.selectAddressForEditing()", qml)
        self.assertIn("PaperWeb keyboard opened", qml)
        self.assertIn("PaperWeb keyboard hidden", qml)
        self.assertIn("onPressed: function(points) {\n                    root.dismissKeyboard()", qml)

    def test_terminal_native_view_replaces_qml_refresh_workarounds(self):
        qml = (RELEASE / "payload/apps/paperterminal/ui/main.qml").read_text()
        menu = (RELEASE / "payload/system/rmssh-menu").read_text()
        self.assertIn('Native.TerminalView {', qml)
        self.assertIn('Component.onCompleted: { start(); forceActiveFocus() }', qml)
        self.assertIn('terminal.stop()', qml)
        self.assertNotIn('terminalContent.opacity', qml)
        self.assertNotIn('id: screenRefreshTimer', qml)
        self.assertNotIn('id: startupRefreshTimer', qml)
        self.assertIn('displayMethod: DisplayMethodArea.Fast', qml)
        self.assertIn("PaperDesk Terminal display changed", qml)
        # The start screen gives saved profiles the full viewport.
        # Opening a session or the Keyboard button requests the input method.
        self.assertNotIn("id: startupKeyboardTimer", qml)
        self.assertIn("function toggleSystemKeyboard()", qml)
        self.assertIn("function hideSystemKeyboard()", qml)
        self.assertIn('text: Qt.inputMethod.visible ? "Hide keyboard" : "Keyboard"', qml)
        self.assertIn("onTapped: root.toggleSystemKeyboard()", qml)
        self.assertIn("function calculateKeyboardInset", qml)
        self.assertIn("var safeFallback = viewHeight * 0.38", qml)
        self.assertIn('root.refreshTerminal("keyboard hidden")', qml)
        self.assertIn("New connection", menu)
        self.assertNotIn('PROFILES=', menu)
        self.assertNotIn('HOST_ALIASES=', menu)
        self.assertNotIn("show_profiles", menu)
        self.assertNotIn("open_numbered_profile", menu)
        self.assertNotIn("resolve_host_alias", menu)
        self.assertNotIn("Save this connection", menu)
        self.assertNotIn("Advanced connection", menu)
        self.assertNotIn("advanced_connect", menu)

    def test_terminal_mouse_mode_is_explicit_bounded_and_session_only(self):
        qml = (RELEASE / "payload/apps/paperterminal/ui/main.qml").read_text()
        self.assertIn('property bool mouseMode: true', qml)
        self.assertIn('objectName: "terminalMouseButton"', qml)
        self.assertIn('mouseMode = false', qml.split("function unloading()", 1)[1].split("}", 1)[0])
        self.assertIn('terminal.sendMouse(column, row, button)', qml)
        self.assertIn('root.sendMouseClick(points[i].x, points[i].y, 0)', qml)
        self.assertIn('root.sendMouseClick(terminalTouch.mouseStartX, terminalTouch.mouseStartY, 2)', qml)
        self.assertIn('terminalTouch.activePoint === -1', qml)
        self.assertIn('terminalTouch.rightClickSent = true', qml)
        self.assertIn('interval: 700', qml)
        self.assertNotIn('property bool savedMouseMode', qml)

    def test_terminal_display_modes_are_optional_persistent_and_high_contrast_by_default(self):
        qml = (RELEASE / "payload/apps/paperterminal/ui/main.qml").read_text()
        self.assertIn("property bool savedAnsiColors: false", qml)
        self.assertIn("property real savedFontSize:", qml)
        self.assertIn('target: "terminalDisplayHighContrast"', qml)
        self.assertIn('target: "terminalDisplayAnsi"', qml)
        self.assertIn('ansiColors: root.ansiColors', qml)
        self.assertIn("terminalSettings.savedFontSize = root.terminalFontSize", qml)

    def test_web_requests_mobile_documents_by_default(self):
        qml = (RELEASE / "payload/apps/paperweb/ui/main.qml").read_text()
        self.assertIn("property bool mobileMode: webSettings.savedMobileMode", qml)
        self.assertIn('objectName: "webViewModeButton"', qml)
        self.assertIn('objectName: "webBackButton"\n                    label: ""\n                    iconName: "back"', qml)
        self.assertIn('objectName: "webReloadButton"\n                    label: ""\n                    iconName: "reload"', qml)
        self.assertIn('objectName: "webPicturesButton"', qml)
        self.assertIn('property bool savedMobileMode: true', qml)
        self.assertIn('property bool savedShowPictures: false', qml)
        self.assertIn('PaperWeb view mode", root.mobileMode ? "mobile" : "computer"', qml)
        self.assertIn('xhr.setRequestHeader("User-Agent", mobileUserAgent)', qml)
        self.assertIn('xhr.setRequestHeader("Accept", "text/html', qml)
        self.assertIn('PaperWeb request profile", mobileMode ? "mobile"', qml)
        self.assertIn("function usablePageResponse(status, value)", qml)
        self.assertIn("function shouldRetryPageRequest(status, attempt)", qml)
        self.assertIn('objectName: "webNavigationRetryTimer"', qml)
        self.assertIn("Qt.callLater(restoreLastAddress)", qml)
        self.assertIn('if (shouldUseCompactReader(source)) {\n            done("")', qml)
        self.assertIn("function shouldUseCompactReader(source)", qml)
        reader_choice = qml.split("function shouldUseCompactReader(source)", 1)[1].split("function pageReaderTitle", 1)[0]
        self.assertIn("if (mobileMode)", reader_choice)
        self.assertIn("applicationShell", reader_choice)
        self.assertIn('"computer page"', qml)
        self.assertIn("compactLayout ? compactCss : computerCss", qml)
        self.assertIn('html.replace(/\\sstyle\\s*=', qml)
        self.assertIn("max-width:100%!important", qml)
        self.assertIn("column-count:1!important", qml)
        self.assertIn("grid-template-columns:1fr!important", qml)
        self.assertIn("function htmlStoryReader(source, finalUrl)", qml)
        self.assertIn("function embeddedFeedReader(source, finalUrl)", qml)
        self.assertIn("function articleDocumentReader(source, finalUrl)", qml)
        self.assertIn("function stripTechnicalBlocks(value)", qml)
        self.assertIn("function decodeHtmlEntities(value)", qml)
        self.assertIn("function repairUtf8Mojibake(value)", qml)
        self.assertIn("html = stripTechnicalBlocks(html)", qml)
        self.assertIn("PaperWeb article reader JSON", qml)
        self.assertIn("PaperWeb link activated", qml)
        self.assertIn("function linkAtViewport(x, y)", qml)
        self.assertIn("application\\/(?:ld\\+)?json", qml)
        self.assertIn("paper-story", qml)
        self.assertIn("PaperWeb embedded reader items", qml)
        self.assertIn('PaperWeb pictures", root.showPictures ? "shown" : "hidden"', qml)
        self.assertIn("pictureCount >= 12", qml)
        self.assertIn("images.weserv.nl", qml)
        self.assertIn("e2eSettings.scenarioVersion === 20260927 && e2eSettings.webFixture", qml)

    def test_web_downloads_use_bounded_worker_and_native_import(self):
        apps = RELEASE / "payload/apps"
        system = RELEASE / "payload/system"
        qml = (apps / "paperweb/ui/main.qml").read_text()
        self.assertNotIn("AppLoadLauncher", qml)
        self.assertNotIn('"external::paperweb-download"', qml)
        self.assertNotIn('category: "PaperWebDownload"', qml)
        self.assertNotIn('objectName: "webDownloadsButton"', qml)
        self.assertNotIn("function startDownload", qml)
        self.assertNotIn("function showDownloads", qml)
        self.assertNotIn("download-status", qml)
        self.assertIn("function showUnsupportedDownload", qml)
        self.assertIn("My files supports PDF and EPUB", qml)
        panel = (apps / "paperweb/ui/NativeDownload.qml").read_text()
        self.assertIn("importFromUrls", panel)
        self.assertIn("67108864", panel)
        self.assertIn("saved.uncertainToken", panel)
        self.assertIn("Qt.callLater(function()", qml)
        self.assertLess(qml.index("Qt.callLater(function()"), qml.index("xhr.abort()", qml.index("Qt.callLater(function()")))
        self.assertIn("function responseWantsDownload", qml)
        self.assertIn("Content-Disposition", qml)
        self.assertIn("application\\/octet-stream", qml)
        self.assertFalse((system / "paperdesk-download-agent").exists())
        self.assertFalse((system / "paperdesk-download.service").exists())
        self.assertFalse((system / "paperdesk-download.path").exists())
        installer = (RELEASE / "install.sh").read_text()
        uninstaller = (RELEASE / "uninstall.sh").read_text()
        self.assertNotIn("systemctl enable --now paperdesk-download.path", installer)
        self.assertIn("systemctl disable --now paperdesk-download.path", installer)
        self.assertIn('"$TARGET/paperweb-download/web-download"', installer)
        self.assertIn("paperweb-download", uninstaller)

    def test_rss_science_starter_pack_is_non_destructive(self):
        qml = (RELEASE / "payload/apps/paperrss/ui/main.qml").read_text()
        for url in (
            "https://physicsworld.com/feed/",
            "https://www.quantamagazine.org/feed/",
            "https://www.technologyreview.com/feed/",
            "https://www.sciencedaily.com/rss/top/science.xml",
            "https://www.nature.com/nphys.rss",
        ):
            self.assertIn(url, qml)
        self.assertIn("if (!store.scienceStarterAdded)", qml)
        self.assertIn("if (!alreadyPresent)", qml)
        save_state = qml.split("function saveState()", 1)[1].split("function contains", 1)[0]
        self.assertIn("if (e2eScenarioActive() && e2eSettings.rssLongArticle)", save_state)
        self.assertIn("return", save_state)
        self.assertIn("return e2eSettings.traceTouches && e2eSettings.scenarioVersion === 20260927", qml)

    def test_close_is_rightmost_in_every_qml_app_header(self):
        terminal = (RELEASE / "payload/apps/paperterminal/ui/main.qml").read_text()
        rdp_login = (RELEASE / "payload/apps/paperrdp-login/ui/main.qml").read_text()
        self.assertIn('id: closeButton\n            objectName: "terminalCloseButton"\n            anchors.right: parent.right', terminal)
        self.assertIn('anchors.right: closeButton.left', terminal)
        self.assertIn('id: closeButton\n            objectName: "rdpCloseButton"\n            anchors.right: parent.right', rdp_login)
        self.assertIn('anchors.right: closeButton.left', rdp_login)

    def test_release_checksums(self):
        for line in (RELEASE / "SHA256SUMS").read_text().splitlines():
            expected, relative = line.split(maxsplit=1)
            path = RELEASE / relative
            self.assertTrue(path.is_file(), relative)
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(expected, actual, relative)

    def test_qml_is_embedded_in_every_app_resource(self):
        rcc = TOOLCACHE / "qt-rcc-pkg/root/usr/lib/qt5/bin/rcc"
        library = TOOLCACHE / "qt-rcc-pkg/root/usr/lib/x86_64-linux-gnu"
        for app_name in ("paperdesk", "paperterminal", "paperweb", "paperrss", "paperrdp-login", "paperbooks", "paperdots"):
            app_dir = RELEASE / "payload/apps" / app_name
            with tempfile.TemporaryDirectory() as directory:
                rebuilt = pathlib.Path(directory) / "resources.rcc"
                env = {"LD_LIBRARY_PATH": str(library)}
                subprocess.run(
                    [str(rcc), "--binary", str(app_dir / "application.qrc"), "-o", str(rebuilt)],
                    cwd=ROOT,
                    env=env,
                    check=True,
                )
                self.assertEqual(
                    resource_bytes_without_timestamps(app_dir / "resources.rcc"),
                    resource_bytes_without_timestamps(rebuilt),
                    f"{app_name} resources.rcc is stale after editing QML",
                )






if __name__ == "__main__":
    unittest.main()
