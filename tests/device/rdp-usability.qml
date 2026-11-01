import QtQuick 2.15
import QtQuick.Window 2.15

// Temporary AppLoad diagnostics only. The runner stages private helper/engine
// application IDs and configuration/certificate directories. No physical input
// injection, framebuffer grab, user profile or arbitrary server is used here.
Rectangle {
    id: probe
    anchors.fill: parent
    color: "white"
    signal close
    property string fixtureUrl: "file://__RDP_FIXTURE_DIR__/"
    property string commandUrl: "file://__RDP_COMMAND_FILE__"
    property string fixturePort: "__RDP_PORT__"
    property int phase: 0
    property double began: Date.now()
    property double phaseAt: Date.now()
    property bool done: false
    property bool commandReadPending: false
    property int lastRevision: 0
    property var awaiting: null
    property int enginePid: -1
    property var beforeKeyboard: null
    property string sessionOrientation: ""
    property var result: ({execution: "production RDP QML and external engine inside AppLoad",
        physical_input_injected: false, optical_ghosting_measured: false,
        orientations: {}, actions: []})

    function gainedFocus() {
        if (!done && subject.item && subject.item.gainedFocus) subject.item.gainedFocus()
    }

    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = find(children[i], name)
            if (found) return found
        }
        return null
    }
    function engine(item, depth) {
        if (!item || depth > 40) return null
        if (item.appName === "PaperDesk RDP Engine" && item.appPid > 0 &&
                item.qtfbKey !== -1 && !item.closing) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = engine(children[i], depth + 1)
            if (found) return found
        }
        return null
    }
    function ownEngine() {
        var window = engine(probe.Window.window ? probe.Window.window.contentItem : null, 0)
        return window && window.appPid === enginePid ? window : null
    }
    function status(app) {
        var label = find(app, "rdpProfileStatus")
        return label ? label.text : ""
    }
    function state(action, passed, details) {
        var record = {revision: lastRevision, action: action, passed: passed, details: details || {}}
        result.actions.push(record)
        console.log("PAPERDESK_RDP_PROBE_STATE " + JSON.stringify(record))
    }
    function finish(error) {
        if (done) return
        done = true
        ticker.stop(); commands.stop()
        result.error = error || ""
        result.elapsed_ms = Date.now() - began
        result.passed = !error && result.crud && result.no_optimistic_save && result.no_optimistic_delete &&
            result.orientations.portrait && result.orientations.landscape && result.navigation && result.functions
        var window = ownEngine()
        if (window) window.requestClose(true)
        if (subject.item) subject.item.unloading()
        console.log("PAPERDESK_RDP_PROBE_RESULT " + JSON.stringify(result))
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    function fill(app, user, direction, password) {
        find(app, "serverInput").text = "127.0.0.1"
        find(app, "usernameInput").text = user || "paperdesk-rdp-probe"
        find(app, "passwordInput").text = password || ""
        find(app, "portInput").text = fixturePort
        app.profileDomain = ""
        app.rememberPassword = false
        app.scalePercent = 75; app.colorDepth = 8
        app.orientation = direction || "portrait"
    }
    function ready(app) {
        return app && app.profileLoaded && !app.profileActionPending && !app.profileRefreshRequired &&
            /^(absent|[a-f0-9]{64})$/.test(app.profileRevision)
    }
    function waitFor(kind, command) {
        awaiting = {kind: kind, command: command || {}, at: Date.now()}
    }
    function complete(passed, details) {
        var action = awaiting.command.action
        awaiting = null
        state(action, passed, details)
        check(passed, "Command failed: " + action)
    }
    function geometry(window) {
        var canvas = find(window, "paperdeskWindowCanvas")
        var chrome = find(window, "paperdeskRdpChrome")
        var keyboard = find(window, "paperdeskRdpKeyboardButton")
        var closeButton = find(window, "paperdeskRdpCloseButton")
        var kp = keyboard.mapToItem(chrome, 0, 0)
        var cp = closeButton.mapToItem(chrome, 0, 0)
        return {canvasX: canvas.x, canvasY: canvas.y, canvasWidth: canvas.width, canvasHeight: canvas.height,
            logicalWidth: chrome.width, logicalHeight: chrome.height,
            keyboardX: kp.x, keyboardY: kp.y, closeX: cp.x, closeY: cp.y,
            viewportHeight: window.rdpViewportHeight, viewportCommand: window.rdpLastViewportCommand,
            toolbarReachable: kp.y >= 0 && kp.y + keyboard.height <= 112 &&
                              cp.y >= 0 && cp.y + closeButton.height <= 112}
    }
    function sameCanvas(first, second) {
        return first.canvasX === second.canvasX && first.canvasY === second.canvasY &&
            first.canvasWidth === second.canvasWidth && first.canvasHeight === second.canvasHeight &&
            first.keyboardX === second.keyboardX && first.keyboardY === second.keyboardY &&
            first.closeX === second.closeX && first.closeY === second.closeY
    }
    function execute(command) {
        var app = subject.item
        lastRevision = command.revision
        check(!awaiting && phase === 100, "The previous action has not completed")
        check(!app.profileActionPending, "A profile operation is still pending")
        var action = command.action
        if (action === "save_locked" || action === "save_write_error" || action === "save_stale") {
            if (app.editorMode !== "") app.cancelProfileEdit()
            app.beginAddProfile(); fill(app, "paperdesk-probe-retained", "portrait", "")
            var count = app.savedProfileCount
            var revision = app.profileRevision
            app.saveProfileChanges()
            check(app.profileActionPending, "The failure fixture did not start its real helper request")
            waitFor("failure", command)
            awaiting.count = count; awaiting.revision = revision
        } else if (action === "refresh") {
            check(app.refreshSavedProfiles(), "Could not start the real profile read")
            waitFor("refresh", command)
        } else if (action === "connect") {
            check(ready(app), "Refresh the fixture profiles before connecting")
            check(!engine(probe.Window.window.contentItem, 0), "An RDP window is already active")
            check(command.orientation === "portrait" || command.orientation === "landscape", "Choose an explicit orientation")
            if (app.editorMode !== "") app.cancelProfileEdit()
            app.beginAddProfile()
            sessionOrientation = command.orientation
            fill(app, command.user, sessionOrientation, command.password)
            app.saveProfileChanges()
            check(app.profileActionPending, "Could not start the connection fixture save")
            waitFor("connect_save", command)
        } else if (action === "finish") {
            finish("")
        } else {
            var window = ownEngine()
            check(window !== null, "The diagnostic RDP engine is unavailable")
            if (action === "keyboard") {
                beforeKeyboard = geometry(window)
                if (!window.rdpKeyboardVisible) window.toggleKeyboardInput()
                waitFor("keyboard", command)
            } else if (action === "hide_keyboard") {
                window.hideSystemKeyboard()
                waitFor("hide_keyboard", command)
            } else if (action === "navigation" || action === "functions") {
                window.rdpShortcutPage = action === "navigation" ? 1 : 2
                window.rdpShortcutsOpen = true
                waitFor("panel", command)
            } else if (action === "send_navigation") {
                var wasVisible = window.rdpKeyboardVisible
                for (var key of [Qt.Key_Home, Qt.Key_Up, Qt.Key_End, Qt.Key_PageUp,
                        Qt.Key_Left, Qt.Key_Down, Qt.Key_Right, Qt.Key_PageDown, Qt.Key_Delete, Qt.Key_Return])
                    window.sendRdpKey(key)
                window.sendRdpShortcut(30)
                check(window.rdpKeyboardVisible === wasVisible, "Navigation changed keyboard visibility")
                result.navigation = true
                state(action, true, {keys: 10, shiftTab: true, orientation: sessionOrientation})
            } else if (action === "send_functions") {
                var keyboardWasVisible = window.rdpKeyboardVisible
                for (var number = 0; number < 12; ++number) window.sendRdpKey(Qt.Key_F1 + number)
                window.sendRdpShortcut(0); window.sendRdpShortcut(1)
                check(window.rdpKeyboardVisible === keyboardWasVisible, "Function keys changed keyboard visibility")
                result.functions = true
                state(action, true, {functionKeys: 12, ctrlC: true, ctrlV: true, orientation: sessionOrientation})
            } else if (action === "retry" || action === "fit") {
                window.sendRdpShortcut(action === "retry" ? 0x100 : 0x101)
                state(action, true, {command_dispatched: true})
            } else if (action === "close") {
                window.requestClose(true)
                waitFor("close", command)
            } else throw new Error("Unknown diagnostic action")
        }
    }
    function tick() {
        if (done) return
        check(Date.now() - began < 600000, "Diagnostic command sequence timed out")
        var app = subject.item
        if (!app) { check(subject.status !== Loader.Error, "The production login QML could not load"); return }
        if (phase !== 100) {
            check(Date.now() - phaseAt < 15000, "Async CRUD timed out in phase " + phase)
            if (phase === 0) {
                if (!ready(app)) return
                check(app.profileConfigurationUrl === fixtureUrl, "The production login is not using its private fixture")
                check(app.savedProfileCount === 0, "The fixture must begin with zero saved profiles")
                check(!engine(probe.Window.window.contentItem, 0), "An RDP window was already open")
                app.beginAddProfile(); fill(app, "paperdesk-rdp-probe", "portrait", "")
                app.saveProfileChanges()
                result.no_optimistic_save = app.profileActionPending && app.savedProfileCount === 0
                check(result.no_optimistic_save, "Save changed the list before its helper ACK")
                phase = 10; phaseAt = Date.now()
            } else if (!app.profileActionPending) {
                if (phase === 10) {
                    check(app.savedProfileCount === 1 && app.editorMode === "" && status(app) === "Profile saved", "The initial helper save failed")
                    app.beginEditProfile(); fill(app, "paperdesk-rdp-probe-edited", "portrait", "")
                    app.saveProfileChanges(); check(app.profileActionPending, "Edit did not start its helper")
                    phase = 20; phaseAt = Date.now()
                } else if (phase === 20) {
                    check(app.editorMode === "" && status(app) === "Profile saved", "The edit helper ACK failed")
                    check(app.refreshSavedProfiles(), "Could not read back the edited fixture")
                    phase = 30; phaseAt = Date.now()
                } else if (phase === 30) {
                    check(ready(app) && app.savedProfileCount === 1, "The edited fixture did not survive a real read")
                    app.chooseProfile(0)
                    check(find(app, "usernameInput").text === "paperdesk-rdp-probe-edited", "The read did not return the edited record")
                    app.requestDeleteProfile(); app.confirmDeleteProfile()
                    result.no_optimistic_delete = app.profileActionPending && app.savedProfileCount === 1
                    check(result.no_optimistic_delete, "Delete changed the list before its helper ACK")
                    phase = 40; phaseAt = Date.now()
                } else if (phase === 40) {
                    check(ready(app) && app.savedProfileCount === 0 && status(app) === "Profile deleted", "The delete helper ACK failed")
                    result.crud = true; phase = 100
                    state("crud_ready", true, {count: 0, revision_ready: true})
                }
            }
            return
        }
        if (!awaiting) return
        check(Date.now() - awaiting.at < 15000, "Command timed out: " + awaiting.command.action)
        var kind = awaiting.kind, command = awaiting.command
        if ((kind === "failure" || kind === "refresh" || kind === "connect_save") && app.profileActionPending) return
        if (kind === "failure" && !app.profileActionPending) {
            var expected = command.action === "save_locked" ? "Another profile update" :
                           command.action === "save_stale" ? "Saved profiles changed" : "Could not write profiles"
            complete(status(app).indexOf(expected) === 0 && app.savedProfileCount === awaiting.count &&
                app.profileRevision === awaiting.revision && app.editorMode === "add" &&
                find(app, "usernameInput").text === "paperdesk-probe-retained",
                {edits_retained: true, count_unchanged: true, refresh_required: app.profileRefreshRequired})
        } else if (kind === "refresh" && !app.profileActionPending) {
            complete(ready(app) && (command.expectedCount === undefined || app.savedProfileCount === command.expectedCount),
                {count: app.savedProfileCount, refresh_required: app.profileRefreshRequired})
        } else if (kind === "connect_save" && !app.profileActionPending) {
            check(ready(app) && app.editorMode === "" && status(app) === "Profile saved", "The loopback connection fixture could not save")
            app.openSelectedProfile(); awaiting.kind = "engine"; awaiting.at = Date.now()
        } else if (kind === "engine") {
            var candidate = engine(probe.Window.window.contentItem, 0)
            if (!candidate) return
            enginePid = candidate.appPid
            complete(true, {engine_window_ready: true, orientation: sessionOrientation,
                note: "Coordinator must await the real connected marker before sending input"})
        } else if (kind === "close") {
            if (ownEngine()) return
            enginePid = -1
            complete(true, {engine_window_closed: true})
        } else {
            var window = ownEngine()
            check(window !== null, "The diagnostic engine closed during a command")
            if (kind === "keyboard") {
                if (!Qt.inputMethod.visible || window.rdpLastViewportCommand <= 0) return
                var shown = geometry(window)
                result.orientations[sessionOrientation] = sameCanvas(beforeKeyboard, shown) && shown.toolbarReachable && shown.viewportHeight >= 240
                complete(result.orientations[sessionOrientation], shown)
            } else if (kind === "hide_keyboard") {
                if (Qt.inputMethod.visible || window.rdpKeyboardVisible || window.rdpLastViewportCommand !== 0) return
                var hidden = geometry(window)
                complete(beforeKeyboard && sameCanvas(beforeKeyboard, hidden) && hidden.toolbarReachable &&
                    hidden.viewportHeight === hidden.logicalHeight - 112, hidden)
            } else if (kind === "panel" && Date.now() - awaiting.at > 150) {
                var panel = find(window, "paperdeskRdpShortcutsPanel")
                var last = find(window, command.action === "navigation" ? "paperdeskRdpNav_Fit" : "paperdeskRdpFunction_F12")
                var bounds = last ? last.mapToItem(panel, 0, 0, last.width, last.height) : null
                complete(panel && panel.visible && last && last.visible && bounds.y + bounds.height < panel.height - 96,
                    {page: window.rdpShortcutPage, keyboard_visible: window.rdpKeyboardVisible, last_key_above_back: true})
            }
        }
    }
    function pollCommand() {
        if (done || phase !== 100 || awaiting || commandReadPending ||
                (subject.item && subject.item.profileActionPending)) return
        commandReadPending = true
        var request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE) return
            commandReadPending = false
            if (done || awaiting || !request.responseText) return
            var command
            try { command = JSON.parse(request.responseText) } catch (error) { return }
            if (!command || !Number.isInteger(command.revision) || command.revision <= lastRevision ||
                    typeof command.action !== "string") return
            try { execute(command) } catch (error) { finish(String(error)) }
        }
        try { request.open("GET", commandUrl); request.send() }
        catch (error) { commandReadPending = false; finish("Could not read the private command file") }
    }
    Loader { id: subject; anchors.fill: parent }
    Component.onCompleted: {
        if (!/^\d{1,5}$/.test(fixturePort) || Number(fixturePort) < 1 || Number(fixturePort) > 65535 ||
                fixtureUrl.indexOf("__RDP_") >= 0 || commandUrl.indexOf("__RDP_") >= 0) {
            finish("The diagnostic fixture placeholders were not staged")
            return
        }
        subject.setSource("production/ui/main.qml", {profileConfigurationUrl: fixtureUrl})
    }
    Timer { id: ticker; interval: 100; repeat: true; running: !probe.done
        onTriggered: { try { probe.tick() } catch (error) { probe.finish(String(error)) } } }
    Timer { id: commands; interval: 250; repeat: true; running: !probe.done; onTriggered: probe.pollCommand() }
}
