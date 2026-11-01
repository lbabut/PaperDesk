import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1872
    QtObject {
        id: backend
        property int latched: 0
        property int locked: 0
        function cycle(modifier) {
            if ((latched | locked) & modifier) {
                latched &= ~modifier; locked &= ~modifier
            } else latched |= modifier
        }
        function lock(modifier) { latched &= ~modifier; locked |= modifier }
    }
    TestCase {
        name: "TerminalShortcuts"
        when: windowShown
        function makePanel() {
            backend.latched = 0; backend.locked = 0
            var component = Qt.createComponent("../../product/payload/apps/paperterminal/ui/Shortcuts.qml")
            compare(component.status, Component.Ready, component.errorString())
            var panel = createTemporaryObject(component, scene, {width: scene.width})
            verify(panel !== null)
            panel.latchedModifiers = Qt.binding(function() { return backend.latched })
            panel.lockedModifiers = Qt.binding(function() { return backend.locked })
            panel.modifierTapped.connect(function(modifier) { backend.cycle(modifier) })
            panel.modifierHeld.connect(function(modifier) { backend.lock(modifier) })
            waitForRendering(panel)
            return panel
        }
        function spy(panel, signal) {
            var result = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            result.target = panel; result.signalName = signal
            return result
        }
        function tap(panel, name) {
            var item = findChild(panel, name)
            verify(item !== null && item.visible && item.enabled, name)
            mouseClick(item, item.width / 2, item.height / 2)
            wait(20)
            return item
        }
        function test_all_function_keys_are_touch_sized_and_dispatch_native_keys() {
            var panel = makePanel(), sent = spy(panel, "shortcutRequested")
            tap(panel, "terminalShortcutFunctionTab")
            verify(panel.functionKeysOpen)
            for (var i = 1; i <= 12; ++i) {
                var key = tap(panel, "terminalShortcut_F" + i), position = key.mapToItem(panel, 0, 0)
                verify(key.width >= 200 && key.height >= 76)
                verify(position.x >= 0 && position.x + key.width <= panel.width)
                verify(position.y >= 0 && position.y + key.height <= panel.height)
                compare(sent.signalArguments[i - 1][0], Qt.Key_F1 + i - 1)
                compare(sent.signalArguments[i - 1][1], Qt.NoModifier)
            }
            compare(sent.count, 12)
            tap(panel, "terminalShortcutKeysTab")
            verify(!panel.functionKeysOpen)
            tap(panel, "terminalShortcut_Ctrl+C")
            compare(sent.signalArguments[12][0], Qt.Key_C)
            compare(sent.signalArguments[12][1], Qt.ControlModifier)
        }
        function test_tap_arms_next_key_and_second_tap_clears_it() {
            var panel = makePanel()
            var ctrl = tap(panel, "terminalModifierCtrl")
            compare(panel.modifierState(Qt.ControlModifier), 1)
            compare(panel.modifierSummary, "CTRL next")
            verify(Qt.colorEqual(ctrl.color, "black"))
            tap(panel, "terminalModifierAlt")
            compare(panel.modifierSummary, "CTRL next / ALT next")
            tap(panel, "terminalModifierCtrl")
            compare(panel.modifierState(Qt.ControlModifier), 0)
            compare(panel.modifierSummary, "ALT next")
            verify(Qt.colorEqual(ctrl.color, "white"))
        }
        function test_hold_locks_once_and_release_does_not_toggle_it_off() {
            var panel = makePanel(), held = spy(panel, "modifierHeld"), tapped = spy(panel, "modifierTapped")
            var ctrl = findChild(panel, "terminalModifierCtrl")
            mousePress(ctrl, ctrl.width / 2, ctrl.height / 2)
            wait(780)
            mouseRelease(ctrl, ctrl.width / 2, ctrl.height / 2)
            wait(30)
            compare(held.count, 1); compare(tapped.count, 0)
            compare(panel.modifierState(Qt.ControlModifier), 2)
            compare(panel.modifierSummary, "CTRL locked")
            tap(panel, "terminalModifierCtrl")
            compare(panel.modifierState(Qt.ControlModifier), 0)
            compare(tapped.count, 1)
        }
        function test_tabs_and_visibility_do_not_consume_armed_modifiers() {
            var panel = makePanel(), sent = spy(panel, "shortcutRequested")
            tap(panel, "terminalModifierCtrl")
            tap(panel, "terminalShortcutFunctionTab")
            tap(panel, "terminalShortcutKeysTab")
            panel.visible = false; panel.visible = true
            compare(panel.modifierState(Qt.ControlModifier), 1)
            compare(sent.count, 0)
            backend.lock(Qt.AltModifier)
            compare(panel.modifierSummary, "CTRL next / ALT locked")
        }
    }
}
