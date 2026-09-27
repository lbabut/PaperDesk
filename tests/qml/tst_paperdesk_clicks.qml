import QtQuick 2.15
import QtTest 1.3
import net.asivery.AppLoad 1.0

Item {
    id: scene
    width: 1404
    height: 1872

    property var app: null

    TestCase {
        id: testCase
        name: "PaperDeskClicks"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperdesk/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.app = component.createObject(scene)
            verify(scene.app !== null, component.errorString())
            waitForRendering(scene.app)
        }

        function cleanupTestCase() {
            if (scene.app)
                scene.app.destroy()
        }

        function init() {
            AppLoadLauncher.reset()
        }

        function clickAndVerify(objectName, expectedApplicationId) {
            var button = findChild(scene.app, objectName)
            verify(button !== null, "Missing UI control: " + objectName)
            verify(button.visible && button.enabled, "Control is not clickable: " + objectName)
            var closeSpy = Qt.createQmlObject(
                'import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            closeSpy.target = scene.app
            mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton)
            tryCompare(AppLoadLauncher, "launchCount", 1)
            compare(AppLoadLauncher.lastApplicationId, expectedApplicationId)
            wait(350)
            compare(closeSpy.count, 0, "PaperDesk must stay open behind the launched app")
            closeSpy.destroy()
        }

        function test_terminal_button() {
            clickAndVerify("terminalButton", "literm")
        }

        function test_web_button() {
            clickAndVerify("webButton", "paperweb")
        }

        function test_rdp_button() {
            clickAndVerify("rdpButton", "paperrdp-login")
        }

        function test_rss_button() {
            clickAndVerify("rssButton", "paperrss")
        }
    }
}
