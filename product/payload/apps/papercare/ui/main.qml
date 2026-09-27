import QtQuick 2.15
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.1
import net.asivery.AppLoad 1.0

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    signal close

    readonly property string currentVersion: "1.1.2"
    readonly property string manifestUrl: "http://192.168.1.40:8090/update/latest.json"
    property string latestVersion: "—"
    property string publishedAt: ""
    property string releaseNotes: ""
    property string state: "checking"
    property string statusMessage: "Checking for updates…"
    property bool requestActive: false
    property bool uninstallConfirming: false
    property bool uninstallConfirmReady: false
    property var manifestRequest: null
    property var statusRequest: null

    component ActionButton: Rectangle {
        id: button
        property string label: "Action"
        property bool primary: false
        property bool available: true
        signal triggered
        radius: 8
        color: !available ? "#eeeeee" : (tap.pressed || primary ? "black" : "white")
        border.color: available ? "black" : "#888888"
        border.width: 2
        opacity: available ? 1 : 0.62
        Text {
            anchors.centerIn: parent
            text: button.label
            color: !button.available ? "#555555" : (tap.pressed || button.primary ? "white" : "black")
            font.pointSize: 15
            font.bold: true
        }
        TapHandler {
            id: tap
            enabled: button.available
            onTapped: button.triggered()
        }
    }

    Settings {
        id: updateSettings
        category: "PaperDeskUpdate"
        property bool installRequested: false
        property bool uninstallRequested: false
        property string requestedVersion: ""
    }

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool traceTouches: false
    }

    function versionParts(value) {
        var raw = String(value || "0").split(".")
        return [parseInt(raw[0] || "0"), parseInt(raw[1] || "0"), parseInt(raw[2] || "0")]
    }

    function isNewer(candidate, installed) {
        var a = versionParts(candidate)
        var b = versionParts(installed)
        for (var i = 0; i < 3; ++i) {
            if (a[i] > b[i]) return true
            if (a[i] < b[i]) return false
        }
        return false
    }

    function readableNotes(notes) {
        if (!notes || notes.length === 0)
            return "No release notes were supplied."
        var lines = []
        for (var i = 0; i < notes.length; ++i)
            lines.push("•  " + String(notes[i]))
        return lines.join("\n\n")
    }

    function applyManifest(payload) {
        if (!payload || payload.product !== "PaperDesk" || !payload.version ||
                !payload.archiveUrl || !payload.archiveSha256)
            return false
        latestVersion = String(payload.version)
        publishedAt = String(payload.publishedAt || "")
        releaseNotes = readableNotes(payload.releaseNotes)
        if (isNewer(latestVersion, currentVersion)) {
            state = "available"
            statusMessage = "A new version is ready"
        } else {
            state = "current"
            statusMessage = "PaperDesk is up to date"
        }
        if (e2eSettings.traceTouches)
            e2eGeometryLog.restart()
        console.log("PaperDesk Care manifest", latestVersion, state)
        return true
    }

    function checkForUpdates() {
        if (manifestRequest) {
            manifestRequest.abort()
            manifestRequest = null
        }
        state = "checking"
        statusMessage = "Checking for updates…"
        var xhr = new XMLHttpRequest()
        manifestRequest = xhr
        xhr.open("GET", manifestUrl)
        xhr.setRequestHeader("Cache-Control", "no-cache")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            manifestRequest = null
            if (xhr.status >= 200 && xhr.status < 400) {
                try {
                    if (!applyManifest(JSON.parse(String(xhr.responseText || ""))))
                        throw new Error("invalid manifest")
                } catch (error) {
                    state = "error"
                    statusMessage = "The update information is invalid"
                }
            } else {
                state = "offline"
                statusMessage = "Update server is unavailable"
            }
        }
        xhr.send()
        console.log("PaperDesk Care action check")
    }

    function requestInstall() {
        if (state !== "available" || requestActive)
            return
        requestActive = true
        updateSettings.requestedVersion = latestVersion
        updateSettings.installRequested = true
        state = "queued"
        statusMessage = "Update queued — PaperDesk will restart"
        console.log("PaperDesk Care action install", latestVersion)
    }

    function beginUninstall() {
        if (requestActive)
            return
        uninstallConfirming = true
        uninstallConfirmReady = false
        uninstallConfirmDelay.restart()
        console.log("PaperDesk Care action uninstall confirmation")
    }

    function cancelUninstall() {
        uninstallConfirming = false
        uninstallConfirmReady = false
        uninstallConfirmDelay.stop()
        console.log("PaperDesk Care action uninstall cancel")
    }

    function requestUninstall() {
        if (!uninstallConfirming || !uninstallConfirmReady || requestActive)
            return
        uninstallConfirming = false
        requestActive = true
        updateSettings.requestedVersion = ""
        updateSettings.installRequested = false
        updateSettings.uninstallRequested = true
        state = "queued"
        statusMessage = "Removing PaperDesk…"
        console.log("PaperDesk Care action uninstall confirmed")
    }

    function pollInstallStatus() {
        if (!requestActive || statusRequest)
            return
        var xhr = new XMLHttpRequest()
        statusRequest = xhr
        xhr.open("GET", "file:///home/root/.local/share/paperdesk/update-status.json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            statusRequest = null
            if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 400)) {
                try {
                    var result = JSON.parse(String(xhr.responseText || ""))
                    if (result.state === "error") {
                        state = "error"
                        statusMessage = String(result.message || "Update failed")
                        requestActive = false
                    } else if (result.state === "checking" || result.state === "downloading" ||
                               result.state === "installing" || result.state === "uninstalling") {
                        state = "queued"
                        statusMessage = String(result.message || "Installing update…")
                    }
                } catch (error) {
                }
            }
        }
        xhr.send()
    }

    function unloading() {
        if (manifestRequest)
            manifestRequest.abort()
        if (statusRequest)
            statusRequest.abort()
        manifestRequest = null
        statusRequest = null
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            color: "black"
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "PAPERDESK  /  SYSTEM"
                        color: "white"
                        font.pointSize: 9
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "PaperDesk Care"
                        color: "white"
                        font.pointSize: 24
                        font.bold: true
                    }
                }
                ActionButton {
                    objectName: "careCheckButton"
                    label: root.state === "checking" ? "Checking…" : "Check now"
                    available: root.state !== "checking" && root.state !== "queued"
                    Layout.preferredWidth: 190
                    Layout.fillHeight: true
                    onTriggered: root.checkForUpdates()
                }
                ActionButton {
                    objectName: "careCloseButton"
                    label: "Close"
                    Layout.preferredWidth: 176
                    Layout.fillHeight: true
                    onTriggered: {
                        console.log("PaperDesk Care action close")
                        root.close()
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.height + 80
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 17000
            maximumFlickVelocity: 1300
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn; width: 15 }

            Column {
                id: content
                x: 90
                y: 54
                width: parent.width - 195
                spacing: 28

                Text {
                    width: parent.width
                    text: "Updates, without the terminal."
                    color: "black"
                    font.pointSize: 34
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "PaperDesk Care checks the official release feed, verifies every package and keeps a backup before installation."
                    color: "black"
                    font.pointSize: 18
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 300
                    radius: 10
                    color: root.state === "available" ? "black" : "white"
                    border.color: "black"
                    border.width: 3
                    Column {
                        anchors.fill: parent
                        anchors.margins: 28
                        spacing: 18
                        Text {
                            width: parent.width
                            text: statusMessage
                            color: root.state === "available" ? "white" : "black"
                            font.pointSize: 25
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            width: parent.width
                            spacing: 80
                            Column {
                                spacing: 4
                                Text { text: "INSTALLED"; color: root.state === "available" ? "white" : "black"; font.pointSize: 10; font.bold: true; font.letterSpacing: 2 }
                                Text { text: currentVersion; color: root.state === "available" ? "white" : "black"; font.pointSize: 24; font.bold: true }
                            }
                            Column {
                                spacing: 4
                                Text { text: "LATEST"; color: root.state === "available" ? "white" : "black"; font.pointSize: 10; font.bold: true; font.letterSpacing: 2 }
                                Text { text: latestVersion; color: root.state === "available" ? "white" : "black"; font.pointSize: 24; font.bold: true }
                            }
                            Column {
                                spacing: 4
                                visible: publishedAt.length > 0
                                Text { text: "PUBLISHED"; color: root.state === "available" ? "white" : "black"; font.pointSize: 10; font.bold: true; font.letterSpacing: 2 }
                                Text { text: publishedAt; color: root.state === "available" ? "white" : "black"; font.pointSize: 16; font.bold: true }
                            }
                        }
                        ActionButton {
                            objectName: "careInstallButton"
                            width: 310
                            height: 66
                            label: root.state === "queued" ? "Update queued" : "Install update"
                            primary: root.state !== "available"
                            available: root.state === "available" && !root.requestActive
                            onTriggered: root.requestInstall()
                        }
                    }
                }

                Rectangle { width: parent.width; height: 2; color: "black" }
                Text {
                    width: parent.width
                    text: "WHAT’S NEW"
                    color: "black"
                    font.pointSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    width: parent.width
                    text: releaseNotes || "Release notes will appear after the update check."
                    color: "black"
                    font.pointSize: 18
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                }
                Rectangle { width: parent.width; height: 2; color: "black" }
                Row {
                    width: parent.width
                    spacing: 28
                    Repeater {
                        model: [
                            ["1", "Signed manifest", "The release description must match PaperDesk’s built-in public key."],
                            ["2", "Verified archive", "SHA-256 is checked before anything is unpacked or executed."],
                            ["3", "Automatic backup", "Your previous applications and connection settings remain recoverable."]
                        ]
                        delegate: Rectangle {
                            width: (content.width - 56) / 3
                            height: 220
                            color: "white"
                            border.color: "black"
                            border.width: 2
                            radius: 8
                            Column {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 10
                                Text { text: modelData[0]; font.pointSize: 25; font.bold: true; color: "black" }
                                Text { width: parent.width; text: modelData[1]; font.pointSize: 16; font.bold: true; wrapMode: Text.WordWrap; color: "black" }
                                Text { width: parent.width; text: modelData[2]; font.pointSize: 13; wrapMode: Text.WordWrap; color: "black" }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 2; color: "black" }
                Text {
                    width: parent.width
                    text: "SYSTEM MANAGEMENT"
                    color: "black"
                    font.pointSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }
                Rectangle {
                    width: parent.width
                    height: root.uninstallConfirming ? 250 : 150
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 18

                        RowLayout {
                            width: parent.width
                            height: 78
                            spacing: 24
                            Column {
                                Layout.fillWidth: true
                                spacing: 5
                                Text { text: "Remove PaperDesk"; color: "black"; font.pointSize: 18; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: "Removes all PaperDesk apps. Saved connections, reader data and backups stay on the tablet."
                                    color: "black"
                                    font.pointSize: 13
                                    wrapMode: Text.WordWrap
                                }
                            }
                            ActionButton {
                                id: uninstallButton
                                objectName: "careUninstallButton"
                                label: "Uninstall"
                                available: !root.requestActive && !root.uninstallConfirming
                                Layout.preferredWidth: 205
                                Layout.fillHeight: true
                                onTriggered: root.beginUninstall()
                            }
                        }

                        Row {
                            visible: root.uninstallConfirming
                            width: parent.width
                            height: visible ? 92 : 0
                            spacing: 18
                            Text {
                                width: parent.width - 446
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Are you sure? PaperDesk will close and disappear from AppLoad."
                                color: "black"
                                font.pointSize: 16
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }
                            ActionButton {
                                id: uninstallCancelButton
                                objectName: "careUninstallCancelButton"
                                width: 190
                                height: parent.height
                                label: "Cancel"
                                onTriggered: root.cancelUninstall()
                            }
                            ActionButton {
                                id: uninstallConfirmButton
                                objectName: "careUninstallConfirmButton"
                                width: 220
                                height: parent.height
                                label: "Yes, uninstall"
                                primary: true
                                available: root.uninstallConfirmReady
                                onTriggered: root.requestUninstall()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: e2eGeometryLog
        interval: 800
        repeat: false
        onTriggered: {
            if (!e2eSettings.traceTouches)
                return
            var uninstallPoint = uninstallButton.mapToItem(root, 0, 0)
            console.log("PaperDesk Care E2E uninstall geometry", uninstallPoint.x,
                        uninstallPoint.y, uninstallButton.width, uninstallButton.height)
            if (root.uninstallConfirming) {
                var cancelPoint = uninstallCancelButton.mapToItem(root, 0, 0)
                console.log("PaperDesk Care E2E cancel geometry", cancelPoint.x,
                            cancelPoint.y, uninstallCancelButton.width, uninstallCancelButton.height)
            }
        }
    }

    onUninstallConfirmingChanged: {
        if (e2eSettings.traceTouches)
            e2eGeometryLog.restart()
    }

    Timer {
        id: uninstallConfirmDelay
        interval: 450
        repeat: false
        onTriggered: root.uninstallConfirmReady = root.uninstallConfirming
    }

    Timer {
        interval: 1800
        repeat: true
        running: root.requestActive
        onTriggered: root.pollInstallStatus()
    }

    Component.onCompleted: {
        checkForUpdates()
        if (e2eSettings.traceTouches)
            e2eGeometryLog.start()
    }
}
