import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1872
    TestCase {
        name: "PaperDeskDesign"
        when: windowShown
        function make(name) {
            var c = Qt.createComponent("../../product/payload/apps/" + name + "/ui/main.qml")
            compare(c.status, Component.Ready, c.errorString())
            var app = createTemporaryObject(c, scene)
            verify(app !== null)
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
                {tag: "SSH", app: "literm", close: "terminalCloseButton"},
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
            var app = make("literm"), previousRight = 0
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
            var app = make("literm")
            app.toggleMouseMode()
            var touch = findChild(app, "terminalTouchArea")
            var terminal = findChild(app, "terminalRenderer")
            var sequence = touchEvent(touch)
            sequence.press(0, touch, 200, 200).commit()
            wait(780)
            sequence.release(0, touch, 200, 200).commit()
            wait(30)
            verify(terminal.sentText.indexOf("\u001b[<2;") >= 0, "Hold must emit right button")
            verify(terminal.sentText.indexOf("\u001b[<0;") < 0, "Release must not emit a left click after hold")
            app.unloading()
        }
        function test_rdp_editor_actions_do_not_hide_validation() {
            var app = make("paperrdp-login")
            app.beginAddProfile(); app.keyboardInset = 710
            wait(30)
            var save = findChild(app, "rdpProfileSaveButton")
            var p = save.mapToItem(app, 0, save.height)
            verify(p.y < app.height - 710)
            tap(app, "rdpProfileSaveButton")
            var message = findChild(app, "rdpEditorStatus")
            verify(message.visible && message.text.length > 0)
            verify(message.mapToItem(app, 0, message.height).y <= save.mapToItem(app, 0, 0).y)
            app.cancelProfileEdit()
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
