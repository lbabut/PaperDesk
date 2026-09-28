import hashlib
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


class PackageRegressionTests(unittest.TestCase):
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
            "literm": (
                "terminalCloseButton", "terminalKeyboardButton",
                "terminalShortcutsButton", "terminalShortcut_",
            ),
            "paperweb": (
                "webBackButton", "webCloseButton",
                "webAddressInput", "webGoButton", "webZoomOutButton",
                "webZoomInButton",
            ),
            "paperrdp-login": (
                "rdpCloseButton", "rdpKeyboardButton", "serverInput",
                "usernameInput", "passwordInput", "portInput", "connectButton",
                "rdpSavedProfilesList", "rdpSavedProfileButton_",
                "rdpScaleButton_", "rdpColorDepthButton_",
            ),
            "paperrss": (
                "rssRefreshButton", "rssAddFeedViewButton", "rssCloseButton",
                "rssAllArticlesButton", "rssDeleteFeedButton_", "readerTouch",
                "rssBackButton", "rssFavouriteButton",
                "rssCancelAddButton", "rssAddButton", "rssFeedNameInput",
                "rssFeedUrlInput",
            ),
            "papercare": (
                "careCheckButton", "careInstallButton", "careCloseButton",
            ),
        }
        for app_name, targets in expected.items():
            qml = (apps / app_name / "ui/main.qml").read_text()
            for target in targets:
                self.assertIn(target, qml, f"{app_name}: missing action target {target}")
        web = (apps / "paperweb/ui/main.qml").read_text()
        self.assertNotIn('objectName: "webDownloadButton"', web)

    def test_product_menus_use_touch_native_consistent_controls(self):
        apps = RELEASE / "payload/apps"
        terminal = (apps / "literm/ui/main.qml").read_text()
        rdp = (apps / "paperrdp-login/ui/main.qml").read_text()
        web = (apps / "paperweb/ui/main.qml").read_text()
        rss = (apps / "paperrss/ui/main.qml").read_text()
        self.assertIn("readonly property int toolbarButtonWidth: 172", terminal)
        self.assertIn("anchors.right: keyboardButton.left", terminal)
        self.assertIn("anchors.leftMargin: 24", terminal)
        self.assertIn("readonly property int toolbarButtonWidth: 176", rdp)
        self.assertIn("readonly property int toolbarButtonHeight: 68", rdp)
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
            for name in ("paperdesk", "literm", "paperweb", "paperrdp-login", "paperrss", "papercare")
        }
        self.assertIn("PAPERDESK  /  E-INK WORKSPACE", qml["paperdesk"])
        for name in ("literm", "paperweb", "paperrdp-login", "paperrss", "papercare"):
            self.assertIn("PAPERDESK  /", qml[name], name)
            self.assertIn("radius: 8", qml[name], name)
        self.assertIn("var paperCss", qml["paperweb"])
        self.assertIn("body *{color:#000!important", qml["paperweb"])
        self.assertIn("font.bold: false", qml["paperrss"])
        self.assertIn("width: Math.min(parent.width - 180, 1040)", qml["paperrdp-login"])

    def test_release_documents_tested_firmware_and_extension_versions(self):
        readme = (RELEASE / "README.md").read_text()
        self.assertIn("3.29.0.149", readme)
        self.assertIn("AppLoad 0.6.0", readme)
        self.assertIn("LiTerm 0.1.7", readme)
        release = json.loads((RELEASE / "release.json").read_text())
        self.assertEqual(release["releaseDate"], "2026-09-28")
        self.assertEqual(release["testedWith"]["remarkableOS"], "3.29.0.149")
        self.assertEqual(release["testedWith"]["appLoad"], "0.6.0")
        self.assertEqual(release["testedWith"]["liTerm"], "0.1.7")

    def test_installer_records_the_packaged_version(self):
        installer = (RELEASE / "install.sh").read_text()
        self.assertIn('VERSION=$(tr -d \'\\r\\n\' < "$SCRIPT_DIR/VERSION")', installer)
        self.assertNotIn('VERSION="1.1.4"', installer)

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
        self.assertIn(f'{official_url}/update/latest.json', care)
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
        self.assertIn("std::chrono::milliseconds(3200)", source)
        self.assertIn("changedTileCount>DAMAGE_TILE_COUNT/3", source)
        self.assertIn("a.fb.sendCompleteUpdate();", source)
        self.assertIn("next-row<2", source)
        self.assertIn("if(*out!=pixel)", source)
        self.assertIn("merged.x2-merged.x1,merged.y2-merged.y1", source)

    def test_rdp_event_storm_has_a_per_turn_budget(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        self.assertIn("packetBudget<64", source)

    def test_rdp_profiles_scale_and_color_depth_are_end_to_end(self):
        source = (RELEASE / "payload/apps/paperrdp/paperrdp.cpp").read_text()
        login = (RELEASE / "payload/apps/paperrdp-login/ui/main.qml").read_text()
        for value in ("scale_percent", "color_depth", "--scale-percent", "--color-depth", "--domain-hex"):
            self.assertIn(value, source)
            self.assertIn(value, login)
        self.assertIn('/home/root/.config/paperrdp/profiles', source)
        self.assertIn("profiles.size()>8", source)
        self.assertIn("writePrivateFile(profilesPath,profilesTemp,listData)", source)
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
        self.assertIn("PaperDesk RDP double click", source)
        self.assertIn("std::chrono::milliseconds(500)", source)
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
        for key in (
            "0x01000003", "0xff08", "0x08", "0x7f",
            "0x01000004", "0x01000005", "0xff0d", "0x0a", "0x0d",
        ):
            self.assertIn(f"case {key}:", source)
        self.assertIn("remoteInputKey(a,u.x,true)", source)
        self.assertIn("remoteInputKey(a,u.x,false)", source)
        self.assertIn("if(specialKeyToScan(key))", source)

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
        self.assertIn("owner.pendingArticles = owner.pendingArticles.concat(parsed)", qml)
        self.assertIn("if (!selectedFeedUrl || candidate.url === selectedFeedUrl)", qml)
        self.assertIn("if (!owner || owner.disposed)", qml)
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
        self.assertIn("paperdesk-e2e-clean.conf", runner)
        self.assertIn("web-live-wp)", runner)
        self.assertIn("web-download)", runner)
        self.assertIn("PaperWeb download saved", runner)
        self.assertIn("PaperWeb HTML reader items", runner)
        self.assertIn("web-live-dynamic)", runner)
        self.assertIn("PaperWeb embedded reader items", runner)
        self.assertIn("care)", runner)
        self.assertIn("PaperDesk Care action check", runner)
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

    def test_terminal_forces_initial_and_output_refreshes(self):
        qml = (RELEASE / "payload/apps/literm/ui/main.qml").read_text()
        self.assertIn('root.refreshTerminal("component ready")', qml)
        self.assertIn('root.refreshTerminal("startup")', qml)
        self.assertIn('root.refreshTerminal("output")', qml)
        self.assertIn("PaperDesk Terminal display changed", qml)

    def test_web_requests_mobile_documents_by_default(self):
        qml = (RELEASE / "payload/apps/paperweb/ui/main.qml").read_text()
        self.assertIn("property bool mobileMode: webSettings.savedMobileMode", qml)
        self.assertIn('objectName: "webViewModeButton"', qml)
        self.assertIn('objectName: "webBackButton"\n                    label: "←"', qml)
        self.assertIn('objectName: "webPicturesButton"', qml)
        self.assertIn('property bool savedMobileMode: true', qml)
        self.assertIn('property bool savedShowPictures: false', qml)
        self.assertIn('PaperWeb view mode", root.mobileMode ? "mobile" : "computer"', qml)
        self.assertIn('xhr.setRequestHeader("User-Agent", mobileUserAgent)', qml)
        self.assertIn('xhr.setRequestHeader("Accept", "text/html', qml)
        self.assertIn('PaperWeb request profile", mobileMode ? "mobile"', qml)
        self.assertIn('if (shouldUseCompactReader(source)) {\n            done("")', qml)
        self.assertIn("Both representations still need PaperWeb's single-column", qml)
        self.assertIn("function shouldUseCompactReader(source)", qml)
        self.assertIn("return true", qml.split("function shouldUseCompactReader(source)", 1)[1].split("function pageReaderTitle", 1)[0])
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

    def test_web_downloads_use_a_hidden_bounded_helper(self):
        apps = RELEASE / "payload/apps"
        qml = (apps / "paperweb/ui/main.qml").read_text()
        helper = (apps / "paperweb-download/download").read_text()
        manifest = json.loads((apps / "paperweb-download/external.manifest.json").read_text())
        self.assertEqual(manifest["qtfb"], False)
        self.assertIn('"external::paperweb-download"', qml)
        self.assertIn("function responseWantsDownload", qml)
        self.assertIn("Content-Disposition", qml)
        self.assertIn("application\\/octet-stream", qml)
        self.assertIn("file:///home/root/.local/share/paperdesk/download-status", qml)
        self.assertIn("/home/root/Downloads/PaperDesk", helper)
        self.assertIn('case "$URL" in', helper)
        self.assertIn("http://*|https://*", helper)
        self.assertIn('ulimit -f "$MAX_BLOCKS"', helper)
        self.assertIn("MAX_BLOCKS=204800", helper)
        self.assertIn("Not enough free space", helper)
        self.assertNotIn("eval ", helper)
        self.assertNotIn("sh -c", helper)
        installer = (RELEASE / "install.sh").read_text()
        uninstaller = (RELEASE / "uninstall.sh").read_text()
        self.assertIn("paperweb-download", installer)
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
        terminal = (RELEASE / "payload/apps/literm/ui/main.qml").read_text()
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
        for app_name in ("paperdesk", "literm", "paperweb", "paperrss", "paperrdp-login"):
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
                    hashlib.sha256((app_dir / "resources.rcc").read_bytes()).hexdigest(),
                    hashlib.sha256(rebuilt.read_bytes()).hexdigest(),
                    f"{app_name} resources.rcc is stale after editing QML",
                )


if __name__ == "__main__":
    unittest.main()
