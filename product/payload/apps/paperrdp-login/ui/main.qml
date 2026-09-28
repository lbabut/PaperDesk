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
    property bool connectionLaunching: false
    property int scalePercent: 100
    property int colorDepth: 16
    property string profileDomain: ""
    property int selectedProfileIndex: -1
    readonly property int savedProfileCount: savedProfiles.count
    readonly property int toolbarButtonWidth: 176
    readonly property int toolbarButtonHeight: 68
    readonly property int actionFontPointSize: 16

    function unloading() { Qt.inputMethod.hide() }

    function showKeyboard(editor) {
        editor.forceActiveFocus()
        Qt.inputMethod.show()
    }

    function fromHex(value) {
        value = String(value || "")
        if (value.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(value))
            return ""
        var encoded = ""
        for (var i = 0; i + 1 < value.length; i += 2)
            encoded += "%" + value.substr(i, 2)
        try { return decodeURIComponent(encoded) } catch (error) {}
        var fallback = ""
        for (var j = 0; j + 1 < value.length; j += 2)
            fallback += String.fromCharCode(parseInt(value.substr(j, 2), 16))
        return fallback
    }

    function toHex(value) {
        var utf8 = unescape(encodeURIComponent(value))
        var result = ""
        for (var i = 0; i < utf8.length; ++i) {
            var part = utf8.charCodeAt(i).toString(16)
            result += part.length < 2 ? "0" + part : part
        }
        return result
    }

    function validScale(value) {
        value = Number(value)
        return value === 50 || value === 75 || value === 100 ? value : 100
    }

    function validColorDepth(value) {
        value = Number(value)
        return value === 8 || value === 16 || value === 24 ? value : 16
    }

    function addSavedProfile(host, user, domain, port, passwordHex, scale, depth) {
        if (!host || !user)
            return
        savedProfiles.append({
            profileHost: host,
            profileUser: user,
            profileDomain: domain || "",
            profilePort: String(port || "3389"),
            profilePasswordHex: passwordHex || "",
            profileScale: validScale(scale),
            profileColorDepth: validColorDepth(depth)
        })
    }

    function parseSavedProfiles(text) {
        savedProfiles.clear()
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; ++i) {
            if (lines[i].length > 8192)
                continue
            var parts = lines[i].split("\t")
            if (parts.length !== 8 || parts[0] !== "v1")
                continue
            if (parts[1].length > 4096 || parts[2].length > 4096 ||
                    parts[3].length > 4096 || parts[5].length > 4096)
                continue
            addSavedProfile(fromHex(parts[1]), fromHex(parts[2]), fromHex(parts[3]),
                            parts[4], parts[5], parts[6], parts[7])
        }
        selectedProfileIndex = savedProfiles.count > 0 ? 0 : -1
    }

    function chooseProfile(index) {
        if (index < 0 || index >= savedProfiles.count)
            return
        var profile = savedProfiles.get(index)
        serverInput.text = profile.profileHost
        usernameInput.text = profile.profileUser
        profileDomain = profile.profileDomain
        portInput.text = profile.profilePort
        passwordInput.text = fromHex(profile.profilePasswordHex)
        scalePercent = validScale(profile.profileScale)
        colorDepth = validColorDepth(profile.profileColorDepth)
        selectedProfileIndex = index
        statusText.text = "Saved profile selected"
        console.log("PaperDesk RDP profile selected", profile.profileHost, profile.profileUser)
    }

    function loadSavedProfiles(fallbackProfile) {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            if ((request.status === 0 || request.status === 200) && request.responseText.trim().length > 0)
                parseSavedProfiles(request.responseText)
            else if (fallbackProfile && fallbackProfile.host && fallbackProfile.user) {
                savedProfiles.clear()
                addSavedProfile(fallbackProfile.host, fallbackProfile.user, fallbackProfile.domain,
                                fallbackProfile.port, fallbackProfile.passwordHex,
                                fallbackProfile.scale, fallbackProfile.depth)
                selectedProfileIndex = 0
            }
            root.profileLoaded = true
        }
        request.open("GET", "file:///home/root/.config/paperrdp/profiles")
        request.send()
    }

    function loadProfile() {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            var fallback = { host: "", user: "", domain: "", port: "3389",
                             passwordHex: "", scale: 100, depth: 16 }
            if (request.status === 0 || request.status === 200) {
                var lines = request.responseText.split("\n")
                for (var i = 0; i < lines.length; ++i) {
                    var split = lines[i].indexOf("=")
                    if (split < 0) continue
                    var key = lines[i].substr(0, split)
                    var value = lines[i].substr(split + 1)
                    if (key === "host") { serverInput.text = value; fallback.host = value }
                    else if (key === "user") { usernameInput.text = value; fallback.user = value }
                    else if (key === "domain") { profileDomain = value; fallback.domain = value }
                    else if (key === "port") { portInput.text = value; fallback.port = value }
                    else if (key === "password_hex") {
                        passwordInput.text = fromHex(value)
                        fallback.passwordHex = value
                    } else if (key === "scale_percent") {
                        scalePercent = validScale(value)
                        fallback.scale = scalePercent
                    } else if (key === "color_depth") {
                        colorDepth = validColorDepth(value)
                        fallback.depth = colorDepth
                    }
                }
            }
            loadSavedProfiles(fallback)
        }
        request.open("GET", "file:///home/root/.config/paperrdp/profile")
        request.send()
    }

    function connectRdp() {
        if (connectionLaunching)
            return
        if (serverInput.text.trim().length === 0 || usernameInput.text.trim().length === 0) {
            statusText.text = "Server and username are required"
            return
        }
        var portNumber = Number(portInput.text)
        if (!isFinite(portNumber) || Math.floor(portNumber) !== portNumber || portNumber < 1 || portNumber > 65535) {
            statusText.text = "Port must be between 1 and 65535"
            return
        }
        connectionLaunching = true
        statusText.text = "Connecting..."
        Qt.inputMethod.hide()
        var current = -1
        for (var i = 0; i < savedProfiles.count; ++i) {
            var candidate = savedProfiles.get(i)
            if (candidate.profileHost === serverInput.text.trim() &&
                    candidate.profileUser === usernameInput.text &&
                    candidate.profileDomain === profileDomain &&
                    candidate.profilePort === portInput.text) {
                current = i
                break
            }
        }
        if (current < 0) {
            savedProfiles.insert(0, {
                profileHost: serverInput.text.trim(), profileUser: usernameInput.text,
                profileDomain: profileDomain, profilePort: portInput.text,
                profilePasswordHex: toHex(passwordInput.text),
                profileScale: scalePercent, profileColorDepth: colorDepth
            })
            if (savedProfiles.count > 8)
                savedProfiles.remove(savedProfiles.count - 1)
            selectedProfileIndex = 0
        } else {
            savedProfiles.setProperty(current, "profilePasswordHex", toHex(passwordInput.text))
            savedProfiles.setProperty(current, "profileScale", scalePercent)
            savedProfiles.setProperty(current, "profileColorDepth", colorDepth)
            selectedProfileIndex = current
        }
        AppLoadLauncher.launchApplication(
            "external::paperrdp",
            ["--host", serverInput.text.trim(), "--user", usernameInput.text,
             "--domain-hex", toHex(profileDomain),
             "--password-hex", toHex(passwordInput.text), "--port", portInput.text,
             "--scale-percent", String(scalePercent), "--color-depth", String(colorDepth)],
            {}, false)
        connectionLaunchGuard.restart()
        // Keep this native frontend alive underneath the external QTFB
        // session.  AppLoad 0.5.x can leave its window shell (the lone "X")
        // behind when an internal frontend unloads while it is launching an
        // external child.  Returning here after RDP exits keeps ownership and
        // keyboard focus valid; CLOSE remains the explicit way back.
        statusText.text = "RDP session launched"
    }

    function gainedFocus() {
        connectionLaunchGuard.stop()
        connectionLaunching = false
        loadProfile()
    }

    Component.onCompleted: {
        loadProfile()
        Qt.callLater(function() {
            var scaleItem = scaleChoices.itemAt(1)
            var colorItem = colorChoices.itemAt(0)
            if (!scaleItem || !colorItem)
                return
            var scaleCenter = scaleItem.mapToItem(root, scaleItem.width / 2, scaleItem.height / 2)
            var colorCenter = colorItem.mapToItem(root, colorItem.width / 2, colorItem.height / 2)
            var connectCenter = connectButton.mapToItem(root, connectButton.width / 2, connectButton.height / 2)
            console.log("PaperDesk RDP layout", Math.round(scaleCenter.x), Math.round(scaleCenter.y),
                        Math.round(colorCenter.x), Math.round(colorCenter.y),
                        Math.round(connectCenter.x), Math.round(connectCenter.y))
        })
    }

    ListModel { id: savedProfiles }

    // The native login remains alive beneath the external QTFB window.  This
    // short guard absorbs an accidental double-tap while launch is in flight,
    // then makes Connect available again when the RDP window later closes.
    Timer {
        id: connectionLaunchGuard
        interval: 900
        repeat: false
        onTriggered: root.connectionLaunching = false
    }

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
                font.pointSize: 10
                font.bold: true
                font.letterSpacing: 2
            }
            Text {
                text: "Remote desktop"
                color: "white"
                font.pointSize: 25
                font.bold: true
            }
        }

        Rectangle {
            id: closeButton
            objectName: "rdpCloseButton"
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: root.toolbarButtonHeight
            radius: 8
            border.color: "white"
            border.width: 2
            color: closeMouse.pressed ? "black" : "white"
            Text {
                objectName: "rdpCloseLabel"
                anchors.centerIn: parent
                text: "Close"
                color: closeMouse.pressed ? "white" : "black"
                font.pointSize: root.actionFontPointSize
                font.bold: true
            }
            TapHandler { id: closeMouse; onTapped: { console.log("PaperDesk RDP action close"); root.close() } }
        }

        Rectangle {
            id: keyboardButton
            objectName: "rdpKeyboardButton"
            anchors.right: closeButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: root.toolbarButtonWidth
            height: root.toolbarButtonHeight
            radius: 8
            border.color: "white"
            border.width: 2
            color: keyboardMouse.pressed ? "black" : "white"
            Text {
                objectName: "rdpKeyboardLabel"
                anchors.centerIn: parent
                text: "Keyboard"
                color: keyboardMouse.pressed ? "white" : "black"
                font.pointSize: root.actionFontPointSize
                font.bold: true
            }
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

        Text {
            text: "SAVED PROFILES"
            font.pointSize: 14
            font.bold: true
            font.letterSpacing: 1
            color: "black"
            topPadding: 6
        }
        Item {
            width: parent.width
            height: 78

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: savedProfiles.count === 0
                text: "Your first connection will appear here."
                font.pointSize: 15
                color: "black"
            }

            Flickable {
                id: savedProfilesFlick
                objectName: "rdpSavedProfilesList"
                anchors.fill: parent
                visible: savedProfiles.count > 0
                clip: true
                contentWidth: savedProfilesRow.width
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: savedProfilesRow
                    height: parent.height
                    spacing: 10

                    Repeater {
                        model: savedProfiles
                        delegate: Rectangle {
                            objectName: "rdpSavedProfileButton_" + index
                            width: Math.min(410, Math.max(250, savedProfileLabel.implicitWidth + 42))
                            height: 68
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 8
                            border.color: "black"
                            border.width: 2
                            color: root.selectedProfileIndex === index ? "black" : "white"

                            Text {
                                id: savedProfileLabel
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                text: profileHost + "  ·  " +
                                      (profileDomain ? profileDomain + "\\" : "") + profileUser
                                color: root.selectedProfileIndex === index ? "white" : "black"
                                font.pointSize: 15
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            TapHandler { onTapped: root.chooseProfile(index) }
                        }
                    }
                }
            }
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

        Text { text: "PERFORMANCE"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
        Row {
            width: parent.width
            height: 118
            spacing: 12

            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                color: "white"
                radius: 8
                border.color: "black"
                border.width: 2

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: "SCALE"
                    font.pointSize: 12
                    font.bold: true
                    color: "black"
                }
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 70
                    spacing: 8
                    Repeater {
                        id: scaleChoices
                        model: [50, 75, 100]
                        delegate: Rectangle {
                            objectName: "rdpScaleButton_" + modelData
                            width: (parent.width - 16) / 3
                            height: parent.height
                            radius: 7
                            border.color: "black"
                            border.width: 2
                            color: root.scalePercent === modelData ? "black" : "white"
                            Text {
                                anchors.centerIn: parent
                                text: modelData + "%"
                                color: root.scalePercent === modelData ? "white" : "black"
                                font.pointSize: 15
                                font.bold: true
                            }
                            TapHandler {
                                onTapped: {
                                    root.scalePercent = modelData
                                    root.selectedProfileIndex = -1
                                    console.log("PaperDesk RDP scale", modelData)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                color: "white"
                radius: 8
                border.color: "black"
                border.width: 2

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: "COLORS"
                    font.pointSize: 12
                    font.bold: true
                    color: "black"
                }
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 70
                    spacing: 8
                    Repeater {
                        id: colorChoices
                        model: [{ bits: 8, label: "256" },
                                { bits: 16, label: "65K" },
                                { bits: 24, label: "16M" }]
                        delegate: Rectangle {
                            objectName: "rdpColorDepthButton_" + modelData.bits
                            width: (parent.width - 16) / 3
                            height: parent.height
                            radius: 7
                            border.color: "black"
                            border.width: 2
                            color: root.colorDepth === modelData.bits ? "black" : "white"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.colorDepth === modelData.bits ? "white" : "black"
                                font.pointSize: 15
                                font.bold: true
                            }
                            TapHandler {
                                onTapped: {
                                    root.colorDepth = modelData.bits
                                    root.selectedProfileIndex = -1
                                    console.log("PaperDesk RDP colors", modelData.bits)
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            width: parent.width
            text: "Lower values are faster. 75% and 256 colors are recommended for reMarkable."
            color: "black"
            font.pointSize: 13
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: connectButton
            objectName: "connectButton"
            width: parent.width; height: 82; radius: 8; color: connectMouse.pressed ? "white" : "black"; border.color: "black"; border.width: 2
            Text {
                objectName: "rdpConnectLabel"
                anchors.centerIn: parent
                text: "Connect"
                color: connectMouse.pressed ? "black" : "white"
                font.pointSize: root.actionFontPointSize
                font.bold: true
            }
            TapHandler {
                id: connectMouse
                enabled: !root.connectionLaunching
                onTapped: { console.log("PaperDesk RDP action connect"); root.connectRdp() }
            }
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
