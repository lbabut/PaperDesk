import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils
import "../native" as Native

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    focus: true

    signal close
    signal mouseReport(int button, bool accepted)
    property bool clearingInput: false
    property bool shortcutsOpen: false
    property bool displayOpen: false
    property bool mouseMode: true
    property bool disposed: false
    property bool runtimeErrorDismissed: false
    property string modifierNotice: ""
    property bool ansiColors: terminalSettings.savedAnsiColors
    property real terminalFontSize: Math.max(16, Math.min(46, terminalSettings.savedFontSize))
    property real pendingFontSize: terminalFontSize
    property int terminalUpdateCount: 0
    property real keyboardInset: calculateKeyboardInset(
        Qt.inputMethod.visible,
        Qt.inputMethod.keyboardRectangle.y,
        Qt.inputMethod.keyboardRectangle.height,
        height)

    readonly property int toolbarButtonWidth: 176
    readonly property real commandButtonWidth: (width - 48 - 4 * 12) / 5
    readonly property real terminalPanelHeight: Math.max(
        shortcutsOpen ? shortcutsPanel.height : 0,
        displayOpen ? displayPanel.height : 0)

    Settings {
        id: terminalSettings
        category: "PaperTerminal"
        property bool savedAnsiColors: false
        property real savedFontSize: 26
    }

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool traceTouches: false
        property bool sshSessionCrud: false
    }

    function refreshTerminal(reason) {
        terminal.redraw()
        if (e2eSettings.traceTouches)
            console.log("PaperDesk Terminal refresh", reason, root.terminalUpdateCount)
    }

    function unloading() {
        disposed = true
        terminal.clearModifiers()
        modifierNotice = ""
        terminal.stop()
        mouseMode = false
        Qt.inputMethod.hide()
    }

    function gainedFocus() {
        if (sessionsPanel.visible) return
        if (Qt.inputMethod.visible) systemInput.forceActiveFocus()
        else terminal.forceActiveFocus()
    }

    function showSystemKeyboard() {
        systemInput.forceActiveFocus()
        Qt.inputMethod.show()
    }

    function hideSystemKeyboard() {
        Qt.inputMethod.hide()
        systemInput.focus = false
        terminal.forceActiveFocus()
        Qt.callLater(function() { root.refreshTerminal("keyboard hidden") })
    }
    function restoreTerminalInput() {
        if (terminal.menuReady) root.hideSystemKeyboard()
        else root.showSystemKeyboard()
    }

    function toggleSystemKeyboard() {
        if (sessionsPanel.visible) {
            if (Qt.inputMethod.visible) Qt.inputMethod.hide()
            else sessionsPanel.message = "Tap a connection field to open the keyboard."
            return
        }
        if (Qt.inputMethod.visible) {
            console.log("PaperDesk Terminal keyboard hidden")
            root.hideSystemKeyboard()
        } else {
            console.log("PaperDesk Terminal keyboard opened")
            root.showSystemKeyboard()
        }
    }

    function openSavedSession(host, user, port, credentialId) {
        if (disposed || !sessionsPanel.valid(host, user, port)) return
        terminal.clearModifiers()
        modifierNotice = ""
        // The native backend starts SSH with an argument vector. Connection
        // values are never typed into a running terminal or remote shell.
        if (terminal.connectTo(host, user, port, credentialId || "")) {
            console.log("Paper Terminal opening saved session")
            sessionsPanel.visible = false
            root.showSystemKeyboard()
        } else {
            var message = terminal.sessionError || "The connection could not be opened. Return to the local menu and try again."
            sessionsPanel.visible = true
            sessionsPanel.replacementRequest = null
            sessionsPanel.activeTerminalAvailable = !!terminal.replacementToken
            sessionsPanel.showMessage(message)
            terminalHome.message = message
            Qt.inputMethod.hide()
            if (terminal.replacementToken)
                sessionsPanel.beginReplacement(host, user, port, credentialId || "", terminal.replacementToken)
        }
    }
    function openReplacingSession(host, user, port, credentialId, expectedToken) {
        if (disposed) return
        terminal.clearModifiers()
        root.modifierNotice = ""
        if (terminal.connectReplacing(host, user, port, credentialId, expectedToken)) {
            sessionsPanel.visible = false
            root.showSystemKeyboard()
        } else {
            sessionsPanel.visible = true
            sessionsPanel.activeTerminalAvailable = terminal.running
            sessionsPanel.showMessage(terminal.sessionError || "The active session changed. Open the saved connection again to continue.")
        }
    }
    function returnToActiveTerminal() {
        sessionsPanel.visible = false
        root.showSystemKeyboard()
        // The Sessions layer hides the input panel as it closes. Refocus on
        // the next event turn so keyboard input returns to the terminal.
        Qt.callLater(function() {
            if (!root.disposed && !sessionsPanel.visible) root.showSystemKeyboard()
        })
    }

    function calculateKeyboardInset(visible, rectangleY, rectangleHeight, viewHeight) {
        if (!visible || viewHeight <= 0)
            return 0
        var reportedHeight = isFinite(rectangleHeight) ? Math.max(0, rectangleHeight) : 0
        var coveredFromTop = isFinite(rectangleY) && rectangleY > 0 && rectangleY < viewHeight
            ? viewHeight - rectangleY : 0
        // On reMarkable OS 3.29 the input method occasionally reports an
        // empty rectangle. Keep the prompt above the native keyboard anyway.
        var safeFallback = viewHeight * 0.38
        // Reserve the expanded controls, terminal frame margins and at least
        // 240 px of rendered terminal when the keyboard reports a large area.
        var maximumInset = Math.max(0, viewHeight - toolbar.height - terminalPanelHeight - 18 - 20 - 32 - 240)
        return Math.min(maximumInset, Math.max(reportedHeight, coveredFromTop, safeFallback))
    }

    function sendShortcut(key, modifiers) {
        console.log("PaperDesk Terminal shortcut", key, modifiers)
        terminal.vkbKeyPress(key, modifiers)
        if (Qt.inputMethod.visible) systemInput.forceActiveFocus()
        else terminal.forceActiveFocus()
    }

    function setAnsiColors(enabled) {
        ansiColors = enabled
        terminalSettings.savedAnsiColors = enabled
        console.log("PaperDesk Terminal display", enabled ? "ansi tones" : "high contrast")
        Qt.callLater(function() { root.refreshTerminal("display mode") })
    }

    function adjustFontSize(delta) {
        terminalFontSize = Math.max(16, Math.min(46, terminalFontSize + delta))
        pendingFontSize = terminalFontSize
        terminalSettings.savedFontSize = terminalFontSize
        console.log("PaperDesk Terminal font size", terminalFontSize)
        Qt.callLater(function() { root.refreshTerminal("font size") })
    }

    function toggleMouseMode() {
        mouseMode = !mouseMode
        shortcutsOpen = false
        displayOpen = false
        var returningFromSessions = sessionsPanel.visible
        sessionsPanel.visible = false
        if (returningFromSessions) root.restoreTerminalInput()
        gestureStatusText.text = mouseMode ? "MOUSE ON — TAP / HOLD" : "MOUSE OFF"
        gestureStatus.visible = true
        gestureStatusTimer.restart()
        console.log("PaperDesk Terminal mouse mode", mouseMode ? "on" : "off")
    }

    function mouseCell(value, cellExtent, maximum) {
        if (!isFinite(cellExtent) || cellExtent <= 0 || maximum <= 0)
            return 1
        return Math.max(1, Math.min(maximum, Math.floor(value / cellExtent) + 1))
    }

    function sendMouseClick(x, y, button) {
        if (!mouseMode)
            return
        var column = mouseCell(x, terminal.cellSize.width, terminal.terminalSize.width)
        var row = mouseCell(y, terminal.cellSize.height, terminal.terminalSize.height)
        var accepted = terminal.sendMouse(column, row, button)
        root.mouseReport(button, accepted)
        console.log("PaperDesk Terminal mouse", button === 2 ? "right" : "left", column, row)
    }

    Keys.onPressed: function(event) {
        if (sessionsPanel.visible) return
        terminal.vkbKeyPress(event.key, event.modifiers, event.text)
        event.accepted = true
    }

    Rectangle {
        id: toolbar
        z: 20
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 208
        color: "black"
        border.color: "black"
        border.width: 2

        Rectangle {
            id: closeButton
            objectName: "terminalCloseButton"
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 18
            width: root.toolbarButtonWidth
            height: 76
            radius: 8
            color: closeMouse.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Close"
                color: closeMouse.pressed ? "white" : "black"
                font.pointSize: 16
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
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 120
            width: root.commandButtonWidth
            height: 76
            radius: 8
            color: keyboardMouse.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: Qt.inputMethod.visible ? "Hide keyboard" : "Keyboard"
                color: keyboardMouse.pressed ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }

            TapHandler {
                id: keyboardMouse
                onTapped: root.toggleSystemKeyboard()
            }
        }

        Rectangle {
            id: mouseButton
            objectName: "terminalMouseButton"
            anchors.right: keyboardButton.left
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 120
            width: root.commandButtonWidth
            height: 76
            radius: 8
            color: mouseTap.pressed || root.mouseMode ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                objectName: "terminalMouseLabel"
                anchors.centerIn: parent
                text: root.mouseMode ? "Mouse on" : "Mouse"
                color: mouseTap.pressed || root.mouseMode ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }

            TapHandler {
                id: mouseTap
                onTapped: root.toggleMouseMode()
            }
        }

        Rectangle {
            id: shortcutsButton
            objectName: "terminalShortcutsButton"
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.top: parent.top
            anchors.topMargin: 120
            width: root.commandButtonWidth
            height: 76
            radius: 8
            color: shortcutsMouse.pressed || root.shortcutsOpen ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Shortcuts"
                color: shortcutsMouse.pressed || root.shortcutsOpen ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }

            TapHandler {
                id: shortcutsMouse
                onTapped: {
                    root.shortcutsOpen = !root.shortcutsOpen
                    root.displayOpen = false
                    var returningFromSessions = sessionsPanel.visible
                    sessionsPanel.visible = false
                    if (returningFromSessions) root.restoreTerminalInput()
                    console.log("PaperDesk Terminal shortcuts", root.shortcutsOpen ? "opened" : "closed")
                }
            }
        }

        Rectangle {
            id: sessionsButton
            objectName: "terminalSessionsButton"
            anchors.right: displayButton.left
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 120
            width: root.commandButtonWidth; height: 76; radius: 8
            border.width: 2; border.color: "white"
            color: sessionsTap.pressed || sessionsPanel.visible ? "black" : "white"
            Text { anchors.centerIn: parent; text: "Sessions"; font.pointSize: 16; font.bold: true; color: sessionsTap.pressed || sessionsPanel.visible ? "white" : "black" }
            TapHandler {
                id: sessionsTap
                onTapped: {
                    root.shortcutsOpen = false; root.displayOpen = false
                    sessionsPanel.visible = !sessionsPanel.visible
                    if (sessionsPanel.visible) { terminal.clearModifiers(); root.modifierNotice = ""; Qt.inputMethod.hide() }
                    else root.restoreTerminalInput()
                }
            }
        }
        Rectangle {
            id: displayButton
            objectName: "terminalDisplayButton"
            anchors.right: mouseButton.left
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 120
            width: root.commandButtonWidth
            height: 76
            radius: 8
            color: displayMouse.pressed || root.displayOpen ? "black" : "white"
            border.color: "white"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Display"
                color: displayMouse.pressed || root.displayOpen ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }

            TapHandler {
                id: displayMouse
                onTapped: {
                    root.displayOpen = !root.displayOpen
                    root.shortcutsOpen = false
                    var returningFromSessions = sessionsPanel.visible
                    sessionsPanel.visible = false
                    if (returningFromSessions) root.restoreTerminalInput()
                    console.log("PaperDesk Terminal display panel", root.displayOpen ? "opened" : "closed")
                }
            }
        }

        Rectangle {
            id: inputFrame
            objectName: "terminalInputFrame"
            visible: Qt.inputMethod.visible && !sessionsPanel.visible
            anchors.left: parent.left
            anchors.leftMargin: 420
            anchors.right: closeButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: closeButton.verticalCenter
            height: 66
            radius: 8
            color: "white"
            border.color: "white"
            border.width: systemInput.activeFocus ? 3 : 2

            Text {
                id: inputHint
                objectName: "terminalInputHint"
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 14
                verticalAlignment: Text.AlignVCenter
                color: "black"
                font.pointSize: 14
                elide: Text.ElideRight
                visible: systemInput.text.length === 0 && systemInput.preeditText.length === 0
                text: terminalHome.visible ? "Connection number + Enter" : "Keyboard input goes to SSH"
            }

            TextInput {
                id: systemInput
                // Committed input is forwarded immediately. The terminal
                // paints its own static caret, avoiding idle e-ink blinking.
                cursorVisible: false
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
                        terminal.vkbKeyPress(event.key, event.modifiers, event.text)
                        event.accepted = true
                    }
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
            objectName: "terminalIdentity"
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: inputFrame.left
            anchors.rightMargin: 24
            anchors.verticalCenter: closeButton.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: "PAPERDESK  /  TERMINAL"
                color: "white"
                font.pointSize: 10
                font.bold: true
                font.letterSpacing: 2
                horizontalAlignment: Text.AlignLeft
            }
            Text {
                width: parent.width
                text: "Paper Terminal"
                elide: Text.ElideRight
                color: "white"
                font.pointSize: 25
                font.bold: true
                horizontalAlignment: Text.AlignLeft
            }
            Text {
                objectName: "terminalModifierStatus"
                width: parent.width
                text: root.modifierNotice || shortcutsPanel.modifierSummary
                visible: text.length > 0
                textFormat: Text.PlainText; elide: Text.ElideRight
                color: "white"; font.pointSize: 14; font.bold: true
            }
        }
    }

    Sessions {
        id: sessionsPanel
        objectName: "terminalSessionsPanel"
        anchors.top: toolbar.bottom
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        z: 30
        visible: false
        keyboardInset: root.keyboardInset
        traceTouches: e2eSettings.traceTouches
        fixtureCrud: e2eSettings.sshSessionCrud
        credentialStore: terminal
        onVisibleChanged: if (visible) {
            root.shortcutsOpen = false; root.displayOpen = false
            terminal.clearModifiers(); root.modifierNotice = ""
        }
        onDismissed: { visible = false; root.restoreTerminalInput() }
        onConnectRequested: function(host, user, port, credentialId) { root.openSavedSession(host, user, port, credentialId) }
        onReplacementRequested: function(host, user, port, credentialId, expectedToken) {
            root.openReplacingSession(host, user, port, credentialId, expectedToken)
        }
        onActiveTerminalRequested: root.returnToActiveTerminal()
    }
    Shortcuts {
        id: shortcutsPanel
        z: 40
        visible: root.shortcutsOpen
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        latchedModifiers: terminal.latchedModifiers
        lockedModifiers: terminal.lockedModifiers
        onShortcutRequested: function(key, modifiers) { root.sendShortcut(key, modifiers) }
        onModifierTapped: function(modifier) { terminal.cycleModifier(modifier) }
        onModifierHeld: function(modifier) { terminal.lockModifier(modifier) }
    }

    Rectangle {
        id: displayPanel
        objectName: "terminalDisplayPanel"
        z: 40
        visible: root.displayOpen
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 108
        color: "white"
        border.color: "black"
        border.width: 2

        Row {
            anchors.centerIn: parent
            spacing: 10

            Repeater {
                model: [
                    { target: "terminalDisplayHighContrast", label: "High contrast", selected: !root.ansiColors, action: "contrast" },
                    { target: "terminalDisplayAnsi", label: "ANSI tones", selected: root.ansiColors, action: "ansi" },
                    { target: "terminalDisplaySmaller", label: "Text −", selected: false, action: "smaller" },
                    { target: "terminalDisplayLarger", label: "Text +", selected: false, action: "larger" },
                    { target: "terminalDisplayRefresh", label: "Refresh", selected: false, action: "refresh" }
                ]

                Rectangle {
                    objectName: modelData.target
                    width: 232
                    height: 76
                    radius: 8
                    color: displayChoiceTap.pressed || modelData.selected ? "black" : "white"
                    border.color: "black"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: displayChoiceTap.pressed || modelData.selected ? "white" : "black"
                        font.pointSize: 16
                        font.bold: true
                    }

                    TapHandler {
                        id: displayChoiceTap
                        onTapped: {
                            if (modelData.action === "contrast")
                                root.setAnsiColors(false)
                            else if (modelData.action === "ansi")
                                root.setAnsiColors(true)
                            else if (modelData.action === "smaller")
                                root.adjustFontSize(-2)
                            else if (modelData.action === "larger")
                                root.adjustFontSize(2)
                            else
                                root.refreshTerminal("manual")
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: terminalArea
        anchors.top: toolbar.bottom
        anchors.topMargin: 18 + root.terminalPanelHeight
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

        Native.TerminalView {
            id: terminal
            objectName: "terminalRenderer"
            anchors.fill: parent
            anchors.margins: 16
            focus: true
            font.family: "DejaVu Sans Mono"
            font.pointSize: root.terminalFontSize
            ansiColors: root.ansiColors

            onTerminalQuit: root.close()
            onErrorChanged: root.runtimeErrorDismissed = false
            onMenuReadyChanged: {
                if (menuReady && !sessionsPanel.visible && !root.disposed) {
                    clearModifiers()
                    root.modifierNotice = ""
                    terminalHome.message = ""
                    root.hideSystemKeyboard()
                }
            }
            onMenuInput: function(text) { if (terminalHome.visible) terminalHome.handleInput(text) }
            onModifiersChanged: root.modifierNotice = ""
            onInputRejected: function(reason) {
                root.modifierNotice = reason
                modifierNoticeTimer.restart()
            }
            onDisplayBufferChanged: {
                root.terminalUpdateCount += 1
                if (e2eSettings.traceTouches)
                    console.log("PaperDesk Terminal display changed", root.terminalUpdateCount)
            }
            Component.onCompleted: { start(); forceActiveFocus() }
            Component.onDestruction: stop()

            DisplayMethodArea {
                anchors.fill: parent
                // AppLoad applies this waveform only to the terminal region.
                // The native renderer coalesces dirty rows; it never blinks.
                displayMethod: DisplayMethodArea.Fast
            }

            MultiPointTouchArea {
                id: terminalTouch
                objectName: "terminalTouchArea"
                anchors.fill: parent
                minimumTouchPoints: 1
                maximumTouchPoints: 2
                property int activePoint: -1
                property var pointState: ({})
                property bool pinchActive: false
                property bool suppressScroll: false
                property real pinchStartDistance: 1
                property real pinchStartFont: root.terminalFontSize
                property real mouseStartX: 0
                property real mouseStartY: 0
                property bool mouseMoved: false
                property bool rightClickSent: false

                Timer {
                    id: mouseHoldTimer
                    interval: 700
                    repeat: false
                    onTriggered: {
                        if (!root.mouseMode || terminalTouch.activePoint === -1 || terminalTouch.mouseMoved || terminalTouch.pinchActive)
                            return
                        root.sendMouseClick(terminalTouch.mouseStartX, terminalTouch.mouseStartY, 2)
                        terminalTouch.rightClickSent = true
                    }
                }

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
                        if (oldPoint !== undefined && !root.mouseMode)
                            terminal.mouseRelease(oldPoint.x, oldPoint.y)
                        mouseHoldTimer.stop()
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
                    terminalSettings.savedFontSize = root.terminalFontSize
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
                        if (root.mouseMode) {
                            mouseStartX = points[0].x
                            mouseStartY = points[0].y
                            mouseMoved = false
                            rightClickSent = false
                            mouseHoldTimer.restart()
                        } else {
                            terminal.mousePress(points[0].x, points[0].y)
                        }
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
                            if (root.mouseMode) {
                                var dx = points[i].x - mouseStartX
                                var dy = points[i].y - mouseStartY
                                if (Math.sqrt(dx * dx + dy * dy) > 28) {
                                    mouseMoved = true
                                    mouseHoldTimer.stop()
                                }
                            } else {
                                terminal.mouseMove(points[i].x, points[i].y)
                            }
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
                            if (root.mouseMode) {
                                mouseHoldTimer.stop()
                                if (!rightClickSent && !mouseMoved)
                                    root.sendMouseClick(points[i].x, points[i].y, 0)
                            } else {
                                terminal.mouseRelease(points[i].x, points[i].y)
                            }
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
                    mouseHoldTimer.stop()
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
        Home {
            id: terminalHome
            anchors.fill: parent; anchors.margins: 16; z: 10
            menuReady: terminal.menuReady
            managementOpen: sessionsPanel.visible
            savedSessions: sessionsPanel.savedSessions
            onOpenRequested: function(index) { sessionsPanel.openIndex(index) }
            onNewRequested: {
                terminal.clearModifiers()
                root.modifierNotice = ""
                root.shortcutsOpen = false; root.displayOpen = false
                sessionsPanel.visible = true
                Qt.inputMethod.hide()
                sessionsPanel.edit(true)
            }
            onLocalShellRequested: {
                terminal.clearModifiers()
                root.modifierNotice = ""
                if (terminal.sendMenuCommand("l")) root.showSystemKeyboard()
                else message = terminal.sessionError || "The local menu is not ready. Try again."
            }
            onCloseRequested: root.close()
        }
    }

    Rectangle {
        objectName: "terminalErrorPanel"
        z: 60
        anchors.left: terminalArea.left
        anchors.right: terminalArea.right
        anchors.bottom: terminalArea.bottom
        color: "white"
        border.color: "black"
        border.width: 2
        visible: terminal.error.length > 0 && !sessionsPanel.visible && !root.runtimeErrorDismissed
        height: Math.max(110, terminalErrorText.implicitHeight + 36)
        Text {
            id: terminalErrorText
            anchors.left: parent.left; anchors.right: retryButton.left
            anchors.margins: 18
            anchors.verticalCenter: parent.verticalCenter
            text: terminal.error
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: "black"
            font.pointSize: 16
        }
        Rectangle {
            id: retryButton
            objectName: "terminalRetryButton"
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 180; height: 76
            color: retryTap.pressed ? "black" : "white"
            border.color: "black"; border.width: 2; radius: 8
            Text {
                anchors.centerIn: parent; text: terminal.running ? "Dismiss" : "Open menu"
                color: retryTap.pressed ? "white" : "black"
                font.pointSize: 16
            }
            TapHandler {
                id: retryTap
                onTapped: {
                    if (terminal.running) root.runtimeErrorDismissed = true
                    else terminal.start()
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
        id: modifierNoticeTimer
        interval: 4000; repeat: false
        onTriggered: root.modifierNotice = ""
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                terminal.clearModifiers()
                root.modifierNotice = ""
            }
        }
    }

    Component.onCompleted: {
        terminal.forceActiveFocus()
    }
}
