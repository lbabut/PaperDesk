import QtQuick 2.15
import QtTest 1.3
import net.asivery.AppLoad 1.0

Item {
    id: scene
    width: 1404; height: 1872
    TestCase {
        name: "PaperDeskDesign"
        when: windowShown
        function init() { AppLoadLauncher.reset() }
        function cleanup() { AppLoadLauncher.reset() }
        function make(name) {
            var c = Qt.createComponent("../../product/payload/apps/" + name + "/ui/main.qml")
            compare(c.status, Component.Ready, c.errorString())
            var app = null
            if (name === "paperrdp-login") {
                // The production form waits for a correlated asynchronous
                // read. Supply an empty private fixture rather than leaving
                // its helper request pending or skipping the readiness gate.
                AppLoadLauncher.launchHandler = function(id, args) {
                    if (id !== "external::paperrdp-profile" || args[0] !== "--read") return false
                    var token = args[1]
                    Qt.callLater(function() {
                        if (app && app.profileOperationToken === token)
                            app.acceptProfileOperationResult(token,
                                "PaperDeskProfileResult\t1\t" + token + "\tread\tok\tabsent\tnone\n")
                    })
                    return true
                }
            }
            app = createTemporaryObject(c, scene, name === "paperrdp-login" ?
                {profileConfigurationUrl: "file:///paperdesk-design-empty-fixture/"} : {})
            verify(app !== null)
            if (name === "paperrdp-login") {
                tryVerify(function() { return app.profileLoaded && !app.profileActionPending }, 1500)
                compare(app.profileRevision, "absent")
                compare(app.savedProfileCount, 0)
            }
            if (app.abortAll) app.abortAll()
            if (app.abortRequests) app.abortRequests()
            waitForRendering(app); wait(40)
            return app
        }
        function tap(app, name) {
            var item = findChild(app, name)
            verify(item !== null && item.visible && item.enabled, name)
            mouseClick(item, item.width / 2, item.height / 2)
            wait(30)
            return item
        }
        function test_consistent_close_data() {
            return [
                {tag: "SSH", app: "paperterminal", close: "terminalCloseButton"},
                {tag: "RDP", app: "paperrdp-login", close: "rdpCloseButton"},
                {tag: "RSS", app: "paperrss", close: "rssCloseButton"},
                {tag: "Web", app: "paperweb", close: "webCloseButton"},
                {tag: "Books", app: "paperbooks", close: "booksCloseButton"},
                {tag: "Dots", app: "paperdots", close: "dotsCloseButton"},
                {tag: "Care", app: "papercare", close: "careCloseButton"}
            ]
        }
        function test_consistent_close(data) {
            var app = make(data.app), close = findChild(app, data.close)
            verify(close !== null)
            compare(close.width, 176)
            compare(close.height, 76)
            compare(close.radius, 8)
            var p = close.mapToItem(app, 0, 0)
            verify(p.x >= app.width - 240 && p.x + close.width <= app.width)
            verify(p.y >= 0 && p.y + close.height <= 140)
            if (app.unloading) app.unloading()
        }
        function test_ssh_toolbar_has_room_and_exclusive_panels() {
            var app = make("paperterminal"), previousRight = 0
            var identity = findChild(app, "terminalIdentity")
            var input = findChild(app, "terminalInputFrame")
            verify(identity.visible && identity.width >= 300)
            verify(identity.x + identity.width < input.x)
            var actions = ["Sessions", "Display", "Mouse", "Keyboard", "Shortcuts"]
            for (var i = 0; i < actions.length; ++i) {
                var action = findChild(app, "terminal" + actions[i] + "Button")
                verify(action.width >= 240 && action.height >= 76)
                var p = action.mapToItem(app, 0, 0)
                verify(p.x >= previousRight && p.y >= 112)
                previousRight = p.x + action.width
            }
            tap(app, "terminalSessionsButton")
            var sessions = findChild(app, "sshSessionsBack")
            verify(sessions.visible)
            tap(app, "terminalDisplayButton")
            verify(app.displayOpen && !sessions.visible)
            tap(app, "terminalShortcutsButton")
            verify(app.shortcutsOpen && !app.displayOpen)
            app.unloading()
        }
        function test_ssh_expanded_controls_reserve_terminal_space() {
            var app = make("paperterminal")
            var renderer = findChild(app, "terminalRenderer")
            var originalTop = renderer.mapToItem(app, 0, 0).y
            var originalHeight = renderer.height
            for (var name of ["Shortcuts", "Display"]) {
                tap(app, "terminal" + name + "Button")
                var panel = findChild(app, "terminal" + name + "Panel")
                verify(panel.visible)
                var panelBottom = panel.mapToItem(app, 0, panel.height).y
                verify(renderer.mapToItem(app, 0, 0).y > panelBottom,
                       name + " controls must not cover the first terminal row")
                compare(renderer.mapToItem(app, 0, 0).y, originalTop + panel.height)
                compare(renderer.height, originalHeight - panel.height)
                var inset = app.calculateKeyboardInset(true, 1, app.height, app.height)
                verify(inset >= 0)
                app.keyboardInset = inset; wait(20)
                verify(renderer.height >= 240, "Expanded controls leave a usable terminal above the keyboard")
                app.keyboardInset = 0
                tap(app, "terminal" + name + "Button")
                verify(!panel.visible)
                compare(renderer.mapToItem(app, 0, 0).y, originalTop)
                compare(renderer.height, originalHeight)
            }
            app.unloading()
        }
        function test_ssh_keyboard_hint_matches_home() {
            var app = make("paperterminal")
            var home = findChild(app, "terminalHomePanel"), hint = findChild(app, "terminalInputHint")
            verify(home !== null && hint !== null)
            home.menuReady = true
            verify(home.visible)
            compare(hint.text, "Connection number + Enter")
            home.menuReady = false
            verify(!home.visible)
            compare(hint.text, "Keyboard input goes to SSH")
            app.unloading()
        }
        function test_ssh_modifier_status_survives_panel_close_and_resets_in_sessions() {
            var app = make("paperterminal"), status = findChild(app, "terminalModifierStatus")
            tap(app, "terminalShortcutsButton")
            tap(app, "terminalModifierCtrl")
            verify(status.visible); compare(status.text, "CTRL next")
            tap(app, "terminalShortcutsButton")
            verify(status.visible); compare(status.text, "CTRL next")
            var position = status.mapToItem(app, 0, 0)
            verify(position.y >= 0 && position.y + status.height < 112)
            tap(app, "terminalSessionsButton")
            verify(!status.visible)
            app.unloading()
        }
        function test_ssh_modified_paste_notice_stays_in_toolbar() {
            var app = make("paperterminal"), terminal = findChild(app, "terminalRenderer")
            var previousError = terminal.error
            var rejected = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            rejected.target = terminal; rejected.signalName = "inputRejected"
            terminal.cycleModifier(Qt.ControlModifier)
            terminal.putString("nonsecret test paste")
            var status = findChild(app, "terminalModifierStatus")
            verify(status.visible)
            compare(rejected.count, 1)
            compare(status.text, rejected.signalArguments[0][0])
            compare(terminal.latchedModifiers, 0); compare(terminal.lockedModifiers, 0)
            compare(terminal.error, previousError)
            var position = status.mapToItem(app, 0, 0)
            verify(position.y >= 0 && position.y + status.height < 112)
            app.unloading()
        }
        function test_web_controls_are_finger_sized_and_show_state() {
            var app = make("paperweb")
            for (var name of ["webBackButton", "webReloadButton", "webGoButton", "webViewModeButton", "webPicturesButton", "webZoomInButton", "webZoomOutButton"]) {
                var b = findChild(app, name)
                verify(b.width >= 76 && b.height >= 76, name)
            }
            var mode = findChild(app, "webViewModeButton")
            verify(mode.label.indexOf("View:") === 0)
            tap(app, "webViewModeButton")
            compare(mode.label, app.mobileMode ? "View: Mobile" : "View: Computer")
            var pictures = findChild(app, "webPicturesButton")
            tap(app, "webPicturesButton")
            compare(pictures.label, app.showPictures ? "Pictures: on" : "Pictures: off")
            app.unloading()
        }
        function test_ssh_hold_sends_only_right_click() {
            var app = make("paperterminal")
            var clicks = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            clicks.target = app; clicks.signalName = "mouseReport"
            compare(app.mouseMode, true)
            var touch = findChild(app, "terminalTouchArea")
            var sequence = touchEvent(touch)
            sequence.press(0, touch, 200, 200).commit()
            wait(780)
            sequence.release(0, touch, 200, 200).commit()
            wait(30)
            compare(clicks.count, 1, "Hold and release emit one click")
            compare(clicks.signalArguments[0][0], 2, "Hold emits the right button")
            compare(clicks.signalArguments[0][1], false, "No mouse bytes without remote negotiation")
            app.unloading()
        }
        function test_rdp_editor_actions_do_not_hide_validation() {
            var app = make("paperrdp-login")
            app.beginAddProfile(); app.keyboardInset = 710
            compare(app.editorMode, "add")
            wait(30)
            var save = findChild(app, "rdpProfileSaveButton")
            var p = save.mapToItem(app, 0, save.height)
            verify(p.y < app.height - 710)
            var launchesBefore = AppLoadLauncher.launchCount
            tap(app, "rdpProfileSaveButton")
            var message = findChild(app, "rdpEditorStatus")
            verify(message.visible)
            compare(message.text, "Server and username are required")
            verify(!app.profileActionPending)
            compare(AppLoadLauncher.launchCount, launchesBefore, "An invalid form must not start a write")
            verify(message.mapToItem(app, 0, message.height).y <= save.mapToItem(app, 0, 0).y)
            app.cancelProfileEdit()
        }
        function test_rdp_remote_controls_fit_above_keyboard_data() {
            return [{tag: "portrait", landscape: false}, {tag: "landscape", landscape: true}]
        }
        function test_rdp_remote_controls_fit_above_keyboard(data) {
            var component = Qt.createComponent("../../product/payload/system/paperdesk-appload-window.qml")
            compare(component.status, Component.Ready, component.errorString())
            var win = createTemporaryObject(component, scene, {globalWidth: 1404, globalHeight: 1872,
                appName: "PaperDesk RDP Engine", rdpLandscape: data.landscape})
            verify(win !== null)
            win.maximize(); win.systemKeyboardActive = true; win.rdpShortcutsOpen = true
            var panel = findChild(win, "paperdeskRdpShortcutsPanel")
            var chrome = findChild(win, "paperdeskRdpChrome")
            for(var page = 0; page < 3; ++page) {
                tap(win, "paperdeskRdpShortcutTab_" + page)
                wait(20)
                var last = findChild(win, page === 0 ? "paperdeskRdpShortcut_8" :
                    page === 1 ? "paperdeskRdpNav_Fit" : "paperdeskRdpFunction_F12")
                verify(last.visible && last.width >= 240 && last.height >= 76)
                var bounds = last.mapToItem(panel, 0, 0, last.width, last.height)
                verify(bounds.y + bounds.height < panel.height - 96, "Every key stays above Back")
                var panelBottom = panel.mapToItem(chrome, 0, panel.height).y
                compare(panelBottom, chrome.height - win.rdpKeyboardInset)
                verify(win.systemKeyboardActive, "Tabs preserve keyboard state")
            }
            for(var name of ["Keyboard", "Close"]) {
                var action = findChild(win, "paperdeskRdp" + name + "Button")
                var position = action.mapToItem(chrome, 0, 0)
                verify(position.y >= 0 && position.y + action.height <= 112)
                verify(action.width >= 176 && action.height >= 68)
            }
            win.hideSystemKeyboard()
        }
        function test_rss_feed_remove_and_add_close_are_reachable() {
            var app = make("paperrss")
            var remove = findChild(app, "rssDeleteFeedButton_0")
            verify(remove !== null && remove.height >= 76 && remove.width >= 110)
            app.view = "add"; app.keyboardInset = 710; wait(50)
            var close = findChild(app, "rssAddCloseButton")
            verify(close.visible && close.height === 76)
            verify(Qt.colorEqual(findChild(app, "rssAddButton").border.color, "white"), "Primary action needs an outline on a dark header")
            var url = findChild(app, "rssFeedUrlInput")
            verify(url.mapToItem(app, 0, url.height).y < app.height - 710)
            app.unloading()
        }
        function test_books_guidance_matches_the_selected_view() {
            var app = make("paperbooks")
            app.switchView("search")
            verify(app.status.indexOf("research topic") >= 0)
            app.switchView("settings")
            verify(app.status.indexOf("choices") >= 0)
            app.switchView("shelf")
            verify(app.status.indexOf("offline books") >= 0)
            app.unloading()
        }
        function test_care_long_messages_grow_instead_of_overlapping() {
            var app = make("papercare")
            app.state = "available"
            app.statusMessage = "An update is available. ".repeat(15)
            app.releaseNotes = "Changes\n".repeat(20)
            wait(50)
            var install = findChild(app, "careInstallButton")
            verify(install.height >= 76)
            verify(install.y + install.height <= install.parent.height + 1)
            app.unloading()
        }
    }
}
