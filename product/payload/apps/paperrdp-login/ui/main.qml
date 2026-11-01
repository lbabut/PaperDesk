import QtQuick 2.15
import QtQuick.Controls 2.15
import Qt.labs.settings 1.1
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
    property string orientation: "portrait"
    property string profileDomain: ""
    property int selectedProfileIndex: -1
    property string editorMode: ""
    property int editorReturnIndex: -1
    property int deleteConfirmationIndex: -1
    property bool profileActionPending: false
    property string profileRevision: ""
    property bool profileRefreshRequired: false
    property string profileOperationToken: ""
    property string profileOperationAction: ""
    property int profileOperationIndex: -1
    property double profileOperationDeadline: 0
    property int profileOperationPolls: 0
    property bool profileResultReadPending: false
    property int profileRequestSerial: 0
    property string profileConfigurationUrl: "file:///home/root/.config/paperrdp/"
    property bool legacyProfileAvailable: false
    property bool rememberPassword: true
    // Some reMarkable firmware reports a visible keyboard with an empty rect.
    property real keyboardInset: Qt.inputMethod.visible ? Math.min(height - 420,
        Math.max(height * 0.38, Qt.inputMethod.keyboardRectangle.height,
                 Qt.inputMethod.keyboardRectangle.y > 0 ? height - Qt.inputMethod.keyboardRectangle.y : 0)) : 0
    onKeyboardInsetChanged: Qt.callLater(ensureFocusedFieldVisible)
    readonly property int savedProfileCount: savedProfiles.count
    readonly property int toolbarButtonWidth: 176
    readonly property int toolbarButtonHeight: 76
    readonly property int actionFontPointSize: 16

    function unloading() { Qt.inputMethod.hide() }

    function showKeyboard(editor) {
        editor.forceActiveFocus()
        Qt.inputMethod.show()
        Qt.callLater(ensureFocusedFieldVisible)
    }

    function ensureFocusedFieldVisible() {
        var field = serverInput.activeFocus ? serverInput : usernameInput.activeFocus ? usernameInput :
                    passwordInput.activeFocus ? passwordInput : portInput.activeFocus ? portInput : null
        if (!field) return
        var point = field.mapToItem(profileContent, 0, 0)
        var top = profileScroll.contentY + 16, bottom = profileScroll.contentY + profileScroll.height - 16
        if (point.y < top) profileScroll.contentY = Math.max(0, point.y - 16)
        else if (point.y + field.height > bottom)
            profileScroll.contentY = Math.min(Math.max(0, profileScroll.contentHeight - profileScroll.height),
                                              point.y + field.height - profileScroll.height + 16)
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

    function validOrientation(value) { return value === "landscape" ? "landscape" : "portrait" }

    function addSavedProfile(host, user, domain, port, passwordHex, scale, depth, direction) {
        if (!host || !user)
            return
        savedProfiles.append({
            profileHost: host,
            profileUser: user,
            profileDomain: domain || "",
            profilePort: String(port || "3389"),
            profilePasswordHex: passwordHex || "",
            profileScale: validScale(scale),
            profileColorDepth: validColorDepth(depth),
            profileOrientation: validOrientation(direction)
        })
    }

    function decodeProfileList(text, strict) {
        text = String(text || "")
        if (text.length > 65536) return null
        var records = [], lines = text.split("\n")
        for (var i = 0; i < lines.length; ++i) {
            if (lines[i] === "" || lines[i].charAt(0) === "#") continue
            var parts = lines[i].split("\t")
            var legacy = parts.length === 8 && parts[0] === "v1"
            var valid = lines[i].length <= 8192 && (legacy ||
                (parts.length === 9 && parts[0] === "v2" &&
                 (parts[8] === "portrait" || parts[8] === "landscape")))
            if (valid) {
                for (var h of [1, 2, 3, 5])
                    valid = valid && parts[h].length <= 4096 && parts[h].length % 2 === 0 && /^[0-9a-f]*$/i.test(parts[h])
                valid = valid && parts[1].length > 0 && parts[2].length > 0 &&
                    /^[0-9]{1,5}$/.test(parts[4]) && Number(parts[4]) >= 1 && Number(parts[4]) <= 65535 &&
                    /^(50|75|100)$/.test(parts[6]) && /^(8|16|24)$/.test(parts[7])
            }
            if (!valid) { if (strict) return null; else continue }
            records.push({ profileHost: fromHex(parts[1]), profileUser: fromHex(parts[2]),
                profileDomain: fromHex(parts[3]), profilePort: parts[4], profilePasswordHex: parts[5],
                profileScale: Number(parts[6]), profileColorDepth: Number(parts[7]),
                profileOrientation: legacy ? "portrait" : parts[8] })
            if (records.length > 8) return null
        }
        return records
    }

    function replaceProfileList(records) {
        savedProfiles.clear()
        for (var record of records) savedProfiles.append(record)
    }

    function parseSavedProfiles(text) {
        var records = decodeProfileList(text, false)
        if (records === null) return false
        replaceProfileList(records)
        selectedProfileIndex = savedProfiles.count > 0 ? 0 : -1
        return true
    }

    function chooseProfile(index) {
        if (profileActionPending) return
        if (index < 0 || index >= savedProfiles.count)
            return
        var profile = savedProfiles.get(index)
        serverInput.text = profile.profileHost
        usernameInput.text = profile.profileUser
        profileDomain = profile.profileDomain
        portInput.text = profile.profilePort
        passwordInput.text = fromHex(profile.profilePasswordHex)
        rememberPassword = profile.profilePasswordHex.length > 0
        scalePercent = validScale(profile.profileScale)
        colorDepth = validColorDepth(profile.profileColorDepth)
        orientation = validOrientation(profile.profileOrientation)
        selectedProfileIndex = index
        editorMode = ""
        editorReturnIndex = -1
        deleteConfirmationIndex = -1
        Qt.inputMethod.hide()
        statusText.text = "Saved profile selected"
        console.log("PaperDesk RDP profile selected", profile.profileHost, profile.profileUser)
    }

    function clearProfileEditor() {
        serverInput.text = ""
        usernameInput.text = ""
        profileDomain = ""
        portInput.text = "3389"
        passwordInput.text = ""
        rememberPassword = true
        scalePercent = 75
        colorDepth = 8
        orientation = "portrait"
    }

    function beginAddProfile() {
        if (profileActionPending) return
        editorReturnIndex = selectedProfileIndex
        selectedProfileIndex = -1
        deleteConfirmationIndex = -1
        editorMode = "add"
        clearProfileEditor()
        if (e2eSettings.rdpProfileCrud) {
            serverInput.text = "rdp-e2e-created"
            usernameInput.text = "paperdesk-test"
            portInput.text = "3391"
            passwordInput.text = "e2e-password"
            console.log("PaperDesk RDP E2E new profile prepared")
        }
        statusText.text = "Enter the new connection, then tap Save new profile"
        console.log("PaperDesk RDP profile add")
    }

    function beginEditProfile() {
        if (profileActionPending) return
        if (selectedProfileIndex < 0 || selectedProfileIndex >= savedProfiles.count) {
            statusText.text = "Select a saved profile first"
            return
        }
        deleteConfirmationIndex = -1
        editorReturnIndex = selectedProfileIndex
        editorMode = "edit"
        if (e2eSettings.rdpProfileCrud && serverInput.text === "rdp-e2e-created") {
            serverInput.text = "rdp-e2e-edited"
            console.log("PaperDesk RDP E2E profile edit prepared")
        }
        statusText.text = "Edit the fields, then tap Save changes"
        console.log("PaperDesk RDP profile edit", selectedProfileIndex)
    }

    function cancelProfileEdit() {
        if (profileActionPending) return
        var returnIndex = editorReturnIndex
        editorMode = ""
        deleteConfirmationIndex = -1
        editorReturnIndex = -1
        if (returnIndex >= 0 && returnIndex < savedProfiles.count)
            chooseProfile(returnIndex)
        else if (savedProfiles.count > 0)
            chooseProfile(0)
        else {
            selectedProfileIndex = -1
            clearProfileEditor()
            statusText.text = "Create a profile to connect"
        }
        Qt.inputMethod.hide()
        console.log("PaperDesk RDP profile edit cancelled")
    }

    function editorIsValid() {
        if (serverInput.text.trim().length === 0 || usernameInput.text.trim().length === 0) {
            statusText.text = "Server and username are required"
            return false
        }
        var portNumber = Number(portInput.text)
        if (!isFinite(portNumber) || Math.floor(portNumber) !== portNumber || portNumber < 1 || portNumber > 65535) {
            statusText.text = "Port must be between 1 and 65535"
            return false
        }
        return true
    }

    function profileManagerArgs(action, index) {
        if (action === "delete")
            return ["--delete", String(index)]
        return ["--save", String(index), toHex(serverInput.text.trim()),
                toHex(usernameInput.text), toHex(profileDomain), portInput.text,
                toHex(rememberPassword ? passwordInput.text : ""),
                String(scalePercent), String(colorDepth), orientation, "v2"]
    }

    function finishProfileOperation() {
        profileActionPending = false
        profileOperationToken = ""
        profileResultReadPending = false
        profileLoaded = true
    }

    function failProfileOperation(code) {
        var action = profileOperationAction
        if (["locked", "stale", "write", "read", "corrupt", "invalid", "launch", "unknown"].indexOf(code) < 0)
            code = "unknown"
        finishProfileOperation()
        // A timeout or failed final read can follow a committed write. Require
        // an explicit read before another mutation; never replay it blindly.
        if (action === "read" || code === "stale" || code === "unknown" || code === "corrupt" || code === "read")
            profileRefreshRequired = true
        var messages = {
            locked: "Another profile update is running. Wait, then try again.",
            stale: "Saved profiles changed. Refresh before saving or deleting.",
            write: "Could not write profiles. Your previous profiles and edits are unchanged.",
            read: "Could not read saved profiles. Refresh to recover.",
            corrupt: "Saved profiles could not be validated. Refresh after repairing the file.",
            invalid: "Profile data was rejected. Check the fields and try again.",
            launch: "Could not start the profile manager. Your edits are still here.",
            unknown: "Result unknown. Refresh saved profiles before trying again."
        }
        statusText.text = messages[code] || messages.unknown
        // Reveal feedback rather than keep it behind the deletion overlay.
        deleteConfirmationIndex = -1
    }

    function startProfileOperation(action, index, args) {
        if (profileActionPending) return false
        if (action !== "read" && (profileRefreshRequired || !/^(absent|[a-f0-9]{64})$/.test(profileRevision))) {
            profileRefreshRequired = true
            if (action === "delete") deleteConfirmationIndex = -1
            statusText.text = "Refresh saved profiles before saving or deleting. Your edits will stay."
            return false
        }
        var token = Date.now().toString(16) + "-" + (++profileRequestSerial).toString(16) + "-" +
                    Math.floor(Math.random() * 0x100000000).toString(16)
        profileOperationToken = token
        profileOperationAction = action
        profileOperationIndex = index
        profileOperationPolls = 0
        profileOperationDeadline = Date.now() + 8000
        profileResultReadPending = false
        profileActionPending = true
        statusText.text = action === "read" ? "Reading saved profiles..." :
                          action === "save" ? "Saving profile..." : "Deleting profile..."
        var requestArgs = action === "read" ? ["--read", token] :
                          ["--request", token, profileRevision].concat(args)
        try {
            var launched = AppLoadLauncher.launchApplication("external::paperrdp-profile", requestArgs, {}, false)
            if (launched === false) { failProfileOperation("launch"); return false }
        } catch (error) {
            failProfileOperation("launch")
            return false
        }
        return true
    }

    function refreshSavedProfiles() {
        return startProfileOperation("read", -1, [])
    }

    function acceptProfileOperationResult(token, text) {
        if (!profileActionPending || token !== profileOperationToken) return false
        text = String(text || "")
        if (text.length > 66048) { failProfileOperation("read"); return false }
        var newline = text.indexOf("\n")
        if (newline < 0) return false
        var header = text.substr(0, newline).split("\t")
        if (header.length !== 7 || header[0] !== "PaperDeskProfileResult" || header[1] !== "1" ||
                header[2] !== token) return false
        if (header[3] !== profileOperationAction || !/^(absent|[a-f0-9]{64})$/.test(header[5])) {
            failProfileOperation("read"); return false
        }
        if (header[4] === "error") {
            failProfileOperation(header[6]); return true
        }
        if (header[4] !== "ok" || header[6] !== "none") { failProfileOperation("read"); return false }
        var records = decodeProfileList(text.substr(newline + 1), true)
        if (header[5] === "absent" && (profileOperationAction !== "read" || (records && records.length > 0))) {
            failProfileOperation("read"); return false
        }
        if (records === null) { failProfileOperation("read"); return false }
        var action = profileOperationAction, index = profileOperationIndex
        var preserveEditor = action === "read" && editorMode !== ""
        var previous = selectedProfileIndex >= 0 && selectedProfileIndex < savedProfiles.count ?
                       savedProfiles.get(selectedProfileIndex) : null
        function recordKey(record) {
            return JSON.stringify([record.profileHost, record.profileUser, record.profileDomain,
                record.profilePort, record.profilePasswordHex, record.profileScale,
                record.profileColorDepth, record.profileOrientation])
        }
        var previousKey = previous ? recordKey(previous) : ""
        var typedPassword = passwordInput.text, optedOut = !rememberPassword
        var wasRecovery = profileRefreshRequired
        finishProfileOperation()
        replaceProfileList(records)
        profileRevision = header[5]
        profileRefreshRequired = false
        if (action === "read") {
            var match = -1, matches = 0
            for (var i = 0; i < records.length; ++i)
                if (recordKey(records[i]) === previousKey) { match = i; ++matches }
            if (matches !== 1) match = -1
            selectedProfileIndex = match >= 0 ? match : records.length > 0 ? 0 : -1
            if (preserveEditor) {
                // A refresh can shift indices. Keep the typed form, and bind an
                // edit only to the same stored endpoint, never a replacement row.
                if (editorMode === "edit" && match < 0) { editorMode = "add"; selectedProfileIndex = -1 }
                editorReturnIndex = selectedProfileIndex
            } else if (selectedProfileIndex >= 0) chooseProfile(selectedProfileIndex)
            else if (legacyProfileAvailable && !wasRecovery) editorMode = "add"
            else if (!wasRecovery) clearProfileEditor()
            statusText.text = preserveEditor || wasRecovery ? "Profiles refreshed. Review your edits before saving." :
                legacyProfileAvailable && records.length === 0 ? "Previous connection loaded. Save it as a new profile." : "Saved profiles loaded"
        } else {
            editorMode = ""
            editorReturnIndex = -1
            deleteConfirmationIndex = -1
            selectedProfileIndex = records.length ? Math.min(action === "save" && index < 0 ? 0 : index, records.length - 1) : -1
            if (selectedProfileIndex >= 0) chooseProfile(selectedProfileIndex)
            else clearProfileEditor()
            if (action === "save" && optedOut) {
                passwordInput.text = typedPassword
                rememberPassword = false
            }
            statusText.text = action === "save" ? "Profile saved" : "Profile deleted"
            Qt.inputMethod.hide()
        }
        return true
    }

    function pollProfileOperation() {
        if (!profileActionPending) return
        if (Date.now() >= profileOperationDeadline || ++profileOperationPolls > 40) {
            failProfileOperation("unknown"); return
        }
        if (profileResultReadPending) return
        var token = profileOperationToken
        profileResultReadPending = true
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || token !== profileOperationToken) return
            profileResultReadPending = false
            if ((request.status === 0 || request.status === 200) && request.responseText.length > 0)
                acceptProfileOperationResult(token, request.responseText)
            else if (request.status !== 0 && request.status !== 404) failProfileOperation("read")
        }
        try {
            request.open("GET", profileConfigurationUrl + "operations/" + token + ".result")
            request.send()
        } catch (error) { failProfileOperation("read") }
    }

    function saveProfileChanges() {
        if (profileActionPending || !editorIsValid()) return
        var replaceIndex = editorMode === "edit" ? selectedProfileIndex : -1
        if (editorMode !== "add" && editorMode !== "edit") {
            statusText.text = "Choose Add or Edit first"; return
        }
        if (editorMode === "edit" && (replaceIndex < 0 || replaceIndex >= savedProfiles.count)) {
            statusText.text = "The selected profile no longer exists"; return
        }
        startProfileOperation("save", replaceIndex, profileManagerArgs("save", replaceIndex))
    }

    function requestDeleteProfile() {
        if (profileRefreshRequired) {
            statusText.text = "Refresh saved profiles before deleting."
            return
        }
        if (profileActionPending || selectedProfileIndex < 0 ||
                selectedProfileIndex >= savedProfiles.count) {
            statusText.text = "Select a saved profile first"
            return
        }
        deleteConfirmationIndex = selectedProfileIndex
        Qt.inputMethod.hide()
        statusText.text = "Confirm profile deletion"
        console.log("PaperDesk RDP profile delete confirmation", selectedProfileIndex)
    }

    function cancelDeleteProfile() {
        if (profileActionPending) return
        deleteConfirmationIndex = -1
        statusText.text = "Deletion cancelled"
        console.log("PaperDesk RDP profile delete cancelled")
    }

    function confirmDeleteProfile() {
        if (profileActionPending) return
        if (deleteConfirmationIndex < 0 || deleteConfirmationIndex >= savedProfiles.count) {
            deleteConfirmationIndex = -1
            statusText.text = "Select a saved profile first"
            return
        }
        startProfileOperation("delete", deleteConfirmationIndex, profileManagerArgs("delete", deleteConfirmationIndex))
    }

    function openSelectedProfile() {
        if (profileActionPending) return
        if (selectedProfileIndex < 0 || selectedProfileIndex >= savedProfiles.count) {
            statusText.text = "Select a saved profile first"
            return
        }
        editorMode = ""
        deleteConfirmationIndex = -1
        console.log("PaperDesk RDP profile open", selectedProfileIndex)
        connectRdp()
    }

    function loadSavedProfiles(fallbackProfile) {
        legacyProfileAvailable = !!(fallbackProfile && fallbackProfile.host && fallbackProfile.user)
        refreshSavedProfiles()
    }

    function loadProfile() {
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return
            var fallback = { host: "", user: "", domain: "", port: "3389",
                             passwordHex: "", scale: 100, depth: 16, orientation: "portrait" }
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
                    } else if (key === "orientation") {
                        orientation = validOrientation(value)
                        fallback.orientation = orientation
                    }
                }
            }
            loadSavedProfiles(fallback)
        }
        request.open("GET", profileConfigurationUrl + "profile")
        request.send()
    }

    function connectRdp() {
        if (connectionLaunching)
            return
        if (!editorIsValid())
            return
        connectionLaunching = true
        statusText.text = "Connecting..."
        Qt.inputMethod.hide()
        var connectionArgs = ["--host", serverInput.text.trim(), "--user", usernameInput.text,
             "--domain-hex", toHex(profileDomain),
             "--password-hex", toHex(passwordInput.text), "--port", portInput.text,
             "--scale-percent", String(scalePercent), "--color-depth", String(colorDepth),
             "--orientation", orientation]
        if (!rememberPassword) connectionArgs.push("--no-save-password")
        AppLoadLauncher.launchApplication("external::paperrdp", connectionArgs, {}, false)
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
        if (profileActionPending) pollProfileOperation()
        else if (profileLoaded && editorMode === "" && !profileRefreshRequired) refreshSavedProfiles()
    }

    Component.onCompleted: {
        loadProfile()
        Qt.callLater(function() {
            var scaleItem = scaleChoices.itemAt(1)
            var colorItem = colorChoices.itemAt(0)
            var newItem = profileActionRepeater.itemAt(0)
            var editItem = profileActionRepeater.itemAt(1)
            var deleteItem = profileActionRepeater.itemAt(2)
            if (!scaleItem || !colorItem || !newItem || !editItem || !deleteItem)
                return
            var scaleCenter = scaleItem.mapToItem(root, scaleItem.width / 2, scaleItem.height / 2)
            var colorCenter = colorItem.mapToItem(root, colorItem.width / 2, colorItem.height / 2)
            var connectCenter = connectButton.mapToItem(root, connectButton.width / 2, connectButton.height / 2)
            console.log("PaperDesk RDP layout", Math.round(scaleCenter.x), Math.round(scaleCenter.y),
                        Math.round(colorCenter.x), Math.round(colorCenter.y),
                        Math.round(connectCenter.x), Math.round(connectCenter.y))
            var newCenter = newItem.mapToItem(root, newItem.width / 2, newItem.height / 2)
            var editCenter = editItem.mapToItem(root, editItem.width / 2, editItem.height / 2)
            var deleteCenter = deleteItem.mapToItem(root, deleteItem.width / 2, deleteItem.height / 2)
            console.log("PaperDesk RDP profile actions", Math.round(newCenter.x), Math.round(newCenter.y),
                        Math.round(editCenter.x), Math.round(editCenter.y),
                        Math.round(deleteCenter.x), Math.round(deleteCenter.y))
            var rememberCenter = rememberPasswordButton.mapToItem(
                root, rememberPasswordButton.width / 2, rememberPasswordButton.height / 2)
            console.log("PaperDesk RDP remember password position",
                        Math.round(rememberCenter.x), Math.round(rememberCenter.y))
        })
    }

    ListModel { id: savedProfiles }

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool rdpProfileCrud: false
        property bool traceTouches: false
    }

    function logTestTargets(item) {
        if (!item.visible) return
        if (item.objectName && (item.objectName.indexOf("rdp") === 0 || /^(server|username|password|port)Input$/.test(item.objectName)) && item.mapToItem) {
            var point = item.mapToItem(root, item.width / 2, item.height / 2)
            console.log("PaperDesk RDP target", item.objectName, Math.round(point.x), Math.round(point.y))
        }
        if (item.children) for (var i = 0; i < item.children.length; ++i) logTestTargets(item.children[i])
    }
    Timer {
        interval: 700; repeat: true
        running: e2eSettings.traceTouches
        onTriggered: {
            console.log("PaperDesk RDP viewport", Math.round(root.keyboardInset), Math.round(profileScroll.height), Math.round(profileScroll.contentY))
            root.logTestTargets(root)
        }
    }

    // The native login remains alive beneath the external QTFB window.  This
    // short guard absorbs an accidental double-tap while launch is in flight,
    // then makes Connect available again when the RDP window later closes.
    Timer {
        id: connectionLaunchGuard
        interval: 900
        repeat: false
        onTriggered: root.connectionLaunching = false
    }

    Timer {
        id: profileOperationPoll
        objectName: "rdpProfileOperationPoll"
        interval: 200
        repeat: true
        running: root.profileActionPending
        onTriggered: root.pollProfileOperation()
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
                text: Qt.inputMethod.visible ? "Hide keyboard" : "Keyboard"
                color: keyboardMouse.pressed ? "white" : "black"
                font.pointSize: root.actionFontPointSize
                font.bold: true
            }
            TapHandler {
                id: keyboardMouse
                onTapped: {
                    console.log("PaperDesk RDP keyboard opened")
                    if (Qt.inputMethod.visible) Qt.inputMethod.hide()
                    else if (root.editorMode === "")
                        statusText.text = "Choose New profile or Edit to change a connection"
                    else
                        root.showKeyboard(serverInput)
                }
            }
        }
    }

    Rectangle {
        id: profileRecoveryBar
        objectName: "rdpProfileRecoveryBar"
        visible: root.profileRefreshRequired && !root.profileActionPending
        anchors.top: toolbar.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 180, 1040)
        height: 88
        color: "white"
        border.color: "black"; border.width: 2; radius: 8
        Text {
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.right: refreshButton.left; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: statusText.text
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            font.pointSize: 14; font.bold: true
        }
        Rectangle {
            id: refreshButton
            objectName: "rdpProfileRefreshButton"
            anchors.right: parent.right; anchors.margins: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 200; height: 70; radius: 6
            color: "black"
            Text { anchors.centerIn: parent; text: "Refresh"; color: "white"; font.pointSize: 16; font.bold: true }
            TapHandler { onTapped: root.refreshSavedProfiles() }
        }
    }

    Flickable {
        id: profileScroll
        objectName: "rdpProfileScroll"
        anchors.top: toolbar.bottom
        anchors.topMargin: profileRecoveryBar.visible ? 112 : 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.keyboardInset + (root.editorMode !== "" ? 168 : 20)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 180, 1040)
        clip: true
        contentHeight: profileContent.height + 20
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        maximumFlickVelocity: 1800
        flickDeceleration: 3000
        Column {
        id: profileContent
        enabled: root.profileLoaded && !root.profileActionPending
        width: profileScroll.width
        spacing: 12

        Text {
            text: "CONNECTION PROFILE"
            color: "black"
            font.pointSize: 13
            font.bold: true
            font.letterSpacing: 2
        }
        Text {
            text: root.editorMode === "add" ? "New connection" : root.editorMode === "edit" ? "Edit connection" : "Connect to a computer"
            color: "black"
            font.pointSize: 29
            font.bold: true
        }
        Text {
            text: root.editorMode !== "" ? "Save stays above the keyboard. Swipe to see every field." : "Select a saved connection or create a new one."
            width: parent.width
            wrapMode: Text.WordWrap
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
            visible: root.editorMode === ""
            font.pointSize: 14
            font.bold: true
            font.letterSpacing: 1
            color: "black"
            topPadding: 6
        }
        Item {
            width: parent.width
            height: visible ? 200 : 0
            visible: root.editorMode === ""

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
                contentWidth: width
                contentHeight: savedProfilesColumn.height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: savedProfilesColumn
                    width: savedProfilesFlick.width
                    height: childrenRect.height
                    spacing: 8

                    Repeater {
                        model: savedProfiles
                        delegate: Rectangle {
                            objectName: "rdpSavedProfileButton_" + index
                            width: savedProfilesColumn.width
                            height: 92
                            radius: 8
                            border.color: "black"
                            border.width: 2
                            color: root.selectedProfileIndex === index ? "black" : "white"

                            Text {
                                id: savedProfileLabel
                                anchors.left: parent.left
                                anchors.right: profileDetails.left
                                anchors.top: parent.top
                                anchors.leftMargin: 18
                                anchors.rightMargin: 14
                                anchors.topMargin: 8
                                text: profileHost
                                color: root.selectedProfileIndex === index ? "white" : "black"
                                font.pointSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.right: profileDetails.left
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 18
                                anchors.rightMargin: 14
                                anchors.bottomMargin: 7
                                text: (profileDomain ? profileDomain + "\\" : "") + profileUser
                                color: root.selectedProfileIndex === index ? "white" : "black"
                                font.pointSize: 15
                                elide: Text.ElideRight
                            }

                            Text {
                                id: profileDetails
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                width: 310
                                horizontalAlignment: Text.AlignRight
                                text: profileScale + "%  ·  " +
                                      (profileColorDepth === 8 ? "256 colors" :
                                       profileColorDepth === 16 ? "65K colors" : "16M colors") + "\n" +
                                      (profileOrientation === "landscape" ? "Landscape" : "Portrait")
                                color: root.selectedProfileIndex === index ? "white" : "black"
                                font.pointSize: 15
                                font.bold: true
                            }
                            TapHandler { onTapped: root.chooseProfile(index) }
                        }
                    }
                }
            }
        }

        Row {
            id: profileActions
            width: parent.width
            height: visible ? 76 : 0
            visible: root.editorMode === ""
            spacing: 12

            Repeater {
                id: profileActionRepeater
                model: [
                    { label: "New profile", target: "rdpProfileNewButton" },
                    { label: "Edit", target: "rdpProfileEditButton" },
                    { label: "Delete", target: "rdpProfileDeleteButton" }
                ]
                delegate: Rectangle {
                    objectName: modelData.target
                    enabled: !root.profileActionPending && (index === 0 || root.selectedProfileIndex >= 0)
                    width: (profileActions.width - profileActions.spacing * 2) / 3
                    height: profileActions.height
                    radius: 8
                    border.color: enabled ? "black" : "#777777"
                    border.width: 2
                    color: modelData.label === "Delete" &&
                           root.deleteConfirmationIndex === root.selectedProfileIndex &&
                           root.selectedProfileIndex >= 0
                           ? "black" : "white"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label === "Delete" &&
                              root.deleteConfirmationIndex === root.selectedProfileIndex &&
                              root.selectedProfileIndex >= 0 ? "Confirm delete" : modelData.label
                        color: !parent.enabled ? "#666666" : parent.color === "black" ? "white" : "black"
                        font.pointSize: 16
                        font.bold: true
                    }
                    TapHandler {
                        onTapped: {
                            if (modelData.label === "New profile") root.beginAddProfile()
                            else if (modelData.label === "Edit") root.beginEditProfile()
                            else root.requestDeleteProfile()
                        }
                    }
                }
            }
        }

        Row {
            id: profileEditActions
            // A fixed action dock remains reachable even while editing Port
            // at the bottom of a form with the native keyboard open.
            parent: root
            z: 30
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.keyboardInset + 18
            width: profileScroll.width
            height: visible ? 76 : 0
            visible: root.editorMode !== ""
            spacing: 12

            Rectangle {
                id: cancelEditButton
                objectName: "rdpProfileCancelButton"
                width: (parent.width - parent.spacing) / 2
                height: parent.height
                radius: 8
                border.color: "black"
                border.width: 2
                color: cancelEditTap.pressed ? "black" : "white"
                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: cancelEditTap.pressed ? "white" : "black"
                    font.pointSize: 16
                    font.bold: true
                }
                TapHandler { id: cancelEditTap; enabled: !root.profileActionPending; onTapped: root.cancelProfileEdit() }
            }

            Rectangle {
                id: saveProfileButton
                objectName: "rdpProfileSaveButton"
                width: (parent.width - parent.spacing) / 2
                height: parent.height
                radius: 8
                border.color: "black"
                border.width: 2
                color: saveProfileTap.pressed ? "white" : "black"
                Text {
                    objectName: "rdpProfileSaveLabel"
                    anchors.centerIn: parent
                    text: root.editorMode === "edit" ? "Save changes" : "Save new profile"
                    color: saveProfileTap.pressed ? "black" : "white"
                    font.pointSize: 16
                    font.bold: true
                }
                TapHandler {
                    id: saveProfileTap
                    enabled: !root.profileActionPending
                    onTapped: {
                        console.log("PaperDesk RDP action save profile")
                        root.saveProfileChanges()
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: root.editorMode === "add" ? "NEW PROFILE — enter connection details below" :
                  root.editorMode === "edit" ? "EDITING SELECTED PROFILE" :
                  "PROFILE DETAILS — select a row above"
            color: "black"
            font.pointSize: 12
            font.bold: true
            font.letterSpacing: 1
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
                readOnly: root.editorMode === ""
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (activeFocus && !readOnly) { Qt.inputMethod.show(); Qt.callLater(root.ensureFocusedFieldVisible) }
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
                readOnly: root.editorMode === ""
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onActiveFocusChanged: if (activeFocus && !readOnly) { Qt.inputMethod.show(); Qt.callLater(root.ensureFocusedFieldVisible) }
            }
        }

        Text { text: "PASSWORD"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
        Rectangle {
            width: parent.width; height: 88; color: "white"; radius: 8
            border.color: "black"
            border.width: passwordInput.activeFocus ? 4 : 2
            TextInput {
                id: passwordInput; objectName: "passwordInput"
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.right: rememberPasswordButton.left
                anchors.leftMargin: 16; anchors.topMargin: 16; anchors.bottomMargin: 16
                anchors.rightMargin: 10
                font.pointSize: 24; color: "black"; verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                readOnly: root.editorMode === ""
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                onActiveFocusChanged: if (activeFocus && !readOnly) { Qt.inputMethod.show(); Qt.callLater(root.ensureFocusedFieldVisible) }
            }
            Rectangle {
                id: rememberPasswordButton
                objectName: "rdpRememberPasswordButton"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 270
                radius: 8
                color: root.rememberPassword ? "black" : "white"
                border.color: "black"
                border.width: 2
                Text {
                    objectName: "rdpRememberPasswordLabel"
                    anchors.centerIn: parent
                    text: root.rememberPassword ? "Remember: on" : "Remember: off"
                    color: root.rememberPassword ? "white" : "black"
                    font.pointSize: 16
                    font.bold: true
                }
                TapHandler {
                    onTapped: {
                        if (root.editorMode === "") {
                            statusText.text = "Tap Edit before changing password storage"
                            return
                        }
                        root.rememberPassword = !root.rememberPassword
                        console.log("PaperDesk RDP remember password", root.rememberPassword ? "on" : "off")
                    }
                }
            }
        }

        Row {
        width: parent.width
        spacing: 20
        Column {
        width: 250
        spacing: 12
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
                readOnly: root.editorMode === ""
                inputMethodHints: Qt.ImhDigitsOnly
                onActiveFocusChanged: if (activeFocus && !readOnly) { Qt.inputMethod.show(); Qt.callLater(root.ensureFocusedFieldVisible) }
            }
        }
        }
        Column {
            width: parent.width - 270
            spacing: 12
            Text { text: "ORIENTATION"; font.pointSize: 14; font.bold: true; font.letterSpacing: 1; color: "black" }
            Row {
                width: parent.width
                height: 76
                spacing: 12
                Repeater {
                    model: ["portrait", "landscape"]
                    delegate: Rectangle {
                        objectName: "rdpOrientationButton_" + modelData
                        width: (parent.width - 12) / 2
                        height: 76; radius: 8
                        color: root.orientation === modelData ? "black" : "white"
                        border.color: "black"; border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: modelData === "portrait" ? "Portrait" : "Landscape"
                            color: root.orientation === modelData ? "white" : "black"
                            font.pointSize: 16; font.bold: true
                        }
                        TapHandler {
                            onTapped: {
                                if (root.editorMode === "") {
                                    statusText.text = "Tap Edit before changing orientation"
                                    return
                                }
                                root.orientation = modelData
                                console.log("PaperDesk RDP orientation", modelData)
                            }
                        }
                    }
                }
            }
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
                    height: 76
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
                                    if (root.editorMode === "") {
                                        statusText.text = "Tap Edit before changing performance"
                                        return
                                    }
                                    root.scalePercent = modelData
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
                    height: 76
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
                                    if (root.editorMode === "") {
                                        statusText.text = "Tap Edit before changing performance"
                                        return
                                    }
                                    root.colorDepth = modelData.bits
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
            font.pointSize: 15
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: root.orientation === "landscape"
            text: "Turn the tablet left when the session opens. Keyboard and shortcuts follow the session orientation."
            color: "black"; font.pointSize: 15; wrapMode: Text.WordWrap
        }

        Rectangle {
            id: connectButton
            objectName: "connectButton"
            width: parent.width
            height: visible ? 82 : 0
            visible: root.editorMode === ""
            radius: 8
            color: connectMouse.pressed ? "white" : "black"
            border.color: "black"
            border.width: 2
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
                enabled: !root.connectionLaunching && !root.profileActionPending
                onTapped: {
                    console.log("PaperDesk RDP action connect")
                    root.openSelectedProfile()
                }
            }
        }

        Text {
            id: statusText
            objectName: "rdpProfileStatus"
            visible: root.editorMode === ""
            width: parent.width
            text: root.profileLoaded ?
                  (root.editorMode === "" ? "Select a profile, then Connect — or choose New profile, Edit or Delete" :
                   "Review the fields, then save or cancel") :
                  "Loading saved profiles..."
            textFormat: Text.PlainText
            color: "black"; font.pointSize: 14; font.bold: true; font.letterSpacing: 0.5; wrapMode: Text.WordWrap
        }
        }
    }

    Rectangle {
        // Solid dock: scrolling fields must never bleed under Save / Cancel.
        z: 29
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.keyboardInset
        height: 150
        visible: root.editorMode !== ""
        color: "white"
        Rectangle { width: parent.width; height: 2; color: "black" }
        Text {
            objectName: "rdpEditorStatus"
            anchors.top: parent.top; anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            width: profileScroll.width
            text: statusText.text
            textFormat: Text.PlainText
            font.pointSize: 15; font.bold: true; color: "black"
            maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
        }
    }

    Rectangle {
        id: deleteConfirmationOverlay
        objectName: "rdpDeleteConfirmation"
        anchors.fill: parent
        visible: root.deleteConfirmationIndex >= 0
        color: "white"
        z: 100

        TapHandler { onTapped: {} }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 160, 900)
            height: 420
            color: "white"
            border.color: "black"
            border.width: 4
            radius: 10

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 42
                spacing: 18

                Text {
                    width: parent.width
                    text: "DELETE PROFILE?"
                    color: "black"
                    font.pointSize: 13
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    width: parent.width
                    text: root.deleteConfirmationIndex >= 0 &&
                          root.deleteConfirmationIndex < savedProfiles.count
                          ? savedProfiles.get(root.deleteConfirmationIndex).profileHost : ""
                    color: "black"
                    font.pointSize: 25
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    objectName: "rdpDeleteStatus"
                    text: root.profileActionPending ? "Deleting profile... Please wait for confirmation." :
                          "This removes the saved connection from this tablet. This action cannot be undone."
                    textFormat: Text.PlainText
                    color: "black"
                    font.pointSize: 16
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 40
                height: 76
                spacing: 16

                Rectangle {
                    objectName: "rdpDeleteCancelButton"
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    color: deleteCancelTap.pressed ? "black" : "white"
                    border.color: "black"
                    border.width: 2
                    radius: 8
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: deleteCancelTap.pressed ? "white" : "black"
                        font.pointSize: 16
                        font.bold: true
                    }
                    TapHandler { id: deleteCancelTap; enabled: !root.profileActionPending; onTapped: root.cancelDeleteProfile() }
                }

                Rectangle {
                    objectName: "rdpDeleteConfirmButton"
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    color: deleteConfirmTap.pressed ? "white" : "black"
                    border.color: "black"
                    border.width: 2
                    radius: 8
                    Text {
                        anchors.centerIn: parent
                        text: "Delete profile"
                        color: deleteConfirmTap.pressed ? "black" : "white"
                        font.pointSize: 16
                        font.bold: true
                    }
                    TapHandler {
                        id: deleteConfirmTap
                        enabled: !root.profileActionPending
                        onTapped: root.confirmDeleteProfile()
                    }
                }
            }
        }
    }

    DisplayMethodArea { anchors.fill: parent; displayMethod: DisplayMethodArea.Fast; z: -1 }
}
