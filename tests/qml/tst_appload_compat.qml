import QtQuick 2.15
import QtTest 1.2

Item {
    id: scene
    width: 1404
    height: 1872

    QtObject {
        id: keyboard
        property bool active: true
        property var config: null
        property var layout: null
    }

    Loader {
        id: windowLoader
        source: "../../product/payload/system/paperdesk-appload-window.qml"
        onLoaded: {
            item.globalWidth = 1404
            item.globalHeight = 1872
            item.virtualKeyboardRef = keyboard
            keyboard.config = item.keyboardConfig
        }
    }

    Loader {
        id: appLoadLoader
        source: "../../product/payload/system/paperdesk-appload.qml"
    }

    TestCase {
        name: "AppLoadCloseCompatibility"
        width: parent.width
        height: parent.height
        when: windowShown && windowLoader.status === Loader.Ready && appLoadLoader.status === Loader.Ready

        SignalSpy {
            id: closeSpy
            target: windowLoader.item
            signalName: "closed"
        }

        function init() {
            if(windowLoader.item) {
                windowLoader.item.closing = false
                windowLoader.item.enabled = true
                windowLoader.item.visible = true
                windowLoader.item.z = 100
                keyboard.config = windowLoader.item.keyboardConfig
                keyboard.active = true
            }
            closeSpy.clear()
        }

        function test_fullscreen_button_toggles_system_keyboard() {
            windowLoader.item.virtualKeyboardLayout = ({ columns: 1 })
            if(!windowLoader.item.fullscreen)
                windowLoader.item.maximize()
            const clickTarget = findChild(windowLoader.item, "paperdeskKeyboardButton")
            verify(clickTarget !== null)
            verify(clickTarget.visible && clickTarget.enabled)

            waitForRendering(windowLoader.item)
            mouseClick(clickTarget, clickTarget.width / 2, clickTarget.height / 2, Qt.LeftButton)
            verify(!keyboard.active)

            mouseClick(clickTarget, clickTarget.width / 2, clickTarget.height / 2, Qt.LeftButton)
            verify(keyboard.active)
            compare(keyboard.config, windowLoader.item.keyboardConfig)
        }

        function test_fullscreen_button_is_hidden_without_a_keyboard() {
            windowLoader.item.virtualKeyboardLayout = null
            if(!windowLoader.item.fullscreen)
                windowLoader.item.maximize()
            const clickTarget = findChild(windowLoader.item, "paperdeskKeyboardButton")
            verify(clickTarget !== null)
            verify(!clickTarget.visible)
        }

        function test_inactive_internal_window_does_not_consume_close_signal() {
            const canvas = findChild(windowLoader.item, "paperdeskWindowCanvas")
            verify(canvas !== null)
            windowLoader.item.qtfbKey = -1
            canvas.active = true
            canvas.active = false

            compare(closeSpy.count, 0)
            verify(!windowLoader.item.closing)
        }

        function test_stale_application_entry_cannot_create_orphan_window() {
            const childCount = appLoadLoader.item.children.length
            compare(appLoadLoader.item.launchWindow({ id: "paperrdp-login" }), null)
            compare(appLoadLoader.item.children.length, childCount)
        }

        function test_technical_and_redundant_apps_are_hidden_from_launcher() {
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "paperdesk" }))
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "external::paperrdp" }))
            verify(appLoadLoader.item.isVisibleLauncherApplication({ id: "paperrdp-login" }))
            verify(appLoadLoader.item.isVisibleLauncherApplication({ id: "paperweb" }))
        }

        function test_external_window_closes_only_after_framebuffer_was_active() {
            const canvas = findChild(windowLoader.item, "paperdeskWindowCanvas")
            verify(canvas !== null)
            windowLoader.item.qtfbKey = 1234
            windowLoader.item.framebufferWasActive = false
            canvas.active = false
            compare(closeSpy.count, 0)

            canvas.active = true
            canvas.active = false
            compare(closeSpy.count, 1)
        }

        function test_close_is_idempotent_and_releases_keyboard() {
            compare(windowLoader.status, Loader.Ready)
            compare(appLoadLoader.status, Loader.Ready)
            verify(keyboard.active)

            windowLoader.item.completeClose()
            windowLoader.item.completeClose()

            compare(closeSpy.count, 1)
            verify(!keyboard.active)
            verify(!windowLoader.item.enabled)
            verify(!windowLoader.item.visible)
            compare(windowLoader.item.z, -1)
        }
    }
}
