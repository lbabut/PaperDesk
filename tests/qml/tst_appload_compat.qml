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

    Item {
        id: nativeKeyboardView
        objectName: "virtualkeyboard/window/main"
        width: 1404; height: 1872
        property alias contentItem: nativeKeyboardPanel
        Item {
            id: nativeKeyboardPanel
            x: 0; y: 0
            width: nativeKeyboardView.width
            height: nativeKeyboardView.height
            property var virtualKeyboard: keyboard
            property bool portrait: true
            property var keyPopup: null
        }
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
                windowLoader.item.rdpShortcutPage = 0
                windowLoader.item.rdpLandscape = false
                windowLoader.item.rdpNativeKeyboardPanel = null
                windowLoader.item.qtfbKey = -1
                windowLoader.item.framebufferWasActive = false
                windowLoader.item.rdpKeyboardRectangle = Qt.binding(function() { return Qt.inputMethod.keyboardRectangle })
                findChild(windowLoader.item, "paperdeskWindowCanvas").active = true
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

        function test_landscape_toolbar_hit_targets_and_native_keyboard_escape() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            if(!win.fullscreen) win.maximize()
            win.rdpLandscape = true
            const chrome = findChild(win, "paperdeskRdpChrome")
            const shortcuts = findChild(win, "paperdeskRdpShortcutsButton")
            const keyboardButton = findChild(win, "paperdeskRdpKeyboardButton")
            const close = findChild(win, "paperdeskRdpCloseButton")
            compare(chrome.width, 1872)
            compare(chrome.height, 1404)
            compare(chrome.rotation, 90)
            for (var action of ["Close", "Keyboard", "Shortcuts", "ShortcutsBack"]) {
                var handler = findChild(win, "paperdeskRdp" + action + "TapHandler")
                verify(handler !== null)
                compare(handler.gesturePolicy, TapHandler.ReleaseWithinBounds)
            }
            var position = close.mapToItem(win, close.width/2, close.height/2)
            verify(position.x > 1290 && position.x < 1404)
            verify(position.y > 1600 && position.y < 1872)
            mouseClick(shortcuts, shortcuts.width/2, shortcuts.height/2)
            verify(win.rdpShortcutsOpen)
            const escape = findChild(win, "paperdeskRdpShortcut_7")
            const canvas = findChild(win, "paperdeskWindowCanvas")
            mouseClick(escape, escape.width/2, escape.height/2)
            compare(canvas.lastKeyDown, 0x02ff0007)
            verify(!win.rdpShortcutsOpen)
            mouseClick(keyboardButton, keyboardButton.width/2, keyboardButton.height/2)
            verify(win.systemKeyboardActive)
            compare(chrome.rotation, 90)
            position = keyboardButton.mapToItem(win, 0, keyboardButton.height)
            verify(position.x >= 1290, "Hide keyboard stays on the landscape top edge")
            tryCompare(nativeKeyboardPanel, "rotation", 90)
            compare(nativeKeyboardPanel.width, 1872)
            compare(nativeKeyboardPanel.height, 1404)
            compare(nativeKeyboardPanel.x, 1404)
            verify(!nativeKeyboardPanel.portrait)
            const input = findChild(win, "paperdeskRdpSystemKeyboardInput")
            keyClick(Qt.Key_Backspace)
            keyClick(Qt.Key_Return)
            mouseClick(keyboardButton, keyboardButton.width/2, keyboardButton.height/2)
            verify(!win.systemKeyboardActive)
            compare(chrome.rotation, 90)
            compare(nativeKeyboardPanel.rotation, 0)
            compare(nativeKeyboardPanel.width, 1404)
            compare(nativeKeyboardPanel.height, 1872)
            verify(nativeKeyboardPanel.portrait)
        }

        function test_native_dismiss_does_not_rotate_button_during_a_press() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = true
            win.systemKeyboardActive = true
            win.systemKeyboardVisibilityChanged(false)
            compare(win.rdpChromeLandscape, true)
            wait(60)
            compare(win.rdpChromeLandscape, true)
            wait(200)
            compare(win.systemKeyboardActive, false)
            compare(win.rdpChromeLandscape, true)
        }

        function test_native_panel_restores_bindings_on_focus_loss_and_close() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = true
            win.systemKeyboardActive = true
            tryCompare(nativeKeyboardPanel, "rotation", 90)
            win.enabled = false
            compare(nativeKeyboardPanel.rotation, 0)
            verify(nativeKeyboardPanel.portrait)
            nativeKeyboardView.width = 1320
            compare(nativeKeyboardPanel.width, 1320, "Original geometry binding must survive")
            nativeKeyboardView.width = 1404
            win.enabled = true
            tryCompare(nativeKeyboardPanel, "rotation", 90)
            win.completeClose()
            compare(nativeKeyboardPanel.rotation, 0)
            compare(nativeKeyboardPanel.x, 0)
            compare(nativeKeyboardPanel.parent, nativeKeyboardView, "Firmware owns the panel lifetime")
        }

        function test_native_panel_lazy_creation_and_cancelled_discovery() {
            const win = windowLoader.item
            nativeKeyboardView.objectName = "not-the-native-keyboard"
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = true
            win.systemKeyboardActive = true
            const probe = findChild(win, "paperdeskRdpNativeKeyboardProbe")
            verify(probe.running)
            wait(70)
            compare(nativeKeyboardPanel.rotation, 0)
            nativeKeyboardView.objectName = "virtualkeyboard/window/main"
            tryCompare(nativeKeyboardPanel, "rotation", 90)
            verify(!probe.running)
            win.hideSystemKeyboard()
            compare(nativeKeyboardPanel.rotation, 0)
            win.rdpNativeKeyboardPanel = null
            nativeKeyboardView.objectName = "not-the-native-keyboard"
            win.systemKeyboardActive = true
            verify(probe.running)
            win.hideSystemKeyboard()
            verify(!probe.running)
            nativeKeyboardView.objectName = "virtualkeyboard/window/main"
            wait(70)
            compare(nativeKeyboardPanel.rotation, 0)
        }

        function test_native_panel_restores_on_unexpected_window_destruction() {
            const component = Qt.createComponent("../../product/payload/system/paperdesk-appload-window.qml")
            const win = component.createObject(scene, { appName: "PaperDesk RDP Engine",
                globalWidth: 1404, globalHeight: 1872, rdpLandscape: true })
            verify(win !== null)
            win.maximize()
            win.systemKeyboardActive = true
            tryCompare(nativeKeyboardPanel, "rotation", 90)
            win.destroy()
            tryCompare(nativeKeyboardPanel, "rotation", 0)
            verify(nativeKeyboardPanel.portrait)
        }

        function test_keyboard_rotation_is_scoped_to_rdp_and_probe_is_bounded() {
            const win = windowLoader.item
            win.rdpLandscape = true
            win.systemKeyboardActive = true
            compare(nativeKeyboardPanel.rotation, 0)
            const probe = findChild(win, "paperdeskRdpNativeKeyboardProbe")
            verify(!probe.running)
            nativeKeyboardView.objectName = "unsupported-firmware"
            win.appName = "PaperDesk RDP Engine"
            verify(probe.running)
            tryCompare(probe, "running", false, 1800)
            compare(probe.attempts, 20)
            compare(nativeKeyboardPanel.rotation, 0)
            win.hideSystemKeyboard()
            nativeKeyboardView.objectName = "virtualkeyboard/window/main"
        }

        function test_shortcuts_keep_landscape_geometry_and_all_actions_fit() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = true
            if(!win.fullscreen) win.maximize()
            win.systemKeyboardActive = true
            const close = findChild(win, "paperdeskRdpCloseButton")
            const before = close.mapToItem(win, 0, 0)
            const button = findChild(win, "paperdeskRdpShortcutsButton")
            mouseClick(button, button.width/2, button.height/2)
            verify(win.rdpShortcutsOpen)
            verify(win.systemKeyboardActive, "Opening shortcuts keeps the typing keyboard visible")
            const after = close.mapToItem(win, 0, 0)
            compare(after.x, before.x)
            compare(after.y, before.y)
            const panel = findChild(win, "paperdeskRdpShortcutsPanel")
            for(let index = 0; index < 9; ++index) {
                const key = findChild(win, "paperdeskRdpShortcut_" + index)
                const p = key.mapToItem(panel, 0, 0)
                verify(p.x >= 0 && p.y >= 0)
                verify(p.x + key.width <= panel.width)
                verify(p.y + key.height <= panel.height)
            }
        }

        function test_rdp_keyboard_viewport_data() {
            return [{tag: "portrait", landscape: false, keyboardHeight: 720},
                    {tag: "landscape", landscape: true, keyboardHeight: 550}]
        }
        function test_rdp_keyboard_viewport(data) {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = data.landscape
            if(!win.fullscreen) win.maximize()
            const chrome = findChild(win, "paperdeskRdpChrome")
            const canvas = findChild(win, "paperdeskWindowCanvas")
            const close = findChild(win, "paperdeskRdpCloseButton")
            const keyboardButton = findChild(win, "paperdeskRdpKeyboardButton")
            const originalCanvas = {x: canvas.x, y: canvas.y, width: canvas.width, height: canvas.height}
            const originalClose = close.mapToItem(win, 0, 0)
            const originalKeyboard = keyboardButton.mapToItem(win, 0, 0)
            win.qtfbKey = 42
            tryCompare(canvas, "lastKeyDown", 0x03000000)
            win.rdpKeyboardRectangle = chrome.mapToItem(null, 0, chrome.height - data.keyboardHeight,
                                                       chrome.width, data.keyboardHeight)
            win.systemKeyboardActive = true
            const visibleHeight = chrome.height - 112 - data.keyboardHeight
            tryCompare(win, "rdpViewportHeight", visibleHeight)
            tryCompare(canvas, "lastKeyDown", 0x03000000 | visibleHeight)
            compare(canvas.lastKeyUp, canvas.lastKeyDown)
            compare(canvas.x, originalCanvas.x); compare(canvas.y, originalCanvas.y)
            compare(canvas.width, originalCanvas.width); compare(canvas.height, originalCanvas.height)
            // The framebuffer remains in its original input coordinate space.
            // Native tests check aspect-fit pixels and reject letterbox hits.
            compare(close.mapToItem(win, 0, 0), originalClose)
            compare(keyboardButton.mapToItem(win, 0, 0), originalKeyboard)
            for(const action of [close, keyboardButton]) {
                verify(action.visible)
                const bounds = action.mapToItem(chrome, 0, 0, action.width, action.height)
                verify(bounds.y >= 0 && bounds.y + bounds.height <= 112)
            }
            const count = canvas.keyDownCount
            win.sendRdpViewport(visibleHeight)
            compare(canvas.keyDownCount, count, "Unchanged viewport does not send repeating commands")
            win.enabled = false
            tryCompare(canvas, "lastKeyDown", 0x03000000)
            win.enabled = true
            tryCompare(canvas, "lastKeyDown", 0x03000000 | visibleHeight)
            win.hideSystemKeyboard()
            tryCompare(canvas, "lastKeyDown", 0x03000000)
            compare(win.rdpViewportHeight, chrome.height - 112)
            compare(close.mapToItem(win, 0, 0), originalClose)
        }

        function test_rdp_keyboard_geometry_fallback_and_bounds() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            if(!win.fullscreen) win.maximize()
            for(const landscape of [false, true]) {
                win.rdpLandscape = landscape
                const chrome = findChild(win, "paperdeskRdpChrome")
                compare(win.calculateRdpKeyboardInset(false, Qt.rect(0, 0, 0, 0)), 0)
                const fallback = win.calculateRdpKeyboardInset(true, Qt.rect(0, 0, 0, 0))
                compare(fallback, chrome.height * 0.38)
                const excessive = chrome.mapToItem(null, 0, 113, chrome.width, chrome.height - 113)
                compare(win.calculateRdpKeyboardInset(true, excessive), chrome.height - 112 - 240)
            }
            // A stale portrait report must not become a full-height cover
            // after the native keyboard changes to the landscape layout.
            compare(win.calculateRdpKeyboardInset(true, Qt.rect(0, 1160, 1404, 712)), 1404 * 0.38)
        }

        function test_rdp_navigation_and_function_tabs_send_native_keys_without_keyboard_toggle() {
            const win = windowLoader.item
            win.appName = "PaperDesk RDP Engine"
            win.rdpLandscape = true
            if(!win.fullscreen) win.maximize()
            win.systemKeyboardActive = true
            win.rdpShortcutsOpen = true
            const canvas = findChild(win, "paperdeskWindowCanvas")
            const panel = findChild(win, "paperdeskRdpShortcutsPanel")
            const navTab = findChild(win, "paperdeskRdpShortcutTab_1")
            mouseClick(navTab, navTab.width/2, navTab.height/2)
            compare(win.rdpShortcutPage, 1)
            waitForRendering(panel); wait(20)
            verify(win.systemKeyboardActive)
            for(const item of [{name: "Up", key: Qt.Key_Up}, {name: "Delete", key: Qt.Key_Delete},
                               {name: "PageDown", key: Qt.Key_PageDown}]) {
                win.rdpShortcutsOpen = true
                const button = findChild(win, "paperdeskRdpNav_" + item.name)
                verify(button.visible && button.width >= 240 && button.height >= 76)
                mouseClick(button, button.width/2, button.height/2)
                compare(canvas.lastKeyDown, item.key); compare(canvas.lastKeyUp, item.key)
                verify(win.systemKeyboardActive && !win.rdpShortcutsOpen)
            }
            win.rdpShortcutsOpen = true
            const functionsTab = findChild(win, "paperdeskRdpShortcutTab_2")
            mouseClick(functionsTab, functionsTab.width/2, functionsTab.height/2)
            waitForRendering(panel); wait(20)
            for(let number = 1; number <= 12; ++number) {
                win.rdpShortcutsOpen = true
                const button = findChild(win, "paperdeskRdpFunction_F" + number)
                verify(button.visible)
                const bounds = button.mapToItem(panel, 0, 0, button.width, button.height)
                verify(bounds.x >= 0 && bounds.x + bounds.width <= panel.width)
                verify(bounds.y >= 0 && bounds.y + bounds.height < panel.height - 96)
                mouseClick(button, button.width/2, button.height/2)
                compare(canvas.lastKeyDown, Qt.Key_F1 + number - 1)
                compare(canvas.lastKeyUp, canvas.lastKeyDown)
                verify(win.systemKeyboardActive)
            }
            win.hideSystemKeyboard()
            win.sendRdpKey(Qt.Key_F12)
            verify(!win.systemKeyboardActive, "Sending a shortcut does not open the keyboard")
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
            for(const key of [Qt.Key_Tab, Qt.Key_Delete, Qt.Key_Left, Qt.Key_Right, Qt.Key_Up,
                              Qt.Key_Down, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown,
                              Qt.Key_F1, Qt.Key_F5, Qt.Key_F12]) {
                keyClick(key)
                compare(canvas.lastKeyDown, key)
                compare(canvas.lastKeyUp, key)
            }
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

        function test_window_stack_blocks_background_input_and_restores_focus() {
            const first = Qt.createQmlObject(
                'import QtQuick 2.15; Item {' +
                ' property bool closing: false; property bool resumed: false;' +
                ' function deactivateVirtualKeyboard() {}' +
                ' function hideSystemKeyboard() {}' +
                ' function notifyGainedFocus() { resumed = true }' +
                '}', scene)
            const second = Qt.createQmlObject(
                'import QtQuick 2.15; Item {' +
                ' property bool closing: false;' +
                ' function deactivateVirtualKeyboard() {}' +
                ' function hideSystemKeyboard() {}' +
                '}', scene)

            appLoadLoader.item.paperdeskWindowStack = []
            appLoadLoader.item.registerPaperDeskWindow(first)
            verify(first.enabled)
            appLoadLoader.item.registerPaperDeskWindow(second)
            verify(!first.enabled)
            verify(second.enabled)

            second.closing = true
            appLoadLoader.item.unregisterPaperDeskWindow(second)
            verify(first.enabled)
            verify(first.resumed)
            compare(appLoadLoader.item.paperdeskWindowStack.length, 1)

            appLoadLoader.item.paperdeskWindowStack = []
            first.destroy()
            second.destroy()
        }

        function test_technical_and_redundant_apps_are_hidden_from_launcher() {
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "paperdesk" }))
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "external::paperrdp" }))
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "external::paperrdp-profile" }))
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "external::paperbooks-download" }))
            verify(!appLoadLoader.item.isVisibleLauncherApplication({ id: "external::paperweb-download" }))
            verify(appLoadLoader.item.isVisibleLauncherApplication({ id: "paperrdp-login" }))
            verify(appLoadLoader.item.isVisibleLauncherApplication({ id: "paperweb" }))
        }

        function test_no_gui_helper_does_not_create_a_window() {
            const result = appLoadLoader.item.launchWindow({
                id: "external::paperrdp-profile",
                name: "PaperDesk RDP Profile Manager",
                externalType: 1,
                supportsScaling: false,
                virtualKeyboardLayout: null,
                disablesWindowedMode: false,
                aspectRatio: 0,
                canHaveMultipleFrontends: true
            }, ["--delete", "0"], {})
            verify(result !== null)
            verify(result.externalNoGui)
            compare(appLoadLoader.item.paperdeskWindowStack.length, 0)
        }

        function test_landscape_launch_argument_configures_only_rdp_chrome() {
            // Production resolves window.qml from QRR. Tests load the source
            // directly, so supply the exact same replacement component here.
            appLoadLoader.item.windowArchetype = Qt.createComponent("../../product/payload/system/paperdesk-appload-window.qml")
            const app = {
                id: "external::paperrdp", name: "PaperDesk RDP Engine",
                externalType: 2, supportsScaling: false,
                virtualKeyboardLayout: null, disablesWindowedMode: true,
                aspectRatio: 0, canHaveMultipleFrontends: false
            }
            const win = appLoadLoader.item.launchWindow(app, ["--orientation", "landscape"], {})
            verify(win !== null)
            verify(win.rdpLandscape)
            appLoadLoader.item.unregisterPaperDeskWindow(win)
            win.destroy()
            const portrait = appLoadLoader.item.launchWindow(app, [], {})
            verify(portrait !== null)
            verify(!portrait.rdpLandscape)
            appLoadLoader.item.unregisterPaperDeskWindow(portrait)
            portrait.destroy()
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
