import QtQuick 2.15
import QtQuick.Controls 2.15
import net.asivery.AppLoad 1.0
import net.asivery.ApploadUtils

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    focus: true
    signal close
    property bool profileLoaded: false
    readonly property int toolbarButtonWidth: 210

    function unloading() { Qt.inputMethod.hide() }

    function showKeyboard(editor) {
        editor.forceActiveFocus()
        Qt.inputMethod.show()
    }

    function fromHex(value) {
        var result = ""
        for (var i = 0; i + 1 < value.length; i += 2)
            result += String.fromCharCode(parseInt(value.substr(i, 2), 16))
        return result
    }

    function toHex(value) {
        var result = ""
        for (var i = 0; i < value.length; ++i) {
            var part = value.charCodeAt(i).toString(16)
            result += part.length < 2 ? "0" + part : part
        }
        return result
    }

    function loadProfile() {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            if (request.status === 0 || request.status === 200) {
                var lines = request.responseText.split("\n")
                for (var i = 0; i < lines.length; ++i) {
                    var split = lines[i].indexOf("=")
                    if (split < 0) continue
                    var key = lines[i].substr(0, split)
                    var value = lines[i].substr(split + 1)
                    if (key === "host") serverInput.text = value
                    else if (key === "user") usernameInput.text = value
                    else if (key === "port") portInput.text = value
                    else if (key === "password_hex") passwordInput.text = fromHex(value)
                }
            }
            root.profileLoaded = true
        }
        request.open("GET", "file:///home/root/.config/paperrdp/profile")
        request.send()
    }

    function connectRdp() {
        if (serverInput.text.trim().length === 0 || usernameInput.text.trim().length === 0) {
            statusText.text = "Server and username are required"
            return
        }
        statusText.text = "Connecting..."
        Qt.inputMethod.hide()
        AppLoadLauncher.launchApplication(
            "external::paperrdp",
            ["--host", serverInput.text.trim(), "--user", usernameInput.text,
             "--password-hex", toHex(passwordInput.text), "--port", portInput.text],
            {}, false)
        // Keep this native frontend alive underneath the external QTFB
        // session.  AppLoad 0.5.x can leave its window shell (the lone "X")
        // behind when an internal frontend unloads while it is launching an
        // external child.  Returning here after RDP exits keeps ownership and
        // keyboard focus valid; CLOSE remains the explicit way back.
        statusText.text = "RDP session launched"
    }

    Component.onCompleted: loadProfile()

    Rectangle {
        id: toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 112
        border.color: "black"
        border.width: 0
        color: "black"

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: "PAPERDESK  /  REMOTE ACCESS"
                color: "white"
                font.pointSize: 11
                font.bold: true
                font.letterSpacing: 2
            }
            Text {
                text: "Remote desktop"
                color: "white"
                font.pointSize: 27
                font.bold: true
            }
        }

        Rectangle {
            objectName: "rdpCloseButton"
            anchors.right: keyboardButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: 70
            radius: 8
            border.color: "white"
            border.width: 2
            color: closeMouse.pressed ? "black" : "white"
            Text { anchors.centerIn: parent; text: "Close"; color: closeMouse.pressed ? "white" : "black"; font.pointSize: 18; font.bold: true }
            TapHandler { id: closeMouse; onTapped: { console.log("PaperDesk RDP action close"); root.close() } }
        }

        Rectangle {
            id: keyboardButton
            objectName: "rdpKeyboardButton"
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: 70
            radius: 8
            border.color: "white"
            border.width: 2
            color: keyboardMouse.pressed ? "black" : "white"
            Text { anchors.centerIn: parent; text: "Keyboard"; color: keyboardMouse.pressed ? "white" : "black"; font.pointSize: 18; font.bold: true }
            TapHandler {
                id: keyboardMouse
                onTapped: {
                    console.log("PaperDesk RDP keyboard opened")
                    root.showKeyboard(usernameInput)
                }
            }
        }
    }

    Column {
        anchors.top: toolbar.bottom
        anchors.topMargin: 46
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 180, 1040)
        spacing: 12

        Text {
            text: "CONNECTION PROFILE"
            color: "black"
            font.pointSize: 13
            font.bold: true
            font.letterSpacing: 2
        }
        Text {
            text: "Connect to a computer"
            color: "black"
            font.pointSize: 29
            font.bold: true
        }
        Text {
            text: "Your saved profile stays on this tablet."
            color: "black"
            font.pointSize: 16
            bottomPadding: 8
        }
        Rectangle {
            width: parent.width
            height: 2
            color: "black"
        }

        Text { text: "SERVER"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black"; topPadding: 6 }
        Rectangle {
            width: parent.width; height: 88; color: "white"; radius: 8
            border.color: "black"
            border.width: serverInput.activeFocus ? 4 : 2
            TextInput {
                id: serverInput; objectName: "serverInput"
                anchors.fill: parent; anchors.margins: 16
                font.pointSize: 24; color: "black"; verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (activeFocus) Qt.inputMethod.show()
            }
        }

        Text { text: "USERNAME"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
        Rectangle {
            width: parent.width; height: 88; color: "white"; radius: 8
            border.color: "black"
            border.width: usernameInput.activeFocus ? 4 : 2
            TextInput {
                id: usernameInput; objectName: "usernameInput"
                anchors.fill: parent; anchors.margins: 16
                font.pointSize: 24; color: "black"; verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (activeFocus) Qt.inputMethod.show()
            }
        }

        Text { text: "PASSWORD"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
        Rectangle {
            width: parent.width; height: 88; color: "white"; radius: 8
            border.color: "black"
            border.width: passwordInput.activeFocus ? 4 : 2
            TextInput {
                id: passwordInput; objectName: "passwordInput"
                anchors.fill: parent; anchors.margins: 16
                font.pointSize: 24; color: "black"; verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                onActiveFocusChanged: if (activeFocus) Qt.inputMethod.show()
            }
        }

        Text { text: "PORT"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
        Rectangle {
            width: parent.width; height: 76; color: "white"; radius: 8
            border.color: "black"
            border.width: portInput.activeFocus ? 4 : 2
            TextInput {
                id: portInput; objectName: "portInput"
                anchors.fill: parent; anchors.margins: 16
                text: "3389"; font.pointSize: 22; color: "black"
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhDigitsOnly
                onActiveFocusChanged: if (activeFocus) Qt.inputMethod.show()
            }
        }

        Rectangle {
            objectName: "connectButton"
            width: parent.width; height: 96; radius: 8; color: connectMouse.pressed ? "white" : "black"; border.color: "black"; border.width: 2
            Text { anchors.centerIn: parent; text: "Connect"; color: connectMouse.pressed ? "black" : "white"; font.pointSize: 24; font.bold: true }
            TapHandler { id: connectMouse; onTapped: { console.log("PaperDesk RDP action connect"); root.connectRdp() } }
        }

        Text {
            id: statusText
            width: parent.width
            text: root.profileLoaded ? "Edit the fields and tap Connect" : "Loading saved profile..."
            color: "black"; font.pointSize: 14; font.bold: true; font.letterSpacing: 0.5; wrapMode: Text.WordWrap
        }
    }

    DisplayMethodArea { anchors.fill: parent; displayMethod: DisplayMethodArea.Fast; z: -1 }
}
