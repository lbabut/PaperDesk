import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1872
    QtObject {
        id: credentials
        property int serial: 0
        function createCredentialId() {
            serial += 1
            return "00000000-0000-4000-8000-" + ("000000000000" + serial).slice(-12)
        }
        function hasSavedPassword(id, host, user, port) { return false }
        function savePassword(id, host, user, port, password) { return true }
        function forgetPassword(id) { return true }
    }
    TestCase {
        name: "TerminalHome"
        when: windowShown
        function makeHub(rows) {
            var sessionsComponent = Qt.createComponent("../../product/payload/apps/paperterminal/ui/Sessions.qml")
            compare(sessionsComponent.status, Component.Ready, sessionsComponent.errorString())
            var panel = createTemporaryObject(sessionsComponent, scene, {
                width: scene.width, height: scene.height, visible: false, credentialStore: credentials
            })
            credentials.serial = 0
            findChild(panel, "sshSessionSettings").sessionsJson = JSON.stringify(rows || [])
            panel.load()
            var component = Qt.createComponent("../../product/payload/apps/paperterminal/ui/Home.qml")
            compare(component.status, Component.Ready, component.errorString())
            var home = createTemporaryObject(component, scene, {
                width: scene.width, height: 1200, menuReady: true, savedSessions: panel.savedSessions
            })
            home.openRequested.connect(function(index) { panel.openIndex(index) })
            var open = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            open.target = home; open.signalName = "openRequested"
            var connect = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            connect.target = panel; connect.signalName = "connectRequested"
            waitForRendering(home); wait(30)
            return {home: home, panel: panel, open: open, connect: connect}
        }
        function rows(count) {
            var profiles = []
            for (var i = 0; i < count; ++i)
                profiles.push({name: "Server " + (i + 1), host: "host" + (i + 1) + ".example", user: "tester", port: "22"})
            return profiles
        }
        function tap(item, name) {
            var target = findChild(item, name)
            verify(target !== null && target.visible && target.enabled, name)
            mouseClick(target, target.width / 2, target.height / 2)
            wait(30)
        }
        function edit(hub, adding, name, host) {
            hub.home.managementOpen = true; hub.panel.visible = true
            if (adding) tap(hub.panel, "sshSessionNew")
            else tap(hub.panel, "sshSessionEdit")
            findChild(hub.panel, "sshSessionNameInput").text = name
            findChild(hub.panel, "sshSessionHostInput").text = host
            findChild(hub.panel, "sshSessionUserInput").text = "tester"
            findChild(hub.panel, "sshSessionPortInput").text = "22"
            tap(hub.panel, "sshSessionSave")
            hub.panel.visible = false; hub.home.managementOpen = false
            waitForRendering(hub.home); wait(30)
        }
        function test_real_taps_show_names_addresses_and_open_saved_profile() {
            var profiles = rows(2)
            profiles[0].name = "Nostalgiczny"; profiles[1].name = ""
            var hub = makeHub(profiles)
            compare(findChild(hub.home, "terminalHomeSessionLabel_0").text, "1 - Nostalgiczny")
            compare(findChild(hub.home, "terminalHomeSessionLabel_1").text, "2 - host2.example")
            tap(hub.home, "terminalHomeSession_0")
            compare(hub.open.count, 1); compare(hub.open.signalArguments[0][0], 0)
            compare(hub.connect.count, 1); compare(hub.connect.signalArguments[0][0], "host1.example")
            compare(hub.connect.signalArguments[0][3], "")
        }
        function test_multi_digit_numbers_backspace_and_unknown_number_feedback() {
            var hub = makeHub(rows(32))
            hub.home.handleInput("12\x7f0\r")
            compare(hub.open.count, 1); compare(hub.open.signalArguments[0][0], 9)
            hub.home.handleInput("31\b2\n")
            compare(hub.open.count, 2); compare(hub.open.signalArguments[1][0], 31)
            for (var invalid of ["33\r", "0\n", "100\r", "1x\r", "\r"]) {
                hub.home.handleInput(invalid)
                compare(hub.open.count, 2)
                verify(hub.home.message.indexOf("Unknown connection number") >= 0)
            }
            hub.home.handleInput("\x1b[3~")
            compare(hub.home.numberInput, ""); compare(hub.open.count, 2)
            hub.home.handleInput("2\r")
            compare(hub.open.count, 3); compare(hub.open.signalArguments[2][0], 1)
        }
        function test_first_enter_discards_entire_paste_suffix_and_busy_input() {
            var hub = makeHub(rows(32))
            hub.home.openRequested.connect(function(index) { hub.home.menuReady = false })
            hub.home.handleInput("10\rwhoami\n32\r")
            compare(hub.open.count, 1); compare(hub.open.signalArguments[0][0], 9)
            compare(hub.connect.count, 1); verify(!hub.home.visible)
            hub.home.handleInput("2\r")
            compare(hub.open.count, 1)
            hub.home.menuReady = true
            hub.home.handleInput("99\r2\r")
            compare(hub.open.count, 1, "Even an invalid first line discards all later clipboard lines")
        }
        function test_busy_remote_and_management_never_display_home() {
            var hub = makeHub(rows(1))
            verify(hub.home.visible)
            hub.home.menuReady = false; verify(!hub.home.visible)
            verify(!hub.home.requestOpen(0)); hub.home.handleInput("1\r")
            compare(hub.open.count, 0)
            hub.home.menuReady = true; hub.home.managementOpen = true
            verify(!hub.home.visible)
            hub.home.handleInput("1\r"); compare(hub.open.count, 0)
            hub.home.managementOpen = false; verify(hub.home.visible)
        }
        function test_dynamic_crud_reload_uses_one_shared_model() {
            var hub = makeHub()
            compare(hub.home.count, 0)
            verify(findChild(hub.home, "terminalHomeMessage").text.indexOf("No saved connections") >= 0)
            edit(hub, true, "Nostalgiczny", "one.example")
            compare(hub.home.count, 1)
            compare(findChild(hub.home, "terminalHomeSessionLabel_0").text, "1 - Nostalgiczny")
            edit(hub, true, "Lola", "two.example")
            compare(hub.home.count, 2)
            edit(hub, false, "Lola changed", "changed.example")
            compare(findChild(hub.home, "terminalHomeSessionLabel_1").text, "2 - Lola changed")
            hub.panel.load(); waitForRendering(hub.home); wait(30)
            compare(hub.home.count, 2)
            tap(hub.home, "terminalHomeSession_1")
            compare(hub.connect.signalArguments[0][0], "changed.example")
            hub.home.managementOpen = true; hub.panel.visible = true
            tap(hub.panel, "sshSessionDelete"); tap(hub.panel, "sshSessionDeleteConfirm")
            hub.panel.visible = false; hub.home.managementOpen = false
            waitForRendering(hub.home); wait(30)
            compare(hub.home.count, 1)
            compare(findChild(hub.home, "terminalHomeSessionLabel_0").text, "1 - Nostalgiczny")
        }
        function test_last_of_32_profiles_is_scrollable_and_clickable() {
            var hub = makeHub(rows(32)), list = findChild(hub.home, "terminalHomeList")
            list.positionViewAtIndex(31, ListView.End)
            waitForRendering(hub.home); wait(30)
            var row = findChild(hub.home, "terminalHomeSession_31")
            verify(row !== null)
            verify(row.mapToItem(list, 0, 0).y >= 0)
            verify(row.mapToItem(list, 0, row.height).y <= list.height)
            tap(hub.home, "terminalHomeSession_31")
            compare(hub.open.signalArguments[0][0], 31)
        }
        function test_named_actions_and_long_profile_text_stay_in_their_rows() {
            var profiles = rows(1); profiles[0].name = "<b>" + new Array(70).join("A") + "</b>"
            var hub = makeHub(profiles), row = findChild(hub.home, "terminalHomeSession_0")
            var label = findChild(hub.home, "terminalHomeSessionLabel_0")
            compare(label.textFormat, Text.PlainText); compare(label.elide, Text.ElideRight)
            compare(row.height, 118)
            for (var action of ["New", "LocalShell", "Close"]) {
                var spy = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
                spy.target = hub.home
                spy.signalName = action === "New" ? "newRequested" : action === "LocalShell" ? "localShellRequested" : "closeRequested"
                tap(hub.home, "terminalHome" + action); compare(spy.count, 1)
            }
            compare(hub.open.count, 0)
        }
    }
}
