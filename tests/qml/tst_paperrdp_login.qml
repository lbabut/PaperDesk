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
            scene.app.connectionLaunching = false
            scene.app.profileDomain = ""
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
            scene.app.profileDomain = "WORKGROUP"
            scene.app.scalePercent = 50
            scene.app.colorDepth = 8
            mouseClick(connect, connect.width / 2, connect.height / 2, Qt.LeftButton)
            tryCompare(AppLoadLauncher, "launchCount", 1)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp")
            compare(AppLoadLauncher.lastArgs[0], "--host")
            compare(AppLoadLauncher.lastArgs[1], "192.168.1.113")
            compare(AppLoadLauncher.lastArgs[2], "--user")
            compare(AppLoadLauncher.lastArgs[3], "lukasz")
            compare(AppLoadLauncher.lastArgs[4], "--domain-hex")
            compare(AppLoadLauncher.lastArgs[5], "574f524b47524f5550")
            compare(AppLoadLauncher.lastArgs[6], "--password-hex")
            compare(AppLoadLauncher.lastArgs[7], "736563726574")
            compare(AppLoadLauncher.lastArgs[8], "--port")
            compare(AppLoadLauncher.lastArgs[9], "3389")
            compare(AppLoadLauncher.lastArgs[10], "--scale-percent")
            compare(AppLoadLauncher.lastArgs[11], "50")
            compare(AppLoadLauncher.lastArgs[12], "--color-depth")
            compare(AppLoadLauncher.lastArgs[13], "8")
            wait(650)
            compare(closeSpy.count, 0)
            closeSpy.destroy()
        }

        function test_connect_guard_allows_a_later_reconnect() {
            var server = findChild(scene.app, "serverInput")
            var username = findChild(scene.app, "usernameInput")
            var port = findChild(scene.app, "portInput")
            server.text = "nostalgiczny"
            username.text = "lukasz"
            port.text = "3389"
            scene.app.connectRdp()
            scene.app.connectRdp()
            compare(AppLoadLauncher.launchCount, 1)
            tryCompare(scene.app, "connectionLaunching", false, 1400)
            scene.app.connectRdp()
            compare(AppLoadLauncher.launchCount, 2)
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
            verify(findChild(scene.app, "rdpSavedProfilesList") !== null)
            for (var scale of [50, 75, 100])
                verify(findChild(scene.app, "rdpScaleButton_" + scale) !== null)
            for (var depth of [8, 16, 24])
                verify(findChild(scene.app, "rdpColorDepthButton_" + depth) !== null)
        }

        function test_performance_selectors_are_touch_native() {
            var scale = findChild(scene.app, "rdpScaleButton_75")
            var colors = findChild(scene.app, "rdpColorDepthButton_8")
            verify(scale !== null && colors !== null)
            mouseClick(scale, scale.width / 2, scale.height / 2, Qt.LeftButton)
            mouseClick(colors, colors.width / 2, colors.height / 2, Qt.LeftButton)
            compare(scene.app.scalePercent, 75)
            compare(scene.app.colorDepth, 8)
        }

        function test_saved_profiles_populate_fields_and_keep_edits() {
            var host = scene.app.toHex("nostalgiczny")
            var user = scene.app.toHex("lukasz")
            var domain = scene.app.toHex("HOME")
            var secondHost = scene.app.toHex("office")
            var secondUser = scene.app.toHex("admin")
            var secondDomain = scene.app.toHex("WORK")
            scene.app.parseSavedProfiles(
                "v1\t" + host + "\t" + user + "\t" + domain + "\t3389\t" + scene.app.toHex("old") + "\t100\t16\n" +
                "v1\t" + secondHost + "\t" + secondUser + "\t" + secondDomain + "\t3390\t\t75\t8\n")
            compare(scene.app.savedProfileCount, 2)
            scene.app.chooseProfile(0)
            compare(findChild(scene.app, "serverInput").text, "nostalgiczny")
            compare(findChild(scene.app, "usernameInput").text, "lukasz")
            compare(findChild(scene.app, "passwordInput").text, "old")
            compare(scene.app.profileDomain, "HOME")
            compare(scene.app.scalePercent, 100)
            compare(scene.app.colorDepth, 16)

            findChild(scene.app, "passwordInput").text = "new"
            scene.app.scalePercent = 50
            scene.app.colorDepth = 8
            scene.app.connectRdp()
            scene.app.chooseProfile(0)
            compare(findChild(scene.app, "passwordInput").text, "new")
            compare(scene.app.scalePercent, 50)
            compare(scene.app.colorDepth, 8)
            compare(scene.app.profileDomain, "HOME")

            scene.app.chooseProfile(1)
            compare(scene.app.profileDomain, "WORK")
            scene.app.connectionLaunching = false
            scene.app.connectRdp()
            compare(AppLoadLauncher.lastArgs[4], "--domain-hex")
            compare(scene.app.fromHex(AppLoadLauncher.lastArgs[5]), "WORK")
        }

        function test_profile_hex_round_trips_unicode() {
            var value = "Łukasz · żółć"
            compare(scene.app.fromHex(scene.app.toHex(value)), value)
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
