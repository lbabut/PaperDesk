import QtQuick 2.15

Rectangle {
    id: panel
    objectName: "terminalShortcutsPanel"
    color: "white"
    border.color: "black"; border.width: 2
    implicitHeight: 276
    height: implicitHeight
    property int latchedModifiers: 0
    property int lockedModifiers: 0
    property bool functionKeysOpen: false
    readonly property string modifierSummary: summary()
    signal shortcutRequested(int key, int modifiers)
    signal modifierTapped(int modifier)
    signal modifierHeld(int modifier)
    property var normalKeys: [
        { label: "Ctrl+C", key: Qt.Key_C, modifiers: Qt.ControlModifier },
        { label: "Ctrl+D", key: Qt.Key_D, modifiers: Qt.ControlModifier },
        { label: "Ctrl+Z", key: Qt.Key_Z, modifiers: Qt.ControlModifier },
        { label: "Ctrl+L", key: Qt.Key_L, modifiers: Qt.ControlModifier },
        { label: "TAB", key: Qt.Key_Tab, modifiers: Qt.NoModifier },
        { label: "ESC", key: Qt.Key_Escape, modifiers: Qt.NoModifier },
        { label: "LEFT", key: Qt.Key_Left, modifiers: Qt.NoModifier },
        { label: "UP", key: Qt.Key_Up, modifiers: Qt.NoModifier },
        { label: "DOWN", key: Qt.Key_Down, modifiers: Qt.NoModifier },
        { label: "RIGHT", key: Qt.Key_Right, modifiers: Qt.NoModifier }
    ]
    property var functionKeys: [
        { label: "F1", key: Qt.Key_F1, modifiers: Qt.NoModifier },
        { label: "F2", key: Qt.Key_F2, modifiers: Qt.NoModifier },
        { label: "F3", key: Qt.Key_F3, modifiers: Qt.NoModifier },
        { label: "F4", key: Qt.Key_F4, modifiers: Qt.NoModifier },
        { label: "F5", key: Qt.Key_F5, modifiers: Qt.NoModifier },
        { label: "F6", key: Qt.Key_F6, modifiers: Qt.NoModifier },
        { label: "F7", key: Qt.Key_F7, modifiers: Qt.NoModifier },
        { label: "F8", key: Qt.Key_F8, modifiers: Qt.NoModifier },
        { label: "F9", key: Qt.Key_F9, modifiers: Qt.NoModifier },
        { label: "F10", key: Qt.Key_F10, modifiers: Qt.NoModifier },
        { label: "F11", key: Qt.Key_F11, modifiers: Qt.NoModifier },
        { label: "F12", key: Qt.Key_F12, modifiers: Qt.NoModifier }
    ]
    function modifierState(modifier) {
        return (lockedModifiers & modifier) ? 2 : (latchedModifiers & modifier) ? 1 : 0
    }
    function summary() {
        var active = []
        if (modifierState(Qt.ControlModifier))
            active.push("CTRL " + (modifierState(Qt.ControlModifier) === 2 ? "locked" : "next"))
        if (modifierState(Qt.AltModifier))
            active.push("ALT " + (modifierState(Qt.AltModifier) === 2 ? "locked" : "next"))
        return active.join(" / ")
    }

    component Modifier: Rectangle {
        id: button
        property int modifier: 0
        property string label: ""
        readonly property int stateValue: panel.modifierState(modifier)
        width: (panel.width - 60) / 4; height: 76; radius: 8
        color: gesture.pressed || stateValue ? "black" : "white"
        border.width: 2; border.color: "black"
        signal triggered()
        signal held()
        Column {
            anchors.centerIn: parent; spacing: 0
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: button.label; color: gesture.pressed || button.stateValue ? "white" : "black"; font.pointSize: 18; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: button.stateValue === 2 ? "LOCKED" : button.stateValue === 1 ? "NEXT KEY" : "OFF"; color: gesture.pressed || button.stateValue ? "white" : "black"; font.pointSize: 12; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: button.stateValue === 2 ? "Tap: off" : "Tap: next / off · Hold: lock"; color: gesture.pressed || button.stateValue ? "white" : "black"; font.pointSize: 10 }
        }
        TapHandler {
            id: gesture
            property bool holdHandled: false
            longPressThreshold: 0.7
            onPressedChanged: if (pressed) holdHandled = false
            onLongPressed: { holdHandled = true; button.held() }
            onTapped: if (!holdHandled) button.triggered()
        }
    }
    component Tab: Rectangle {
        id: button
        property string label: ""
        property bool selected: false
        signal triggered()
        width: (panel.width - 60) / 4; height: 76; radius: 8
        color: gesture.pressed || selected ? "black" : "white"
        border.width: 2; border.color: "black"
        Text { anchors.centerIn: parent; text: button.label; color: gesture.pressed || button.selected ? "white" : "black"; font.pointSize: 18; font.bold: true }
        TapHandler { id: gesture; onTapped: button.triggered() }
    }
    Row {
        id: controls
        anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12; spacing: 12
        Modifier { objectName: "terminalModifierCtrl"; label: "Ctrl"; modifier: Qt.ControlModifier; onTriggered: panel.modifierTapped(modifier); onHeld: panel.modifierHeld(modifier) }
        Modifier { objectName: "terminalModifierAlt"; label: "Alt"; modifier: Qt.AltModifier; onTriggered: panel.modifierTapped(modifier); onHeld: panel.modifierHeld(modifier) }
        Tab { objectName: "terminalShortcutKeysTab"; label: "Keys"; selected: !panel.functionKeysOpen; onTriggered: panel.functionKeysOpen = false }
        Tab { objectName: "terminalShortcutFunctionTab"; label: "F1–F12"; selected: panel.functionKeysOpen; onTriggered: panel.functionKeysOpen = true }
    }
    Grid {
        anchors.top: controls.bottom; anchors.topMargin: 12
        anchors.left: parent.left; anchors.leftMargin: 12
        columns: 6; columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: panel.functionKeysOpen ? panel.functionKeys : panel.normalKeys
            Rectangle {
                id: keyButton
                objectName: "terminalShortcut_" + modelData.label
                width: (panel.width - 84) / 6; height: 76; radius: 8
                color: gesture.pressed ? "black" : "white"
                border.color: "black"; border.width: 2
                signal triggered()
                onTriggered: panel.shortcutRequested(modelData.key, modelData.modifiers)
                Text { anchors.centerIn: parent; text: modelData.label; color: gesture.pressed ? "white" : "black"; font.pointSize: 17; font.bold: true }
                TapHandler { id: gesture; onTapped: keyButton.triggered() }
            }
        }
    }
}
