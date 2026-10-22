import QtQuick 2.15
import Qt.labs.settings 1.1

Rectangle {
    id: panel
    color: "white"
    property real keyboardInset: 0
    property bool traceTouches: false
    property bool fixtureCrud: false
    property string mode: ""
    property int selectedIndex: -1
    property string message: "Saved connections. Passwords are entered in SSH, not stored here."
    property int deleteIndex: -1
    readonly property int count: sessions.count
    signal connectRequested(string host, string user, string port)
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
    function load() {
        sessions.clear()
        selectedIndex = -1
        deleteIndex = -1
        try {
            var rows = JSON.parse(prefs.sessionsJson)
            if (!Array.isArray(rows)) return
            for (var i = 0; i < rows.length && sessions.count < 32; ++i) {
                var row = rows[i]
                if (row && typeof row.name === "string" && row.name.length <= 80 &&
                    typeof row.host === "string" && typeof row.user === "string" &&
                    typeof row.port === "string" && valid(row.host, row.user, row.port))
                    sessions.append({name: row.name, host: row.host, user: row.user, port: row.port})
            }
        } catch (error) { message = "Saved connections could not be read. You can still use the terminal menu." }
        selectedIndex = sessions.count ? 0 : -1
    }
    function persist() {
        var rows = []
        for (var i = 0; i < sessions.count; ++i) {
            var row = sessions.get(i)
            rows.push({name: row.name, host: row.host, user: row.user, port: row.port})
        }
        prefs.sessionsJson = JSON.stringify(rows)
        if (typeof prefs.sync === "function") prefs.sync()
    }
    function choose(index) {
        if (index < 0 || index >= sessions.count) return
        selectedIndex = index
        mode = ""; deleteIndex = -1
    }
    function edit(adding) {
        if (!adding && selectedIndex < 0) return
        if (adding && sessions.count >= 32) { message = "You can save up to 32 connections."; return }
        var row = adding ? {name: "", host: "", user: "", port: "22"} : sessions.get(selectedIndex)
        if (fixtureCrud) row = {name: adding ? "UI test connection" : "Edited UI test connection", host: "127.0.0.1", user: "paperdesk-test", port: "1"}
        nameField.value = row.name; hostField.value = row.host; userField.value = row.user; portField.value = row.port
        mode = adding ? "add" : "edit"; deleteIndex = -1
        message = adding ? "New SSH connection" : "Edit SSH connection"
    }
    function save() {
        if (mode === "" || !valid(hostField.value.trim(), userField.value.trim(), portField.value)) {
            message = "Enter a valid server, username and port (1–65535)."; return false
        }
        var row = {name: nameField.value.trim().slice(0, 80) || userField.value.trim() + "@" + hostField.value.trim(),
                   host: hostField.value.trim(), user: userField.value.trim(), port: String(Number(portField.value))}
        if (mode === "add") { sessions.append(row); selectedIndex = sessions.count - 1 }
        else if (selectedIndex >= 0 && selectedIndex < sessions.count) sessions.set(selectedIndex, row)
        else return false
        persist(); mode = ""; Qt.inputMethod.hide(); message = "Connection saved. Tap Open to connect."
        return true
    }
    function removeSelected() {
        if (deleteIndex < 0 || deleteIndex >= sessions.count) return
        sessions.remove(deleteIndex); selectedIndex = sessions.count ? Math.min(deleteIndex, sessions.count - 1) : -1
        deleteIndex = -1; persist(); message = "Connection deleted."
    }
    function openSelected() {
        if (selectedIndex < 0 || selectedIndex >= sessions.count) return
        var row = sessions.get(selectedIndex)
        connectRequested(row.host, row.user, row.port)
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
    }
    onVisibleChanged: if (!visible) Qt.inputMethod.hide()
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
            if (!clipped) console.log("PaperDesk SSH target", item.objectName, Math.round(point.x), Math.round(point.y))
        }
        if (item.children) for (var i = 0; i < item.children.length; ++i) logTargets(item.children[i])
    }
    Timer {
        interval: 700; repeat: true; running: panel.visible && panel.traceTouches
        onTriggered: {
            console.log("PaperDesk SSH state", panel.mode || "list", panel.count, panel.selectedIndex,
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
                inputMethodHints: field.digits ? Qt.ImhDigitsOnly : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onActiveFocusChanged: if (activeFocus) { Qt.inputMethod.show(); panel.ensureVisible(field) }
            }
        }
    }

    Row {
        id: heading
        anchors.top: parent.top; anchors.topMargin: 24
        anchors.left: parent.left; anchors.leftMargin: 40
        spacing: 20
        Text { width: panel.width - 320; text: "SSH connections"; font.pointSize: 26; font.bold: true; color: "black" }
        Action { objectName: "sshSessionsBack"; label: "Terminal"; onTriggered: { Qt.inputMethod.hide(); panel.dismissed() } }
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
                        TapHandler { onTapped: panel.choose(index) }
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
            Action { objectName: "sshSessionCancel"; visible: panel.mode !== ""; label: "Cancel"; onTriggered: { panel.mode = ""; Qt.inputMethod.hide() } }
            Action { objectName: "sshSessionSave"; visible: panel.mode !== ""; label: "Save"; primary: true; onTriggered: panel.save() }
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
