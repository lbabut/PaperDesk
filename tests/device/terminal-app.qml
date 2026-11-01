import QtQuick 2.15
import QtQuick.Window 2.15

// This harness calls the production QML and native PTY APIs inside Xochitl.
// It deliberately does not inject touch, pen, keyboard or /dev/input events.
Rectangle {
    id: probe
    anchors.fill: parent
    color: "white"
    signal close
    property int phase: 0
    property real at: Date.now()
    property real began: Date.now()
    property real captureHoldUntil: 0
    property bool done: false
    property int idleFrames: 0
    property string activeShellToken: ""
    property var result: ({execution: "production QML and native PTY inside actual AppLoad/Xochitl", physical_touch_tested: false, physical_ghosting_measured: false, screenshots: {}})

    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        if (item.children) for (var i = 0; i < item.children.length; ++i) {
            var child = find(item.children[i], name)
            if (child) return child
        }
        return null
    }
    function geometry(renderer) {
        return {columns: renderer.terminalSize.width, rows: renderer.terminalSize.height,
                cell_width: renderer.cellSize.width, cell_height: renderer.cellSize.height,
                width: renderer.width, height: renderer.height,
                top: renderer.mapToItem(subject.item, 0, 0).y}
    }
    function observe(name, next) {
        // Scene-graph grabs require layers unsupported by this e-paper
        // backend. Record the real production scene without capturing it.
        result.screenshots[name] = {captured: false, reason: "vendor capture unavailable", width: probe.width, height: probe.height}
        console.log("PAPERTERMINAL_APP_STATE " + name)
        captureHoldUntil = Date.now() + 500
        phase = next
        at = captureHoldUntil
    }
    function finish(error) {
        if (done) return
        done = true
        ticker.stop()
        result.error = error || ""
        result.elapsed_ms = Date.now() - began
        result.passed = !error && result.native_running && result.initial_frames > 0 && result.valid_session &&
            result.invalid_session_rejected && result.font_resize && result.keyboard_visible &&
            result.keyboard_reduced_rows && result.keyboard_hidden && result.keyboard_restored_rows &&
            result.connection_finished && result.diagnostic_retained && result.non_return_keeps_diagnostic &&
            result.return_starts_menu && result.idle_frame_delta === 0 && result.mouse_on_by_default &&
            result.password_opt_in_cycle && result.saved_open_from_list && result.reopen_without_enter &&
            result.busy_refusal_visible && result.busy_refusal_does_not_cover_terminal &&
            result.two_saved_session_fixtures && result.second_session_selected &&
            result.replacement_cancel_keeps_shell && result.replacement_confirm_opens_second &&
            result.shortcuts_reserve_space && result.display_reserves_space && result.panels_restore_geometry &&
            result.home_initially_visible && result.home_numbered_fixture && result.home_open_from_row &&
            result.home_returns_after_local_shell && result.home_number_input && result.home_returns_after_number &&
            result.modifier_controls_and_status && result.function_tab_twelve_keys && result.keys_tab_restored &&
            result.modifiers_reset_for_sessions && result.modifiers_reset_on_home &&
            result.modifiers_reset_on_connect && result.shortcuts_with_keyboard
        if (subject.item) subject.item.unloading()
        console.log("PAPERTERMINAL_APP_RESULT " + JSON.stringify(result))
    }
    function step() {
        if (done) return
        var now = Date.now()
        if (now - began > 60000) { finish("Timed out in phase " + phase); return }
        if (now < captureHoldUntil) return
        var app = subject.item
        if (!app) {
            if (subject.status === Loader.Error) finish("Production QML failed to load")
            return
        }
        var renderer = find(app, "terminalRenderer")
        var sessions = find(app, "terminalSessionsPanel")
        var home = find(app, "terminalHomePanel")
        if (!renderer || !sessions || !home) return
        if (phase === 0) {
            if (!renderer.running || !renderer.menuReady || now - began < 1200) return
            app.hideSystemKeyboard()
            result.native_running = true
            result.home_initially_visible = home.visible
            phase = 1; at = now; return
        }
        if (phase === 1 && now - at > 2000) {
            app.hideSystemKeyboard()
            phase = 101; at = now; return
        }
        if (phase === 101 && now - at > 1200) {
            result.initial_geometry = geometry(renderer)
            result.initial_frames = app.terminalUpdateCount
            result.initial_font_size = app.terminalFontSize
            app.shortcutsOpen = true
            phase = 102; at = now; return
        }
        if (phase === 102 && now - at > 700) {
            var expanded = geometry(renderer)
            result.shortcuts_reserve_space = expanded.top - result.initial_geometry.top === app.terminalPanelHeight &&
                result.initial_geometry.height - expanded.height === app.terminalPanelHeight && app.terminalPanelHeight > 0
            var shortcuts = find(app, "terminalShortcutsPanel")
            var ctrl = find(shortcuts, "terminalModifierCtrl"), alt = find(shortcuts, "terminalModifierAlt")
            var functions = find(shortcuts, "terminalShortcutFunctionTab")
            if (!shortcuts || !ctrl || !alt || !functions) { finish("The shortcut modifier controls are missing"); return }
            // Invoke the production tap/hold signals. Actual physical long
            // presses are checked by host QtTest, not injected on the tablet.
            ctrl.triggered()
            var ctrlNext = renderer.latchedModifiers === Qt.ControlModifier && renderer.lockedModifiers === 0
            ctrl.held()
            alt.triggered()
            var status = find(app, "terminalModifierStatus")
            result.modifier_controls_and_status = ctrlNext && renderer.latchedModifiers === Qt.AltModifier &&
                renderer.lockedModifiers === Qt.ControlModifier && shortcuts.modifierState(Qt.ControlModifier) === 2 &&
                shortcuts.modifierState(Qt.AltModifier) === 1 && status &&
                status.text.indexOf("CTRL locked") >= 0 && status.text.indexOf("ALT next") >= 0
            functions.triggered()
            phase = 105; at = now; return
        }
        if (phase === 105 && now - at > 300) {
            var functionPanel = find(app, "terminalShortcutsPanel")
            var allFunctions = functionPanel && functionPanel.functionKeysOpen
            for (var number = 1; number <= 12; ++number) {
                var functionKey = find(functionPanel, "terminalShortcut_F" + number)
                allFunctions = allFunctions && functionKey && functionKey.visible &&
                    functionKey.mapToItem(functionPanel, 0, functionKey.height).y <= functionPanel.height
            }
            result.function_tab_twelve_keys = !!allFunctions
            var keysTab = find(functionPanel, "terminalShortcutKeysTab")
            if (!keysTab) { finish("The shortcut Keys tab is missing"); return }
            keysTab.triggered()
            phase = 106; at = now; return
        }
        if (phase === 106 && now - at > 300) {
            var keysPanel = find(app, "terminalShortcutsPanel")
            var tabKey = find(keysPanel, "terminalShortcut_TAB")
            result.keys_tab_restored = keysPanel && !keysPanel.functionKeysOpen && tabKey && tabKey.visible
            sessions.visible = true
            result.modifiers_reset_for_sessions = renderer.latchedModifiers === 0 && renderer.lockedModifiers === 0
            sessions.visible = false
            app.shortcutsOpen = false
            app.displayOpen = true
            phase = 103; at = now; return
        }
        if (phase === 103 && now - at > 700) {
            var displayed = geometry(renderer)
            result.display_reserves_space = displayed.top - result.initial_geometry.top === app.terminalPanelHeight &&
                result.initial_geometry.height - displayed.height === app.terminalPanelHeight && app.terminalPanelHeight > 0
            app.displayOpen = false
            phase = 104; at = now; return
        }
        if (phase === 104 && now - at > 700) {
            result.panels_restore_geometry = geometry(renderer).height === result.initial_geometry.height &&
                geometry(renderer).top === result.initial_geometry.top
            observe("menu", 2); return
        }
        if (phase === 2) {
            app.adjustFontSize(2)
            phase = 3; at = now; return
        }
        if (phase === 3 && now - at > 1200) {
            result.resized_geometry = geometry(renderer)
            result.font_resize = app.terminalFontSize === result.initial_font_size + 2 &&
                renderer.cellSize.height > result.initial_geometry.cell_height &&
                renderer.terminalSize.height < result.initial_geometry.rows
            app.showSystemKeyboard()
            phase = 4; at = now; return
        }
        if (phase === 4 && now - at > 2000) {
            result.keyboard_visible = Qt.inputMethod.visible
            result.keyboard_inset = app.keyboardInset
            result.keyboard_geometry = geometry(renderer)
            result.keyboard_reduced_rows = app.keyboardInset > 0 && renderer.terminalSize.height < result.resized_geometry.rows
            app.shortcutsOpen = true
            phase = 401; at = now; return
        }
        if (phase === 401 && now - at > 700) {
            var keyboardShortcuts = find(app, "terminalShortcutsPanel")
            result.shortcuts_with_keyboard = Qt.inputMethod.visible && keyboardShortcuts && keyboardShortcuts.visible &&
                geometry(renderer).top - result.keyboard_geometry.top === app.terminalPanelHeight &&
                renderer.height >= 240 && renderer.terminalSize.height > 0
            app.shortcutsOpen = false
            app.hideSystemKeyboard()
            phase = 5; at = now; return
        }
        if (phase === 5 && now - at > 1200) {
            result.keyboard_hidden = !Qt.inputMethod.visible && app.keyboardInset === 0
            result.keyboard_restored_rows = renderer.terminalSize.height === result.resized_geometry.rows
            result.valid_session = sessions.valid("127.0.0.1", "paperterminal-probe", "1")
            result.invalid_session_rejected = !sessions.valid("-oProxyCommand=anything", "root", "22") &&
                !sessions.valid("127.0.0.1", "root;echo bad", "22") &&
                !sessions.valid("127.0.0.1", "root", "65536")
            result.mouse_on_by_default = app.mouseMode
            if (sessions.count !== 0) { finish("The probe must start with isolated saved-session settings"); return }
            sessions.visible = true
            sessions.edit(true)
            if (sessions.mode !== "add") { finish("Could not start a disposable saved-session fixture"); return }
            find(sessions, "sshSessionNameInput").text = "Disposable terminal diagnostic"
            find(sessions, "sshSessionHostInput").text = "127.0.0.1"
            find(sessions, "sshSessionUserInput").text = "paperterminal-probe"
            find(sessions, "sshSessionPortInput").text = "2"
            sessions.rememberPassword = true
            find(sessions, "sshSessionPasswordInput").text = "Disposable-local-fixture-42"
            var firstSaved = sessions.save()
            if (!firstSaved || sessions.count !== 1 || sessions.selectedIndex !== 0) {
                finish("The disposable saved-session fixture could not be created"); return
            }
            sessions.edit(false)
            var savedAndMasked = sessions.storedPassword && find(sessions, "sshSessionPasswordInput").text.length === 0
            sessions.rememberPassword = false
            var disabledSaved = sessions.save()
            if (!disabledSaved) { finish("Could not disable the disposable fixture's password"); return }
            sessions.edit(false)
            var removed = !sessions.storedPassword
            sessions.cancelEdit()
            // Settings is a nonvisual QObject, so it is not in children().
            // Host QtTest checks its metadata whitelist separately.
            result.password_opt_in_cycle = firstSaved && savedAndMasked && disabledSaved && removed
            sessions.edit(true)
            if (sessions.mode !== "add") { finish("Could not start the second disposable fixture"); return }
            find(sessions, "sshSessionNameInput").text = "Second disposable terminal diagnostic"
            find(sessions, "sshSessionHostInput").text = "127.0.0.1"
            find(sessions, "sshSessionUserInput").text = "paperterminal-probe"
            find(sessions, "sshSessionPortInput").text = "1"
            sessions.rememberPassword = false
            var secondSaved = sessions.save()
            result.two_saved_session_fixtures = secondSaved && sessions.count === 2 && sessions.selectedIndex === 1 &&
                sessions.savedSessions.get(0).port === "2" && sessions.savedSessions.get(1).port === "1" &&
                !sessions.savedSessions.get(0).rememberPassword && !sessions.savedSessions.get(1).rememberPassword
            if (!result.two_saved_session_fixtures) { finish("The two isolated saved-session fixtures could not be created"); return }
            sessions.visible = false
            phase = 500; at = now; return
        }
        if (phase === 500) {
            // ListView can create the first delegate on a later polish pass
            // after its hidden model changes. Await that real row, not a
            // fixed delay or the synchronous save() callback.
            var homeRow = find(home, "terminalHomeSession_0")
            var homeLabel = find(home, "terminalHomeSessionLabel_0")
            var secondHomeRow = find(home, "terminalHomeSession_1")
            var secondHomeLabel = find(home, "terminalHomeSessionLabel_1")
            if (!renderer.menuReady || !home.visible || !homeRow || !homeLabel || !secondHomeRow || !secondHomeLabel) return
            result.home_numbered_fixture = home.visible && homeRow && homeRow.visible && homeLabel &&
                homeLabel.text.indexOf("1 - Disposable terminal diagnostic") === 0 && secondHomeRow.visible &&
                secondHomeLabel.text.indexOf("2 - Second disposable terminal diagnostic") === 0
            if (!result.home_numbered_fixture) { finish("The numbered Home fixture is missing"); return }
            var localShell = find(home, "terminalHomeLocalShell")
            if (!localShell || !localShell.visible) { finish("The Home local-shell action is missing"); return }
            // Execute the same production signal as a tap; no device input is
            // injected. Numeric input below exercises the native routing too.
            localShell.triggered()
            phase = 501; at = now; return
        }
        if (phase === 501 && now - at > 1000 && !renderer.menuReady) {
            sessions.visible = true
            sessions.choose(1)
            sessions.openSelected()
            var replacement = find(sessions, "sshSessionReplaceConfirmation")
            var cancel = find(sessions, "sshSessionReplaceCancel")
            var request = sessions.replacementRequest
            activeShellToken = renderer.replacementToken
            result.second_session_selected = sessions.selectedIndex === 1
            result.busy_refusal_visible = sessions.visible && renderer.sessionError.length > 0 &&
                find(sessions, "sshSessionScroll").contentY === 0 && replacement && replacement.visible &&
                request && request.host === "127.0.0.1" && request.port === "1" && request.credentialId === "" &&
                request.expectedToken === activeShellToken && activeShellToken.length > 0
            if (!result.busy_refusal_visible || !cancel) { finish("Opening the second fixture did not offer a session replacement"); return }
            cancel.triggered()
            phase = 503; at = now; return
        }
        if (phase === 503 && now - at > 300) {
            result.replacement_cancel_keeps_shell = sessions.visible && sessions.selectedIndex === 1 &&
                !sessions.replacementRequest && renderer.running && !renderer.menuReady &&
                renderer.replacementToken === activeShellToken
            var back = find(sessions, "sshSessionActiveTerminalBack")
            if (!result.replacement_cancel_keeps_shell || !back || !back.visible) {
                finish("Cancel did not preserve the active shell and second saved-session selection"); return
            }
            back.triggered()
            result.busy_refusal_does_not_cover_terminal = !sessions.visible && !find(app, "terminalErrorPanel").visible &&
                renderer.running && renderer.replacementToken === activeShellToken
            sessions.visible = true
            sessions.openSelected()
            var confirm = find(sessions, "sshSessionReplaceConfirm")
            var frozenRequest = sessions.replacementRequest
            if (!confirm || !confirm.visible || !frozenRequest || frozenRequest.port !== "1" ||
                    frozenRequest.expectedToken.length === 0 || frozenRequest.expectedToken !== renderer.replacementToken ||
                    sessions.selectedIndex !== 1) {
                finish("The second replacement request did not retain its selected endpoint"); return
            }
            activeShellToken = frozenRequest.expectedToken
            confirm.triggered()
            result.replacement_confirm_opens_second = !sessions.visible && sessions.selectedIndex === 1 &&
                !sessions.replacementRequest && renderer.sessionError.length === 0 &&
                renderer.replacementToken !== activeShellToken
            if (!result.replacement_confirm_opens_second) { finish("Confirm did not open the second disposable connection"); return }
            // A new Home generation must clear modifiers after this failed
            // loopback connection, just as it does after a normal exit.
            renderer.lockModifier(Qt.ControlModifier)
            phase = 504; at = now; return
        }
        if (phase === 504 && now - at > 1200 && !renderer.running) {
            renderer.vkbKeyPress(Qt.Key_Return, Qt.NoModifier)
            phase = 502; at = now; return
        }
        if (phase === 502 && renderer.menuReady) {
            result.home_returns_after_local_shell = home.visible
            result.modifiers_reset_on_home = renderer.latchedModifiers === 0 && renderer.lockedModifiers === 0
            var fixture = find(home, "terminalHomeSession_1")
            if (!fixture || !fixture.visible) { finish("The Home fixture disappeared after the local shell"); return }
            renderer.cycleModifier(Qt.AltModifier)
            fixture.triggered()
            result.home_open_from_row = !renderer.menuReady && !sessions.visible && renderer.sessionError.length === 0
            result.modifiers_reset_on_connect = renderer.latchedModifiers === 0 && renderer.lockedModifiers === 0
            phase = 6; at = now; return
        }
        if (phase === 6 && now - at > 1200) {
            app.hideSystemKeyboard()
            if (renderer.error) { finish("Saved connection rejected: " + renderer.error); return }
            if (renderer.running) return
            result.connection_finished = true
            idleFrames = app.terminalUpdateCount
            phase = 7; at = now; return
        }
        if (phase === 7 && now - at > 1800) {
            result.diagnostic_retained = !renderer.running
            idleFrames = app.terminalUpdateCount
            observe("diagnostic", 8); return
        }
        if (phase === 8 && now - at > 2200) {
            result.idle_frame_delta = app.terminalUpdateCount - idleFrames
            observe("diagnostic_later", 9); return
        }
        if (phase === 9) {
            renderer.vkbKeyPress(Qt.Key_A, Qt.NoModifier, "a")
            phase = 10; at = now; return
        }
        if (phase === 10 && now - at > 500) {
            result.non_return_keeps_diagnostic = !renderer.running
            sessions.visible = true
            sessions.openSelected()
            result.reopen_without_enter = !sessions.visible && renderer.sessionError.length === 0
            result.saved_open_from_list = result.reopen_without_enter
            phase = 110; at = now; return
        }
        if (phase === 110 && now - at > 1600) {
            if (renderer.running) return
            renderer.vkbKeyPress(Qt.Key_Return, Qt.NoModifier)
            phase = 11; at = now; return
        }
        if (phase === 11 && renderer.menuReady) {
            result.return_starts_menu = renderer.running && home.visible
            observe("returned_menu", 12); return
        }
        if (phase === 12) {
            // A whole text packet is deliberately used, matching a native
            // keyboard commit/paste and the menuInput(QString) contract.
            renderer.putString("2\r")
            result.home_number_input = !renderer.menuReady && renderer.sessionError.length === 0
            phase = 13; at = now; return
        }
        if (phase === 13 && now - at > 1200 && !renderer.running) {
            renderer.vkbKeyPress(Qt.Key_Return, Qt.NoModifier)
            phase = 14; at = now; return
        }
        if (phase === 14 && renderer.menuReady) {
            result.home_returns_after_number = renderer.running && home.visible
            finish("")
        }
    }
    Loader { id: subject; anchors.fill: parent; source: "production/ui/main.qml" }
    Timer {
        id: ticker
        interval: 100; repeat: true; running: true
        onTriggered: {
            try { probe.step() }
            catch (error) { probe.finish(String(error)) }
        }
    }
}
