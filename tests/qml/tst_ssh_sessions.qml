import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1760
    TestCase {
        name: "SshSavedSessions"
        when: windowShown
        function makePanel() {
            var component = Qt.createComponent("../../product/payload/apps/literm/ui/Sessions.qml")
            compare(component.status, Component.Ready, component.errorString())
            var panel = createTemporaryObject(component, scene, {width: scene.width, height: scene.height})
            verify(panel !== null, component.errorString())
            findChild(panel, "sshSessionSettings").sessionsJson = "[]"
            panel.load(); waitForRendering(panel)
            return panel
        }
        function tap(panel, name) {
            var button = findChild(panel, name)
            verify(button !== null && button.visible)
            mouseClick(button, button.width / 2, button.height / 2)
            wait(30)
        }
        function fill(panel, host) {
            findChild(panel, "sshSessionNameInput").text = "My server"
            findChild(panel, "sshSessionHostInput").text = host
            findChild(panel, "sshSessionUserInput").text = "tester"
            findChild(panel, "sshSessionPortInput").text = "2222"
        }
        function test_real_taps_new_save_open_edit_delete_and_reload() {
            var panel = makePanel()
            var open = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            open.target = panel; open.signalName = "connectRequested"
            tap(panel, "sshSessionNew"); fill(panel, "server.example")
            tap(panel, "sshSessionSave")
            compare(panel.count, 1); compare(panel.mode, "")
            panel.load(); compare(panel.count, 1)
            tap(panel, "sshSessionRow_0"); tap(panel, "sshSessionOpen")
            compare(open.count, 1); compare(open.signalArguments[0][0], "server.example")
            compare(open.signalArguments[0][1], "tester"); compare(open.signalArguments[0][2], "2222")
            tap(panel, "sshSessionEdit"); fill(panel, "changed.example"); tap(panel, "sshSessionSave")
            panel.load(); tap(panel, "sshSessionOpen")
            compare(open.signalArguments[1][0], "changed.example")
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteCancel"); compare(panel.count, 1)
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteConfirm"); compare(panel.count, 0)
            panel.load(); compare(panel.count, 0)
        }
        function test_keyboard_keeps_save_visible_and_port_scrollable() {
            var panel = makePanel()
            tap(panel, "sshSessionNew")
            panel.keyboardInset = 900
            var port = findChild(panel, "sshSessionPortInput")
            port.forceActiveFocus(); wait(80)
            var save = findChild(panel, "sshSessionSave"), scroll = findChild(panel, "sshSessionScroll")
            verify(scroll.contentY > 0)
            verify(save.mapToItem(panel, 0, save.height).y <= panel.height - panel.keyboardInset)
            verify(port.mapToItem(scroll, 0, port.height).y <= scroll.height)
            fill(panel, "::1"); tap(panel, "sshSessionSave"); compare(panel.count, 1)
        }
        function test_validation_and_damaged_settings_are_safe() {
            var panel = makePanel()
            verify(!panel.valid("-oProxyCommand=x", "user", "22"))
            verify(!panel.valid("host\ncommand", "user", "22"))
            verify(!panel.valid("host", "user;touch", "22"))
            verify(!panel.valid("host", "user", "0"))
            verify(!panel.valid("host", "user", "65536"))
            verify(panel.valid("fe80::1%wlan0", "user-name", "22"))
            findChild(panel, "sshSessionSettings").sessionsJson = '{"malformed":true}'
            panel.load(); compare(panel.count, 0)
            compare(panel.selectedIndex, -1)
            tap(panel, "sshSessionNew"); fill(panel, "bad host")
            tap(panel, "sshSessionSave"); compare(panel.count, 0); compare(panel.mode, "add")
            tap(panel, "sshSessionCancel"); compare(panel.mode, "")
        }
    }
}
