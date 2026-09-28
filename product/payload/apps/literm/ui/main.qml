import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.1
import literm 1.0

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    focus: true

    signal close
    property bool clearingInput: false
    property bool shortcutsOpen: false
    property real terminalFontSize: Math.max(26, Util.fontSize)
    property real pendingFontSize: terminalFontSize
    property int terminalUpdateCount: 0
    property real keyboardInset: Qt.inputMethod.visible
        ? Math.max(0, Qt.inputMethod.keyboardRectangle.height) : 0
    property var shortcutKeys: [
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

    readonly property int toolbarButtonWidth: 172

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool traceTouches: false
    }

    function refreshTerminal(reason) {
        terminal.redraw()
        terminalContent.opacity = terminalContent.opacity === 1.0 ? 0.999 : 1.0
        if (root.Window.window !== null)
            root.Window.window.update()
        if (e2eSettings.traceTouches)
            console.log("PaperDesk Terminal refresh", reason, root.terminalUpdateCount)
    }

    function unloading() {
        Qt.inputMethod.hide()
    }

    function gainedFocus() {
        terminal.forceActiveFocus()
    }

    function showSystemKeyboard() {
        systemInput.forceActiveFocus()
        Qt.inputMethod.show()
        inputHint.visible = false
    }

    function sendShortcut(key, modifiers) {
        console.log("PaperDesk Terminal shortcut", key, modifiers)
        terminal.vkbKeyPress(key, modifiers)
        systemInput.forceActiveFocus()
        Qt.inputMethod.show()
    }

    Keys.onPressed: function(event) {
        terminal.vkbKeyPress(event.key, event.modifiers)
        event.accepted = true
    }

    Rectangle {
        id: toolbar
        z: 20
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 112
        color: "black"
        border.color: "black"
        border.width: 2

        Rectangle {
            id: closeButton
            objectName: "terminalCloseButton"
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: 70
            radius: 8
            color: closeMouse.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Close"
                color: closeMouse.pressed ? "white" : "black"
                font.pointSize: 18
                font.bold: true
            }

            TapHandler {
                id: closeMouse
                onTapped: {
                    console.log("PaperDesk Terminal action close")
                    root.close()
                }
            }
        }

        Rectangle {
            id: keyboardButton
            objectName: "terminalKeyboardButton"
            anchors.right: shortcutsButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: 70
            radius: 8
            color: keyboardMouse.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: Qt.inputMethod.visible ? "Keyboard on" : "Keyboard"
                color: keyboardMouse.pressed ? "white" : "black"
                font.pointSize: 17
                font.bold: true
            }

            TapHandler {
                id: keyboardMouse
                onTapped: {
                    console.log("PaperDesk Terminal keyboard opened")
                    root.showSystemKeyboard()
                }
            }
        }

        Rectangle {
            id: shortcutsButton
            objectName: "terminalShortcutsButton"
            anchors.right: closeButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: 70
            radius: 8
            color: shortcutsMouse.pressed || root.shortcutsOpen ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: root.shortcutsOpen ? "Shortcuts ↑" : "Shortcuts ↓"
                color: shortcutsMouse.pressed || root.shortcutsOpen ? "white" : "black"
                font.pointSize: 17
                font.bold: true
            }

            TapHandler {
                id: shortcutsMouse
                onTapped: {
                    root.shortcutsOpen = !root.shortcutsOpen
                    console.log("PaperDesk Terminal shortcuts", root.shortcutsOpen ? "opened" : "closed")
                }
            }
        }

        Rectangle {
            id: inputFrame
            visible: Qt.inputMethod.visible
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.right: keyboardButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: 66
            radius: 8
            color: "white"
            border.color: "white"
            border.width: systemInput.activeFocus ? 3 : 2

            Text {
                id: inputHint
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: Text.AlignVCenter
                color: "black"
                font.pointSize: 14
                elide: Text.ElideRight
                text: "Tap here or select KEYBOARD"
            }

            TextInput {
                id: systemInput
                // A visible editor is required for the native reMarkable input
                // panel. Committed text is forwarded to the PTY and cleared.
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                color: "black"
                font.pointSize: 16
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData

                onTextChanged: {
                    if (root.clearingInput || text.length === 0)
                        return
                    var committed = text
                    root.clearingInput = true
                    text = ""
                    root.clearingInput = false
                    terminal.putString(committed)
                }

                Keys.onPressed: function(event) {
                    var special = event.key === Qt.Key_Return ||
                                  event.key === Qt.Key_Enter ||
                                  event.key === Qt.Key_Backspace ||
                                  event.key === Qt.Key_Delete ||
                                  event.key === Qt.Key_Tab ||
                                  event.key === Qt.Key_Escape ||
                                  event.key === Qt.Key_Left ||
                                  event.key === Qt.Key_Right ||
                                  event.key === Qt.Key_Up ||
                                  event.key === Qt.Key_Down ||
                                  event.key === Qt.Key_Home ||
                                  event.key === Qt.Key_End ||
                                  event.key === Qt.Key_PageUp ||
                                  event.key === Qt.Key_PageDown
                    var chord = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) !== 0
                    if (special || chord) {
                        terminal.vkbKeyPress(event.key, event.modifiers)
                        event.accepted = true
                    }
                }

                onActiveFocusChanged: {
                    inputHint.visible = !activeFocus
                    if (activeFocus)
                        inputHint.text = "Type here — text goes directly to the terminal"
                }
            }

            TapHandler {
                enabled: !systemInput.activeFocus
                onTapped: {
                    console.log("PaperDesk Terminal action input focus")
                    root.showSystemKeyboard()
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: keyboardButton.left
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            visible: !inputFrame.visible
            spacing: 1
            Text {
                width: parent.width
                text: "PAPERDESK  /  SSH"
                color: "white"
                font.pointSize: 10
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignLeft
            }
            Text {
                width: parent.width
                text: "Terminal"
                color: "white"
                font.pointSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    Rectangle {
        id: shortcutsPanel
        z: 40
        visible: root.shortcutsOpen
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 108
        color: "white"
        border.color: "black"
        border.width: 2

        Row {
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: root.shortcutKeys

                Rectangle {
                    objectName: "terminalShortcut_" + modelData.label
                    width: 126
                    height: 68
                    radius: 8
                    color: shortcutMouse.pressed ? "black" : "white"
                    border.color: "black"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: shortcutMouse.pressed ? "white" : "black"
                        font.pointSize: 15
                        font.bold: true
                    }

                    TapHandler {
                        id: shortcutMouse
                        onTapped: root.sendShortcut(modelData.key, modelData.modifiers)
                    }
                }
            }
        }
    }

    Rectangle {
        id: terminalArea
        anchors.top: toolbar.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.keyboardInset + 20
        color: "white"
        border.color: "black"
        border.width: 2
        radius: 8

        TextRender {
            id: terminal
            anchors.fill: parent
            anchors.margins: 16
            focus: true
            font.family: Util.fontFamily
            font.pointSize: root.terminalFontSize
            // LiTerm fades rows below cutAfter. Without this property its
            // default is zero, which made every terminal glyph 30% opaque.
            property int cutAfter: height
            dragMode: Util.dragMode
            allowGestures: true

            // LiTerm updates its QML delegates when terminal data arrives,
            // but xochitl does not always mark that composed area dirty for
            // the e-ink panel. Batch output and nudge the whole terminal layer
            // at most four times per second.
            onDisplayBufferChanged: {
                root.terminalUpdateCount += 1
                if (e2eSettings.traceTouches)
                    console.log("PaperDesk Terminal display changed", root.terminalUpdateCount)
                if (!screenRefreshTimer.running)
                    screenRefreshTimer.start()
            }

            contentItem: Item {
                id: terminalContent
                width: parent.width
                height: parent.height
            }

            // Consume ANSI foreground/background colors on the delegate root,
            // but render the actual cell as high-contrast monochrome.
            cellDelegate: Item {
                property color color: "white"
                Rectangle {
                    anchors.fill: parent
                    color: "white"
                }
            }
            cellContentsDelegate: Item {
                id: monochromeCell
                property string text: ""
                property color color: "black"
                property font font
                property bool blinking: false
                width: monochromeText.implicitWidth

                Text {
                    id: monochromeText
                    anchors.fill: parent
                    text: monochromeCell.text
                    textFormat: Text.PlainText
                    color: "black"
                    font.family: monochromeCell.font.family
                    font.pointSize: monochromeCell.font.pointSize
                    font.bold: true
                    font.italic: monochromeCell.font.italic
                    font.underline: monochromeCell.font.underline
                }
            }
            cursorDelegate: Rectangle {
                color: "black"
                opacity: 0.8
            }
            selectionDelegate: Rectangle {
                color: "black"
                opacity: 0.2
            }

            onTerminalQuit: root.close()

            Component.onCompleted: {
                setBackgroundWhite(true)
                forceActiveFocus()
                Qt.callLater(function() { root.refreshTerminal("component ready") })
            }

            onHeightChanged: Qt.callLater(function() { terminal.redraw() })

            MultiPointTouchArea {
                anchors.fill: parent
                minimumTouchPoints: 1
                maximumTouchPoints: 2
                property int activePoint: -1
                property var pointState: ({})
                property bool pinchActive: false
                property bool suppressScroll: false
                property real pinchStartDistance: 1
                property real pinchStartFont: root.terminalFontSize

                function remember(points) {
                    for (var i = 0; i < points.length; ++i)
                        pointState[points[i].pointId] = { x: points[i].x, y: points[i].y }
                }

                function pointIds() {
                    return Object.keys(pointState)
                }

                function distanceBetween(first, second) {
                    var dx = first.x - second.x
                    var dy = first.y - second.y
                    return Math.sqrt(dx * dx + dy * dy)
                }

                function beginPinch() {
                    var ids = pointIds()
                    if (ids.length < 2)
                        return
                    if (activePoint !== -1) {
                        var oldPoint = pointState[activePoint]
                        if (oldPoint !== undefined)
                            terminal.mouseRelease(oldPoint.x, oldPoint.y)
                        activePoint = -1
                    }
                    suppressScroll = true
                    pinchActive = true
                    pinchStartDistance = Math.max(1, distanceBetween(pointState[ids[0]], pointState[ids[1]]))
                    pinchStartFont = root.terminalFontSize
                    root.pendingFontSize = root.terminalFontSize
                }

                function updatePinch() {
                    var ids = pointIds()
                    if (!pinchActive || ids.length < 2)
                        return
                    var distance = distanceBetween(pointState[ids[0]], pointState[ids[1]])
                    root.pendingFontSize = Math.max(16, Math.min(46,
                        pinchStartFont * distance / pinchStartDistance))
                    gestureStatusText.text = "SIZE " + Math.round(root.pendingFontSize) + " pt"
                    gestureStatus.visible = true
                }

                function finishPinch() {
                    if (!pinchActive)
                        return
                    root.terminalFontSize = Math.round(root.pendingFontSize)
                    pinchActive = false
                    gestureStatusText.text = "SIZE " + Math.round(root.terminalFontSize) + " pt"
                    gestureStatusTimer.restart()
                    Qt.callLater(function() { terminal.redraw() })
                }

                onPressed: function(points) {
                    remember(points)
                    if (pointIds().length >= 2) {
                        beginPinch()
                    } else if (points.length > 0 && activePoint === -1 && !suppressScroll) {
                        activePoint = points[0].pointId
                        terminal.mousePress(points[0].x, points[0].y)
                    }
                }
                onUpdated: function(points) {
                    remember(points)
                    if (pinchActive) {
                        updatePinch()
                        return
                    }
                    for (var i = 0; i < points.length; ++i) {
                        if (points[i].pointId === activePoint) {
                            terminal.mouseMove(points[i].x, points[i].y)
                            break
                        }
                    }
                }
                onReleased: function(points) {
                    remember(points)
                    if (pinchActive)
                        finishPinch()
                    for (var i = 0; i < points.length; ++i) {
                        if (points[i].pointId === activePoint) {
                            terminal.mouseRelease(points[i].x, points[i].y)
                            activePoint = -1
                            break
                        }
                        delete pointState[points[i].pointId]
                    }
                    for (var j = 0; j < points.length; ++j)
                        delete pointState[points[j].pointId]
                    if (pointIds().length === 0)
                        suppressScroll = false
                }
                onCanceled: function(points) {
                    if (pinchActive)
                        finishPinch()
                    pointState = ({})
                    activePoint = -1
                    suppressScroll = false
                }
            }

            Rectangle {
                id: gestureStatus
                z: 30
                visible: false
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 18
                width: 270
                height: 68
                radius: 8
                color: "white"
                border.color: "black"
                border.width: 2

                Text {
                    id: gestureStatusText
                    anchors.centerIn: parent
                    color: "black"
                    font.pointSize: 17
                    font.bold: true
                }
            }
        }
    }

    Timer {
        id: gestureStatusTimer
        interval: 900
        repeat: false
        onTriggered: gestureStatus.visible = false
    }

    Timer {
        id: screenRefreshTimer
        interval: 180
        repeat: false
        onTriggered: root.refreshTerminal("output")
    }

    Timer {
        id: startupRefreshTimer
        interval: 700
        repeat: true
        property int remaining: 3
        onTriggered: {
            root.refreshTerminal("startup")
            remaining -= 1
            if (remaining <= 0)
                stop()
        }
    }

    Component.onCompleted: {
        terminal.forceActiveFocus()
        startupRefreshTimer.start()
    }
}
