import QtQuick 2.15
import QtTest 1.3
import net.asivery.AppLoad 1.0

Item {
    id: scene
    width: 1404
    height: 1872
    property var app: null

    TestCase {
        name: "PaperRdpNativeLogin"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperrdp-login/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.app = component.createObject(scene)
            verify(scene.app !== null, component.errorString())
            waitForRendering(scene.app)
        }

        function cleanupTestCase() {
            if (scene.app) scene.app.destroy()
        }

        function init() {
            AppLoadLauncher.reset()
        }

        function test_backspace_edits_username() {
            var username = findChild(scene.app, "usernameInput")
            verify(username !== null)
            username.text = "lukasza"
            username.forceActiveFocus()
            keyClick(Qt.Key_Backspace)
            compare(username.text, "lukasz")
        }

        function test_connect_launches_engine() {
            var closeSpy = Qt.createQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            closeSpy.target = scene.app
            closeSpy.signalName = "close"
            var server = findChild(scene.app, "serverInput")
            var username = findChild(scene.app, "usernameInput")
            var password = findChild(scene.app, "passwordInput")
            var port = findChild(scene.app, "portInput")
            var connect = findChild(scene.app, "connectButton")
            server.text = "192.168.1.113"
            username.text = "lukasz"
            password.text = "secret"
            port.text = "3389"
            mouseClick(connect, connect.width / 2, connect.height / 2, Qt.LeftButton)
            tryCompare(AppLoadLauncher, "launchCount", 1)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp")
            compare(AppLoadLauncher.lastArgs[0], "--host")
            compare(AppLoadLauncher.lastArgs[1], "192.168.1.113")
            compare(AppLoadLauncher.lastArgs[2], "--user")
            compare(AppLoadLauncher.lastArgs[3], "lukasz")
            compare(AppLoadLauncher.lastArgs[4], "--password-hex")
            compare(AppLoadLauncher.lastArgs[5], "736563726574")
            wait(650)
            compare(closeSpy.count, 0)
            closeSpy.destroy()
        }

        function test_close_action_emits_once() {
            var close = findChild(scene.app, "rdpCloseButton")
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = scene.app
            mouseClick(close, close.width / 2, close.height / 2, Qt.LeftButton)
            compare(spy.count, 1)
            spy.destroy()
        }

        function test_keyboard_and_all_editors_are_real_targets() {
            verify(findChild(scene.app, "rdpKeyboardButton") !== null)
            for (var name of ["serverInput", "usernameInput", "passwordInput", "portInput"])
                verify(findChild(scene.app, name) !== null, name)
        }

        function test_actions_share_one_visual_system() {
            var close = findChild(scene.app, "rdpCloseButton")
            var keyboard = findChild(scene.app, "rdpKeyboardButton")
            var closeLabel = findChild(scene.app, "rdpCloseLabel")
            var keyboardLabel = findChild(scene.app, "rdpKeyboardLabel")
            var connectLabel = findChild(scene.app, "rdpConnectLabel")
            verify(close !== null && keyboard !== null)
            compare(close.width, 176)
            compare(keyboard.width, close.width)
            compare(close.height, 68)
            compare(keyboard.height, close.height)
            compare(close.radius, 8)
            compare(keyboard.radius, close.radius)
            compare(closeLabel.font.pointSize, 16)
            compare(keyboardLabel.font.pointSize, closeLabel.font.pointSize)
            compare(connectLabel.font.pointSize, closeLabel.font.pointSize)
            verify(closeLabel.font.bold)
            verify(keyboardLabel.font.bold)
            verify(connectLabel.font.bold)
        }
    }
}
