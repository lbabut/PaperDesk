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
                windowLoader.item.appName = "<AppLoad Window>"
                windowLoader.item.closing = false
                windowLoader.item.enabled = true
                windowLoader.item.visible = true
                windowLoader.item.z = 100
                windowLoader.item.systemKeyboardActive = false
                windowLoader.item.rdpShortcutsOpen = false
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

        function test_rdp_uses_system_keyboard_and_one_button_font() {
            windowLoader.item.appName = "PaperDesk RDP Engine"
            windowLoader.item.virtualKeyboardLayout = ({ columns: 1 })
            if(!windowLoader.item.fullscreen)
                windowLoader.item.maximize()

            const genericButton = findChild(windowLoader.item, "paperdeskKeyboardButton")
            const toolbar = findChild(windowLoader.item, "paperdeskRdpToolbar")
            const keyboardButton = findChild(windowLoader.item, "paperdeskRdpKeyboardButton")
            const closeLabel = findChild(windowLoader.item, "paperdeskRdpCloseLabel")
            const keyboardLabel = findChild(windowLoader.item, "paperdeskRdpKeyboardLabel")
            const shortcutsLabel = findChild(windowLoader.item, "paperdeskRdpShortcutsLabel")
            verify(!genericButton.visible)
            verify(toolbar.visible)
            compare(toolbar.height, 112)
            compare(closeLabel.font.pointSize, 16)
            compare(keyboardLabel.font.pointSize, closeLabel.font.pointSize)
            compare(shortcutsLabel.font.pointSize, closeLabel.font.pointSize)

            waitForRendering(windowLoader.item)
            mouseClick(keyboardButton, keyboardButton.width / 2,
                       keyboardButton.height / 2, Qt.LeftButton)
            verify(windowLoader.item.systemKeyboardActive)
            verify(!keyboard.active)
        }

        function test_rdp_shortcut_panel_sends_reserved_engine_action() {
            windowLoader.item.appName = "PaperDesk RDP Engine"
            if(!windowLoader.item.fullscreen)
                windowLoader.item.maximize()
            const canvas = findChild(windowLoader.item, "paperdeskWindowCanvas")
            const shortcuts = findChild(windowLoader.item, "paperdeskRdpShortcutsButton")
            const panel = findChild(windowLoader.item, "paperdeskRdpShortcutsPanel")
            const beforeDown = canvas.keyDownCount
            waitForRendering(windowLoader.item)
            mouseClick(shortcuts, shortcuts.width / 2, shortcuts.height / 2, Qt.LeftButton)
            verify(panel.visible)
            windowLoader.item.sendRdpShortcut(0)
            compare(canvas.keyDownCount, beforeDown + 1)
            compare(canvas.lastKeyDown, 0x02ff0000)
            verify(!panel.visible)
        }

        function test_rdp_system_editor_forwards_text_enter_and_backspace() {
            windowLoader.item.appName = "PaperDesk RDP Engine"
            if(!windowLoader.item.fullscreen)
                windowLoader.item.maximize()
            const canvas = findChild(windowLoader.item, "paperdeskWindowCanvas")
            const editor = findChild(windowLoader.item, "paperdeskRdpSystemKeyboardInput")
            editor.forceActiveFocus()

            editor.text = "a"
            compare(canvas.lastKeyDown, 0x02000061)
            compare(editor.text, "")

            keyClick(Qt.Key_Backspace)
            compare(canvas.lastKeyDown, Qt.Key_Backspace)
            compare(canvas.lastKeyUp, Qt.Key_Backspace)

            keyClick(Qt.Key_Return)
            compare(canvas.lastKeyDown, Qt.Key_Return)
            compare(canvas.lastKeyUp, Qt.Key_Return)
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
