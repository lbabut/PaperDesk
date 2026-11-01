import QtQuick 2.15

Rectangle {
    id: home
    objectName: "terminalHomePanel"
    color: "white"
    property var savedSessions: null
    property bool menuReady: false
    property bool managementOpen: false
    property string message: ""
    property string numberInput: ""
    property bool invalidInput: false
    readonly property int count: savedSessions ? savedSessions.count : 0
    visible: menuReady && !managementOpen
    signal openRequested(int index)
    signal newRequested()
    signal localShellRequested()
    signal closeRequested()

    function resetInput() {
        numberInput = ""
        invalidInput = false
    }
    function requestOpen(index) {
        if (!visible || index < 0 || index >= count) return false
        resetInput()
        message = "Opening connection…"
        openRequested(index)
        return true
    }
    function handleInput(text) {
        if (!visible) return
        // This whole payload belongs to the local menu. Stop at the first
        // Enter, even if opening a connection changes menuReady immediately.
        // Clipboard suffixes can never become input for the new SSH session.
        for (var i = 0; i < Math.min(text.length, 128); ++i) {
            var character = text.charAt(i)
            if (character === "\r" || character === "\n") {
                var number = Number(numberInput)
                if (!invalidInput && /^[1-9][0-9]?$/.test(numberInput) && number >= 1 && number <= count)
                    requestOpen(number - 1)
                else {
                    resetInput()
                    message = count ? "Unknown connection number. Choose 1–" + count + "." : "No saved connections. Choose New connection."
                }
                return
            }
            if (character === "\b" || character === "\x7f") {
                numberInput = numberInput.slice(0, -1)
                invalidInput = false
                message = ""
            } else if (character === "\x1b") {
                // Arrow/function/delete sequences have no menu action. Do
                // not interpret their numeric parameters as profile numbers.
                if (text.length === 1) { resetInput(); message = "" }
                return
            } else if (/^[0-9]$/.test(character)) {
                if (numberInput.length < 3) numberInput += character
                else invalidInput = true
                message = ""
            } else {
                invalidInput = true
                message = "Enter a connection number, then press Enter."
            }
        }
        if (text.length > 128) {
            invalidInput = true
            message = "Enter a connection number, then press Enter."
        }
    }
    onVisibleChanged: if (!visible) resetInput()

    component Action: Rectangle {
        id: button
        property string label: ""
        signal triggered()
        width: (home.width - 80) / 3; height: 80; radius: 8
        color: tap.pressed ? "black" : "white"
        border.width: 2; border.color: "black"
        Text {
            anchors.centerIn: parent; text: button.label
            color: tap.pressed ? "white" : "black"; font.pointSize: 17; font.bold: true
        }
        TapHandler { id: tap; onTapped: button.triggered() }
    }

    Column {
        id: heading
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: 24; spacing: 12
        Text {
            text: "Saved connections"; color: "black"; font.pointSize: 25; font.bold: true
        }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: "Tap a connection, or enter its number and press Enter."
            color: "black"; font.pointSize: 17
        }
        Text {
            objectName: "terminalHomeNumber"
            visible: home.numberInput.length > 0
            text: "Number: " + home.numberInput; color: "black"; font.pointSize: 19; font.bold: true
        }
        Text {
            objectName: "terminalHomeMessage"
            width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
            text: home.message || (home.count ? "" : "No saved connections yet. Choose New connection.")
            visible: text.length > 0; color: "black"; font.pointSize: 17
        }
    }
    ListView {
        id: list
        objectName: "terminalHomeList"
        anchors.top: heading.bottom; anchors.topMargin: 24
        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 24
        anchors.bottom: actions.top; anchors.bottomMargin: 24
        clip: true; spacing: 14
        boundsBehavior: Flickable.StopAtBounds
        model: home.savedSessions
        delegate: Rectangle {
            id: row
            objectName: "terminalHomeSession_" + index
            width: list.width; height: 118; radius: 8
            color: tap.pressed ? "black" : "white"
            border.width: 2; border.color: "black"
            signal triggered()
            onTriggered: home.requestOpen(index)
            Column {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                Text {
                    objectName: "terminalHomeSessionLabel_" + index
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: String(index + 1) + " - " + (String(model.name || "").trim() || String(model.host || ""))
                    color: tap.pressed ? "white" : "black"; font.pointSize: 21; font.bold: true
                }
                Text {
                    width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: String(model.user || "") + "@" + String(model.host || "") + ":" + String(model.port || "")
                    color: tap.pressed ? "white" : "black"; font.pointSize: 16
                }
            }
            TapHandler { id: tap; onTapped: row.triggered() }
        }
    }
    Row {
        id: actions
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: 24; spacing: 16
        Action { objectName: "terminalHomeNew"; label: "New connection"; onTriggered: { home.resetInput(); home.newRequested() } }
        Action { objectName: "terminalHomeLocalShell"; label: "Local shell"; onTriggered: { home.resetInput(); home.localShellRequested() } }
        Action { objectName: "terminalHomeClose"; label: "Close"; onTriggered: { home.resetInput(); home.closeRequested() } }
    }
}
