import QtQuick 2.15
import Qt.labs.settings 1.1

Rectangle {
    id: panel
    color: "white"
    property real keyboardInset: 0
    property bool traceTouches: false
    property bool fixtureCrud: false
    property var credentialStore: null
    property bool rememberPassword: false
    property bool storedPassword: false
    property var originalConnection: null
    property string editorCredentialId: ""
    property string mode: ""
    property int selectedIndex: -1
    property string message: "Saved connections. Saving a password on this tablet is optional."
    property int deleteIndex: -1
    property var replacementRequest: null
    property bool activeTerminalAvailable: false
    property bool openingFromDoubleTap: false
    readonly property int count: sessions.count
    property alias savedSessions: sessions
    signal connectRequested(string host, string user, string port, string credentialId)
    signal replacementRequested(string host, string user, string port, string credentialId, string expectedToken)
    signal activeTerminalRequested()
    signal dismissed()

    Settings {
        id: prefs
        objectName: "sshSessionSettings"
        category: "PaperDeskSSH"
        property string sessionsJson: "[]"
    }
    ListModel { id: sessions }

    function valid(host, user, port) {
        return /^[a-zA-Z0-9._:%][a-zA-Z0-9._:%-]{0,254}$/.test(host) &&
            /^[a-zA-Z0-9_.@][a-zA-Z0-9_.@-]{0,127}$/.test(user) &&
            /^[0-9]{1,5}$/.test(port) && Number(port) >= 1 && Number(port) <= 65535
    }
    function validCredentialId(id) {
        return typeof id === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)
    }
    function newCredentialId(usedIds) {
        if (!credentialStore) return ""
        for (var attempt = 0; attempt < 8; ++attempt) {
            var id = credentialStore.createCredentialId(), inUse = usedIds && usedIds[id]
            if (!usedIds) {
                for (var i = 0; i < sessions.count; ++i)
                    if (sessions.get(i).credentialId === id) inUse = true
            }
            if (validCredentialId(id) && !inUse) return id
        }
        return ""
    }
    function load() {
        sessions.clear()
        selectedIndex = -1
        deleteIndex = -1
        replacementRequest = null
        replacementClickGuard.stop()
        activeTerminalAvailable = false
        mode = ""
        clearPasswordEditor()
        scroller.contentY = 0
        try {
            var rows = JSON.parse(prefs.sessionsJson)
            if (!Array.isArray(rows)) return
            var usedIds = {}, migrated = false
            for (var i = 0; i < rows.length && sessions.count < 32; ++i) {
                var row = rows[i]
                if (row && typeof row.name === "string" && row.name.length <= 80 &&
                    typeof row.host === "string" && typeof row.user === "string" &&
                    typeof row.port === "string" && valid(row.host, row.user, row.port)) {
                    var keepId = validCredentialId(row.credentialId) && !usedIds[row.credentialId]
                    var id = keepId ? row.credentialId : newCredentialId(usedIds)
                    var remember = keepId && row.rememberPassword === true
                    if (validCredentialId(id)) usedIds[id] = true
                    migrated = migrated || row.credentialId !== id || row.rememberPassword !== remember
                    sessions.append({name: row.name, host: row.host, user: row.user, port: row.port,
                                     credentialId: id, rememberPassword: remember})
                }
            }
            if (migrated) persist()
        } catch (error) { message = "Saved connections could not be read. You can still use the terminal menu." }
        selectedIndex = sessions.count ? 0 : -1
        scroller.contentY = 0
    }
    function persist() {
        var rows = []
        for (var i = 0; i < sessions.count; ++i) {
            var row = sessions.get(i)
            rows.push({name: row.name, host: row.host, user: row.user, port: row.port,
                       credentialId: row.credentialId, rememberPassword: row.rememberPassword})
        }
        prefs.sessionsJson = JSON.stringify(rows)
        if (typeof prefs.sync === "function") prefs.sync()
    }
    function choose(index) {
        if (index < 0 || index >= sessions.count) return
        selectedIndex = index
        mode = ""; deleteIndex = -1
    }
    function showMessage(text) {
        message = text
        scroller.contentY = 0
    }
    function beginReplacement(host, user, port, credentialId, expectedToken) {
        if (!expectedToken || !valid(host, user, port)) return false
        var name = host
        if (selectedIndex >= 0 && selectedIndex < sessions.count) {
            var selected = sessions.get(selectedIndex)
            if (selected.host === host && selected.user === user && selected.port === port &&
                    (selected.rememberPassword ? selected.credentialId : "") === credentialId)
                name = selected.name.trim() || host
        }
        replacementRequest = Object.freeze({name: name, host: host, user: user, port: port,
                                           credentialId: credentialId, expectedToken: expectedToken})
        replacementClickGuard.stop()
        if (openingFromDoubleTap) replacementClickGuard.restart()
        activeTerminalAvailable = true
        Qt.inputMethod.hide()
        return true
    }
    function cancelReplacement() {
        replacementRequest = null
        replacementClickGuard.stop()
        showMessage("Current session kept. You can return to the active terminal.")
    }
    function confirmReplacement() {
        var request = replacementRequest
        if (!request || replacementClickGuard.running) return false
        replacementRequest = null
        replacementRequested(request.host, request.user, request.port, request.credentialId, request.expectedToken)
        return true
    }
    function backToActiveTerminal() {
        replacementRequest = null
        replacementClickGuard.stop()
        activeTerminalRequested()
    }
    function clearPasswordEditor() {
        passwordField.value = ""
        rememberPassword = false
        storedPassword = false
        originalConnection = null
        editorCredentialId = ""
    }
    function cancelEdit() {
        mode = ""
        clearPasswordEditor()
        Qt.inputMethod.hide()
        scroller.contentY = 0
    }
    function edit(adding) {
        if (!adding && selectedIndex < 0) return
        if (adding && sessions.count >= 32) { message = "You can save up to 32 connections."; return }
        var row = adding ? {name: "", host: "", user: "", port: "22", credentialId: newCredentialId(), rememberPassword: false} : sessions.get(selectedIndex)
        if (fixtureCrud) row = {name: adding ? "UI test connection" : "Edited UI test connection", host: "127.0.0.1", user: "paperdesk-test", port: "1",
                               credentialId: row.credentialId, rememberPassword: row.rememberPassword}
        nameField.value = row.name; hostField.value = row.host; userField.value = row.user; portField.value = row.port
        clearPasswordEditor()
        editorCredentialId = validCredentialId(row.credentialId) ? row.credentialId : newCredentialId()
        originalConnection = adding ? null : {host: row.host, user: row.user, port: row.port, rememberPassword: row.rememberPassword}
        storedPassword = !adding && row.rememberPassword && credentialStore &&
            credentialStore.hasSavedPassword(editorCredentialId, row.host, row.user, row.port)
        rememberPassword = row.rememberPassword
        mode = adding ? "add" : "edit"; deleteIndex = -1
        message = adding ? "New SSH connection" : "Edit SSH connection"
        scroller.contentY = 0
    }
    function save() {
        if (mode === "" || !valid(hostField.value.trim(), userField.value.trim(), portField.value)) {
            showMessage("Enter a valid server, username and port (1–65535)."); return false
        }
        if (mode !== "add" && (selectedIndex < 0 || selectedIndex >= sessions.count)) return false
        if (!validCredentialId(editorCredentialId)) {
            showMessage("Connection storage is unavailable. Please reopen the terminal and try again.")
            return false
        }
        var row = {name: nameField.value.trim().slice(0, 80) || userField.value.trim() + "@" + hostField.value.trim(),
                   host: hostField.value.trim(), user: userField.value.trim(), port: String(Number(portField.value)),
                   credentialId: editorCredentialId, rememberPassword: rememberPassword}
        if (!updatePassword(row)) return false
        if (mode === "add") { sessions.append(row); selectedIndex = sessions.count - 1 }
        else if (selectedIndex >= 0 && selectedIndex < sessions.count) sessions.set(selectedIndex, row)
        else return false
        persist(); mode = ""; Qt.inputMethod.hide(); clearPasswordEditor()
        showMessage("Connection saved. Tap Open to connect.")
        return true
    }
    function removeSelected() {
        if (deleteIndex < 0 || deleteIndex >= sessions.count) return
        var row = sessions.get(deleteIndex)
        if (credentialStore && !credentialStore.forgetPassword(row.credentialId)) {
            deleteIndex = -1
            showMessage("The saved password could not be removed. The connection was kept.")
            return
        }
        sessions.remove(deleteIndex); selectedIndex = sessions.count ? Math.min(deleteIndex, sessions.count - 1) : -1
        deleteIndex = -1; persist(); showMessage("Connection deleted.")
    }
    function sameConnection(first, second) {
        return first && second && first.host === second.host && first.user === second.user && first.port === second.port
    }
    function updatePassword(row) {
        if (!credentialStore) {
            if (!rememberPassword && (!originalConnection || !originalConnection.rememberPassword)) return true
            showMessage("Password storage is unavailable. Turn off Remember password to save this connection.")
            return false
        }
        if (rememberPassword) {
            if (passwordField.value.length > 0) {
                // One atomic record binds this profile's ID, endpoint and
                // password. A host edit never requires a second mutation.
                if (!credentialStore.savePassword(row.credentialId, row.host, row.user, row.port, passwordField.value)) {
                    showMessage("The password could not be saved. The connection was not changed.")
                    return false
                }
            } else if (!sameConnection(originalConnection, row) || !storedPassword ||
                       !credentialStore.hasSavedPassword(row.credentialId, row.host, row.user, row.port)) {
                showMessage("Enter a password, or turn off Remember password.")
                return false
            }
        } else if (!credentialStore.forgetPassword(row.credentialId)) {
            showMessage("The saved password could not be removed. The connection was not changed.")
            return false
        }
        return true
    }
    function openSelected() {
        if (selectedIndex < 0 || selectedIndex >= sessions.count) return
        var row = sessions.get(selectedIndex)
        scroller.contentY = 0
        connectRequested(row.host, row.user, row.port, row.rememberPassword ? row.credentialId : "")
    }
    function openIndex(index) {
        if (index < 0 || index >= sessions.count) return false
        choose(index)
        openSelected()
        return true
    }
    function ensureVisible(field) {
        Qt.callLater(function() {
            var p = field.mapToItem(form, 0, 0)
            if (p.y < scroller.contentY + 14) scroller.contentY = Math.max(0, p.y - 14)
            else if (p.y + field.height > scroller.contentY + scroller.height - 14)
                scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height), p.y + field.height - scroller.height + 14)
        })
    }
    onKeyboardInsetChanged: {
        if (nameField.editing) ensureVisible(nameField)
        else if (hostField.editing) ensureVisible(hostField)
        else if (userField.editing) ensureVisible(userField)
        else if (portField.editing) ensureVisible(portField)
        else if (passwordField.editing) ensureVisible(passwordField)
    }
    onVisibleChanged: if (!visible) {
        Qt.inputMethod.hide(); clearPasswordEditor(); mode = ""
        replacementRequest = null; activeTerminalAvailable = false
        replacementClickGuard.stop()
    }
    Component.onCompleted: load()
    function logTargets(item) {
        if (!item.visible) return
        if (item.objectName && item.objectName.indexOf("ssh") === 0 && item.mapToItem && item.width > 0 && item.height > 0) {
            var point = item.mapToItem(null, item.width / 2, item.height / 2)
            var clipped = false, ancestor = item.parent
            while (ancestor) {
                if (ancestor.clip) { var p = item.mapToItem(ancestor, item.width / 2, item.height / 2); if (p.y < 0 || p.y > ancestor.height) clipped = true }
                ancestor = ancestor.parent
            }
            if (!clipped) console.log("Paper Terminal target", item.objectName, Math.round(point.x), Math.round(point.y))
        }
        if (item.children) for (var i = 0; i < item.children.length; ++i) logTargets(item.children[i])
    }
    Timer {
        id: replacementClickGuard
        // A third tap in the same gesture must not click through a newly
        // opened confirmation, even when its button covers the tapped row.
        interval: Math.max(250, Math.min(600, Qt.styleHints.mouseDoubleClickInterval || 400))
        repeat: false
    }
    Timer {
        interval: 700; repeat: true; running: panel.visible && panel.traceTouches
        onTriggered: {
            console.log("Paper Terminal state", panel.mode || "list", panel.count, panel.selectedIndex,
                        Math.round(panel.keyboardInset), Math.round(scroller.contentY))
            panel.logTargets(panel)
        }
    }

    component Action: Rectangle {
        id: button
        property string label: ""
        property bool available: true
        property bool primary: false
        signal triggered()
        width: 190; height: 76; radius: 8
        enabled: available
        color: available && (tap.pressed || primary) ? "black" : "white"
        border.width: 2; border.color: available ? "black" : "#999999"
        Text { anchors.centerIn: parent; text: button.label; color: !button.available ? "#666666" : tap.pressed || button.primary ? "white" : "black"; font.pointSize: 16; font.bold: true }
        TapHandler { id: tap; enabled: button.available; onTapped: button.triggered() }
    }
    component Field: Column {
        id: field
        property string label: ""
        property alias value: input.text
        property bool digits: false
        property bool password: false
        property string hint: ""
        readonly property bool editing: input.activeFocus
        width: form.width; spacing: 10
        Text { text: field.label; font.pointSize: 15; font.bold: true; color: "black" }
        Rectangle {
            width: parent.width; height: 88; radius: 8; color: "white"
            border.width: input.activeFocus ? 4 : 2; border.color: "black"
            TextInput {
                id: input
                objectName: field.objectName + "Input"
                anchors.fill: parent; anchors.margins: 16
                font.pointSize: 23; color: "black"; clip: true; selectByMouse: true
                echoMode: field.password ? TextInput.Password : TextInput.Normal
                cursorVisible: activeFocus && !field.password
                maximumLength: field.password ? 1024 : 32767
                inputMethodHints: field.password ? Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText :
                                  field.digits ? Qt.ImhDigitsOnly : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onActiveFocusChanged: if (activeFocus) { Qt.inputMethod.show(); panel.ensureVisible(field) }
            }
            Text {
                anchors.fill: parent; anchors.margins: 16
                visible: input.text.length === 0 && !input.activeFocus
                text: field.hint; color: "#555555"; font.pointSize: 18
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
        }
    }

    Row {
        id: heading
        anchors.top: parent.top; anchors.topMargin: 24
        anchors.left: parent.left; anchors.leftMargin: 40
        spacing: 20
        Text { width: panel.width - 320; text: "SSH connections"; font.pointSize: 26; font.bold: true; color: "black" }
        Action { objectName: "sshSessionsBack"; label: "Terminal"; onTriggered: { panel.cancelEdit(); panel.dismissed() } }
    }
    Flickable {
        id: scroller
        objectName: "sshSessionScroll"
        anchors.top: heading.bottom; anchors.topMargin: 28
        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 40
        anchors.bottom: parent.bottom; anchors.bottomMargin: panel.keyboardInset + 120
        clip: true; contentHeight: form.height + 20
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        Column {
            id: form
            width: scroller.width; spacing: 20
            Text { width: parent.width; text: panel.message; wrapMode: Text.WordWrap; font.pointSize: 16; color: "black" }
            Action {
                objectName: "sshSessionActiveTerminalBack"
                visible: panel.activeTerminalAvailable && panel.mode === ""
                width: 440; label: "Back to active terminal"
                onTriggered: panel.backToActiveTerminal()
            }
            Column {
                visible: panel.mode === ""
                width: parent.width; spacing: 14
                Repeater {
                    model: sessions
                    delegate: Rectangle {
                        objectName: "sshSessionRow_" + index
                        width: form.width; height: 130; radius: 8
                        color: index === panel.selectedIndex ? "black" : "white"
                        border.width: 2; border.color: "black"
                        Column {
                            anchors.fill: parent; anchors.margins: 20; spacing: 8
                            Text { text: name; width: parent.width; elide: Text.ElideRight; font.pointSize: 20; font.bold: true; color: index === panel.selectedIndex ? "white" : "black" }
                            Text { text: user + "@" + host + ":" + port; width: parent.width; elide: Text.ElideRight; font.pointSize: 16; color: index === panel.selectedIndex ? "white" : "black" }
                        }
                        TapHandler {
                            onTapped: panel.choose(index)
                            onDoubleTapped: {
                                if (!panel.replacementRequest && panel.deleteIndex < 0) {
                                    panel.openingFromDoubleTap = true
                                    try { panel.openIndex(index) }
                                    finally { panel.openingFromDoubleTap = false }
                                }
                            }
                        }
                    }
                }
                Text { visible: !sessions.count; text: "No saved connections yet. Choose New."; font.pointSize: 19; color: "black" }
            }
            Column {
                visible: panel.mode !== ""; width: parent.width; spacing: 22
                Field { id: nameField; objectName: "sshSessionName"; label: "NAME (optional)" }
                Field { id: hostField; objectName: "sshSessionHost"; label: "SERVER" }
                Field { id: userField; objectName: "sshSessionUser"; label: "USERNAME" }
                Field { id: portField; objectName: "sshSessionPort"; label: "PORT"; digits: true }
                Rectangle {
                    objectName: "sshSessionRememberPassword"
                    width: form.width; height: 80; color: "white"
                    Rectangle {
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        width: 52; height: 52; border.width: 3; border.color: "black"
                        color: panel.rememberPassword ? "black" : "white"
                        Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pointSize: 26; font.bold: true }
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 74; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Remember password (optional)"; color: "black"; font.pointSize: 20
                    }
                    TapHandler {
                        onTapped: {
                            panel.rememberPassword = !panel.rememberPassword
                            if (!panel.rememberPassword) passwordField.value = ""
                        }
                    }
                }
                Text {
                    visible: panel.rememberPassword
                    width: parent.width; wrapMode: Text.WordWrap; font.pointSize: 15; color: "black"
                    text: "Stored locally on this tablet, without encryption. Anyone with root access can read it. On the first connection, verify the server key and enter the password manually; later connections can use the saved password."
                }
                Field {
                    id: passwordField; objectName: "sshSessionPassword"; label: "PASSWORD"
                    visible: panel.rememberPassword; password: true
                    hint: panel.storedPassword && panel.sameConnection(panel.originalConnection,
                        {host: hostField.value.trim(), user: userField.value.trim(), port: String(Number(portField.value))})
                        ? "Saved password — leave blank to keep it" : "Enter password"
                }
            }
        }
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.keyboardInset
        height: 108; color: "white"
        Row {
            anchors.centerIn: parent; spacing: 16
            Action { objectName: "sshSessionNew"; visible: panel.mode === ""; label: "New"; onTriggered: panel.edit(true) }
            Action { objectName: "sshSessionOpen"; visible: panel.mode === ""; label: "Open"; primary: true; available: panel.selectedIndex >= 0; onTriggered: panel.openSelected() }
            Action { objectName: "sshSessionEdit"; visible: panel.mode === ""; label: "Edit"; available: panel.selectedIndex >= 0; onTriggered: panel.edit(false) }
            Action { objectName: "sshSessionDelete"; visible: panel.mode === ""; label: "Delete"; available: panel.selectedIndex >= 0; onTriggered: { panel.deleteIndex = panel.selectedIndex; Qt.inputMethod.hide() } }
            Action { objectName: "sshSessionCancel"; visible: panel.mode !== ""; label: "Cancel"; onTriggered: panel.cancelEdit() }
            Action { objectName: "sshSessionSave"; visible: panel.mode !== ""; label: "Save"; primary: true; onTriggered: panel.save() }
        }
    }
    Rectangle {
        id: replacementDialog
        objectName: "sshSessionReplaceConfirmation"
        anchors.fill: parent; visible: panel.replacementRequest !== null; z: 40; color: "white"
        focus: visible
        onVisibleChanged: if (visible) forceActiveFocus()
        Keys.onPressed: function(event) { event.accepted = true }
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent; width: parent.width - 120; spacing: 30
            Text {
                objectName: "sshSessionReplaceTitle"
                text: panel.replacementRequest ? "Close current session and connect to " + panel.replacementRequest.name + "?" : ""
                textFormat: Text.PlainText; width: parent.width; wrapMode: Text.WordWrap
                font.pointSize: 25; font.bold: true; color: "black"
            }
            Text {
                text: panel.replacementRequest ? panel.replacementRequest.user + "@" + panel.replacementRequest.host + ":" + panel.replacementRequest.port : ""
                textFormat: Text.PlainText; width: parent.width; wrapMode: Text.WordWrap
                font.pointSize: 20; color: "black"
            }
            Text {
                text: "This ends the terminal session currently running. Your saved connections stay unchanged."
                textFormat: Text.PlainText; width: parent.width; wrapMode: Text.WordWrap
                font.pointSize: 17; color: "black"
            }
            Row {
                spacing: 20
                Action { objectName: "sshSessionReplaceCancel"; label: "Cancel"; onTriggered: panel.cancelReplacement() }
                Action { objectName: "sshSessionReplaceConfirm"; width: 330; label: "Close and connect"; primary: true; available: !replacementClickGuard.running; onTriggered: panel.confirmReplacement() }
                Action { objectName: "sshSessionReplaceBack"; width: 440; label: "Back to active terminal"; onTriggered: panel.backToActiveTerminal() }
            }
        }
    }
    Rectangle {
        objectName: "sshSessionDeleteConfirmation"
        anchors.fill: parent; visible: panel.deleteIndex >= 0; z: 30; color: "white"
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent; width: parent.width - 120; spacing: 40
            Text { text: "Delete this saved connection?"; width: parent.width; wrapMode: Text.WordWrap; font.pointSize: 25; font.bold: true; color: "black" }
            Row {
                spacing: 20
                Action { objectName: "sshSessionDeleteCancel"; label: "Cancel"; onTriggered: panel.deleteIndex = -1 }
                Action { objectName: "sshSessionDeleteConfirm"; label: "Delete"; onTriggered: panel.removeSelected() }
            }
        }
    }
}
