import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1760
    QtObject {
        id: credentials
        property var passwords: ({})
        property bool rejectSave: false
        property bool rejectForget: false
        property int serial: 0
        property int saves: 0
        property int forgets: 0
        function createCredentialId() {
            serial += 1
            return "00000000-0000-4000-8000-" + ("000000000000" + serial).slice(-12)
        }
        function hasSavedPassword(id, host, user, port) {
            var row = passwords[id]
            return !!row && row.host === host && row.user === user && row.port === port
        }
        function savePassword(id, host, user, port, password) {
            saves += 1
            if (rejectSave) return false
            passwords[id] = {host: host, user: user, port: port, password: password}
            return true
        }
        function forgetPassword(id) {
            forgets += 1
            if (rejectForget) return false
            delete passwords[id]; return true
        }
    }
    TestCase {
        name: "SshSavedSessions"
        when: windowShown
        function makePanel() {
            var component = Qt.createComponent("../../product/payload/apps/paperterminal/ui/Sessions.qml")
            compare(component.status, Component.Ready, component.errorString())
            credentials.passwords = ({}); credentials.rejectSave = false; credentials.rejectForget = false
            credentials.serial = 0; credentials.saves = 0; credentials.forgets = 0
            var panel = createTemporaryObject(component, scene, {width: scene.width, height: scene.height, credentialStore: credentials})
            verify(panel !== null, component.errorString())
            findChild(panel, "sshSessionSettings").sessionsJson = "[]"
            panel.load(); waitForRendering(panel)
            return panel
        }
        function tap(panel, name) {
            var button = findChild(panel, name)
            verify(button !== null && button.visible)
            mouseClick(button, button.width / 2, button.height / 2)
            wait(30)
        }
        function fill(panel, host) {
            findChild(panel, "sshSessionNameInput").text = "My server"
            findChild(panel, "sshSessionHostInput").text = host
            findChild(panel, "sshSessionUserInput").text = "tester"
            findChild(panel, "sshSessionPortInput").text = "2222"
        }
        function profile(panel, index) {
            return JSON.parse(findChild(panel, "sshSessionSettings").sessionsJson)[index || 0]
        }
        function seedTwoProfiles(panel) {
            findChild(panel, "sshSessionSettings").sessionsJson = JSON.stringify([
                {name: "Nostalgiczny", host: "one.example", user: "first", port: "22"},
                {name: "Lola", host: "two.example", user: "second", port: "2202"}
            ])
            panel.load(); waitForRendering(panel)
        }
        function connectionSpy(panel) {
            var open = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            open.target = panel; open.signalName = "connectRequested"
            return open
        }
        function doubleTapRow(row, x, y) {
            // QtQuickTest's mouse helper adds 500 ms after release, preventing
            // mouse double-click detection. Real touch packets keep timestamps.
            if (x === undefined) x = row.width / 2
            if (y === undefined) y = row.height / 2
            var sequence = touchEvent(row)
            sequence.press(0, row, x, y).commit()
            sequence.release(0, row, x, y).commit()
            wait(80)
            sequence.press(0, row, x, y).commit()
            sequence.release(0, row, x, y).commit()
            wait(30)
        }
        function test_single_click_selects_without_opening() {
            var panel = makePanel(); seedTwoProfiles(panel)
            var open = connectionSpy(panel)
            tap(panel, "sshSessionRow_1")
            compare(panel.selectedIndex, 1); compare(open.count, 0)
            wait(500); compare(open.count, 0)
        }
        function test_double_tap_opens_clicked_second_profile_exactly_once() {
            var panel = makePanel(); seedTwoProfiles(panel)
            var open = connectionSpy(panel), row = findChild(panel, "sshSessionRow_1")
            compare(panel.selectedIndex, 0)
            doubleTapRow(row)
            compare(panel.selectedIndex, 1); compare(open.count, 1)
            compare(open.signalArguments[0][0], "two.example")
            compare(open.signalArguments[0][1], "second")
            compare(open.signalArguments[0][2], "2202")
            wait(500); compare(open.count, 1)
        }
        function test_quick_clicks_on_different_rows_do_not_open_previous_profile() {
            var panel = makePanel(); seedTwoProfiles(panel)
            var open = connectionSpy(panel)
            var first = findChild(panel, "sshSessionRow_0"), second = findChild(panel, "sshSessionRow_1")
            mouseClick(first, first.width / 2, first.height / 2, Qt.LeftButton, Qt.NoModifier, 20)
            mouseClick(second, second.width / 2, second.height / 2, Qt.LeftButton, Qt.NoModifier, 20)
            compare(panel.selectedIndex, 1); compare(open.count, 0)
            wait(500); compare(open.count, 0)
        }
        function test_double_tap_busy_only_opens_confirmation() {
            var panel = makePanel(); seedTwoProfiles(panel)
            var open = connectionSpy(panel)
            var replacement = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            replacement.target = panel; replacement.signalName = "replacementRequested"
            panel.connectRequested.connect(function(host, user, port, credentialId) {
                panel.beginReplacement(host, user, port, credentialId, "busy-current-session")
            })
            var row = findChild(panel, "sshSessionRow_1")
            doubleTapRow(row)
            compare(open.count, 1); compare(replacement.count, 0)
            verify(findChild(panel, "sshSessionReplaceConfirmation").visible)
            compare(panel.replacementRequest.name, "Lola")
            keyClick(Qt.Key_Return); compare(replacement.count, 0)
            tap(panel, "sshSessionReplaceCancel")
            compare(panel.selectedIndex, 1); compare(replacement.count, 0)
        }
        function test_third_tap_overlapping_confirm_cannot_replace_session() {
            var panel = makePanel(), rows = []
            for (var i = 0; i < 12; ++i)
                rows.push({name: "Lola", host: "host" + i + ".example", user: "tester", port: "22"})
            findChild(panel, "sshSessionSettings").sessionsJson = JSON.stringify(rows)
            panel.load(); waitForRendering(panel)
            var replacement = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            replacement.target = panel; replacement.signalName = "replacementRequested"
            panel.beginReplacement("host7.example", "tester", "22", "", "preview")
            waitForRendering(panel)
            var confirm = findChild(panel, "sshSessionReplaceConfirm")
            var target = confirm.mapToItem(panel, confirm.width / 2, confirm.height / 2)
            panel.cancelReplacement(); panel.activeTerminalAvailable = false
            waitForRendering(panel)
            var scroll = findChild(panel, "sshSessionScroll"), row = findChild(panel, "sshSessionRow_7")
            scroll.contentY = row.mapToItem(panel, 0, row.height / 2).y - target.y
            waitForRendering(panel)
            var point = row.mapFromItem(panel, target.x, target.y)
            verify(point.y >= 0 && point.y <= row.height, "The row and future Confirm button overlap exactly")
            panel.connectRequested.connect(function(host, user, port, credentialId) {
                panel.beginReplacement(host, user, port, credentialId, "busy-current-session")
            })
            doubleTapRow(row, point.x, point.y)
            verify(findChild(panel, "sshSessionReplaceConfirmation").visible)
            var actual = confirm.mapToItem(panel, confirm.width / 2, confirm.height / 2)
            compare(actual.x, target.x); compare(actual.y, target.y)
            verify(!confirm.enabled)
            var sequence = touchEvent(confirm)
            sequence.press(0, confirm, confirm.width / 2, confirm.height / 2).commit()
            sequence.release(0, confirm, confirm.width / 2, confirm.height / 2).commit()
            compare(replacement.count, 0)
            verify(!panel.confirmReplacement(), "The production confirmation path is guarded too")
            tryCompare(confirm, "enabled", true)
            tap(panel, "sshSessionReplaceConfirm")
            compare(replacement.count, 1)
            compare(replacement.signalArguments[0][0], "host7.example")
        }
        function test_dragging_rows_scrolls_without_opening() {
            var panel = makePanel(), rows = []
            for (var i = 0; i < 20; ++i)
                rows.push({name: "Server " + i, host: "host" + i + ".example", user: "tester", port: "22"})
            findChild(panel, "sshSessionSettings").sessionsJson = JSON.stringify(rows)
            panel.load(); waitForRendering(panel)
            var open = connectionSpy(panel), scroll = findChild(panel, "sshSessionScroll")
            var row = findChild(panel, "sshSessionRow_1"), point = row.mapToItem(scroll, row.width / 2, row.height / 2)
            mouseDrag(scroll, point.x, point.y, 0, -220, Qt.LeftButton, Qt.NoModifier, 10)
            wait(100)
            verify(scroll.contentY > 0)
            compare(open.count, 0)
        }
        function test_second_profile_open_cancel_then_confirm_uses_frozen_request() {
            var panel = makePanel()
            seedTwoProfiles(panel)
            var replacement = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            replacement.target = panel; replacement.signalName = "replacementRequested"
            var token = "current-child-lease-42"
            panel.connectRequested.connect(function(host, user, port, credentialId) {
                panel.beginReplacement(host, user, port, credentialId, token)
            })
            tap(panel, "sshSessionRow_1"); compare(panel.selectedIndex, 1)
            tap(panel, "sshSessionOpen")
            var dialog = findChild(panel, "sshSessionReplaceConfirmation")
            verify(dialog.visible)
            compare(findChild(panel, "sshSessionReplaceTitle").text, "Close current session and connect to Lola?")
            compare(findChild(panel, "sshSessionReplaceTitle").textFormat, Text.PlainText)
            keyClick(Qt.Key_Return); compare(replacement.count, 0)
            verify(dialog.visible, "Enter cannot confirm ending an active session")
            tap(panel, "sshSessionReplaceCancel")
            verify(!dialog.visible); compare(replacement.count, 0); compare(panel.selectedIndex, 1)
            verify(findChild(panel, "sshSessionActiveTerminalBack").visible)
            tap(panel, "sshSessionOpen"); verify(dialog.visible)
            // A later model/token change cannot retarget the confirmation.
            panel.savedSessions.setProperty(1, "host", "changed.example")
            token = "new-child-lease-99"
            tap(panel, "sshSessionReplaceConfirm")
            compare(replacement.count, 1); verify(!dialog.visible)
            compare(replacement.signalArguments[0][0], "two.example")
            compare(replacement.signalArguments[0][1], "second")
            compare(replacement.signalArguments[0][2], "2202")
            compare(replacement.signalArguments[0][3], "")
            compare(replacement.signalArguments[0][4], "current-child-lease-42")
        }
        function test_replacement_back_keeps_request_unconfirmed_and_session_selected() {
            var panel = makePanel()
            seedTwoProfiles(panel); panel.choose(1)
            var replacement = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            replacement.target = panel; replacement.signalName = "replacementRequested"
            var back = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            back.target = panel; back.signalName = "activeTerminalRequested"
            verify(panel.beginReplacement("two.example", "second", "2202", "", "lease-42"))
            tap(panel, "sshSessionReplaceBack")
            compare(back.count, 1); compare(replacement.count, 0); compare(panel.selectedIndex, 1)
            compare(panel.replacementRequest, null)
            tap(panel, "sshSessionActiveTerminalBack"); compare(back.count, 2)
        }
        function test_nonbusy_failure_cannot_show_replacement_dialog() {
            var panel = makePanel()
            seedTwoProfiles(panel); panel.choose(1)
            verify(!panel.beginReplacement("two.example", "second", "2202", "", ""))
            verify(!findChild(panel, "sshSessionReplaceConfirmation").visible)
            panel.showMessage("Save the password again.")
            verify(!findChild(panel, "sshSessionReplaceConfirmation").visible)
            verify(!panel.confirmReplacement())
        }
        function test_real_taps_new_save_open_edit_delete_and_reload() {
            var panel = makePanel()
            var open = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            open.target = panel; open.signalName = "connectRequested"
            tap(panel, "sshSessionNew"); fill(panel, "server.example")
            tap(panel, "sshSessionSave")
            compare(panel.count, 1); compare(panel.mode, "")
            panel.load(); compare(panel.count, 1)
            tap(panel, "sshSessionRow_0"); tap(panel, "sshSessionOpen")
            compare(open.count, 1); compare(open.signalArguments[0][0], "server.example")
            compare(open.signalArguments[0][1], "tester"); compare(open.signalArguments[0][2], "2222")
            compare(open.signalArguments[0][3], "", "Opted-out profiles never request a stored password")
            tap(panel, "sshSessionEdit"); fill(panel, "changed.example"); tap(panel, "sshSessionSave")
            panel.load(); tap(panel, "sshSessionOpen")
            compare(open.signalArguments[1][0], "changed.example")
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteCancel"); compare(panel.count, 1)
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteConfirm"); compare(panel.count, 0)
            panel.load(); compare(panel.count, 0)
        }
        function test_keyboard_keeps_save_visible_and_port_scrollable() {
            var panel = makePanel()
            tap(panel, "sshSessionNew")
            panel.keyboardInset = 900
            var port = findChild(panel, "sshSessionPortInput")
            port.forceActiveFocus(); wait(80)
            var save = findChild(panel, "sshSessionSave"), scroll = findChild(panel, "sshSessionScroll")
            verify(scroll.contentY > 0)
            verify(save.mapToItem(panel, 0, save.height).y <= panel.height - panel.keyboardInset)
            verify(port.mapToItem(scroll, 0, port.height).y <= scroll.height)
            fill(panel, "::1"); tap(panel, "sshSessionSave"); compare(panel.count, 1)
            compare(scroll.contentY, 0)
            verify(findChild(panel, "sshSessionRow_0").mapToItem(scroll, 0, 0).y >= 0)
        }
        function test_password_is_opt_in_masked_and_never_in_settings() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            compare(panel.rememberPassword, false)
            var field = findChild(panel, "sshSessionPasswordInput")
            compare(field.echoMode, TextInput.Password)
            tap(panel, "sshSessionRememberPassword")
            verify(panel.rememberPassword)
            field.text = "test-password-only"
            tap(panel, "sshSessionSave")
            var id = profile(panel).credentialId
            verify(panel.validCredentialId(id)); compare(profile(panel).rememberPassword, true)
            verify(credentials.hasSavedPassword(id, "secret.example", "tester", "2222"))
            compare(field.text, "")
            var settings = findChild(panel, "sshSessionSettings")
            verify(settings.sessionsJson.indexOf("test-password-only") < 0)
            compare(JSON.parse(settings.sessionsJson)[0].host, "secret.example")
            panel.load(); tap(panel, "sshSessionEdit")
            verify(panel.rememberPassword)
            compare(field.text, "", "A stored password is never loaded into QML")
            tap(panel, "sshSessionSave")
            compare(profile(panel).credentialId, id)
            verify(credentials.hasSavedPassword(id, "secret.example", "tester", "2222"))
            tap(panel, "sshSessionEdit"); panel.rememberPassword = false
            tap(panel, "sshSessionSave")
            verify(!credentials.hasSavedPassword(id, "secret.example", "tester", "2222"))
            compare(profile(panel).rememberPassword, false)
        }
        function test_password_requires_value_and_is_cleared_on_cancel_or_close() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            panel.rememberPassword = true
            tap(panel, "sshSessionSave")
            compare(panel.count, 0); compare(panel.mode, "add")
            verify(panel.message.indexOf("Enter a password") >= 0)
            var field = findChild(panel, "sshSessionPasswordInput")
            var id = panel.editorCredentialId
            field.text = "never-save-this"
            tap(panel, "sshSessionCancel")
            compare(field.text, ""); verify(!panel.rememberPassword)
            verify(!credentials.hasSavedPassword(id, "secret.example", "tester", "2222"))
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            panel.rememberPassword = true; field.text = "also-never-save-this"
            panel.visible = false
            compare(field.text, ""); compare(panel.mode, "")
        }
        function test_password_edit_endpoint_and_delete_remove_previous_secret() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "first.example")
            panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "first-password"
            tap(panel, "sshSessionSave")
            var id = profile(panel).credentialId
            tap(panel, "sshSessionEdit"); fill(panel, "second.example")
            tap(panel, "sshSessionSave")
            compare(panel.mode, "edit", "Changing the server requires a new password")
            findChild(panel, "sshSessionPasswordInput").text = "second-password"
            tap(panel, "sshSessionSave")
            compare(profile(panel).credentialId, id)
            verify(!credentials.hasSavedPassword(id, "first.example", "tester", "2222"))
            verify(credentials.hasSavedPassword(id, "second.example", "tester", "2222"))
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteConfirm")
            verify(!credentials.hasSavedPassword(id, "second.example", "tester", "2222"))
        }
        function test_password_save_failure_keeps_metadata_and_visible_feedback() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "test-only"
            credentials.rejectSave = true
            var scroll = findChild(panel, "sshSessionScroll")
            scroll.contentY = 500
            tap(panel, "sshSessionSave")
            compare(panel.mode, "add"); compare(panel.count, 0)
            compare(scroll.contentY, 0)
            verify(panel.message.indexOf("could not be saved") >= 0)
            verify(findChild(panel, "sshSessionSettings").sessionsJson.indexOf("test-only") < 0)
        }
        function test_duplicate_endpoints_keep_independent_password_choices() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "same.example")
            panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "first-profile-password"
            tap(panel, "sshSessionSave")
            var firstId = profile(panel).credentialId
            tap(panel, "sshSessionNew"); fill(panel, "same.example")
            compare(panel.rememberPassword, false)
            tap(panel, "sshSessionSave")
            var secondId = profile(panel, 1).credentialId
            verify(firstId !== secondId)
            verify(credentials.hasSavedPassword(firstId, "same.example", "tester", "2222"))
            verify(!credentials.hasSavedPassword(secondId, "same.example", "tester", "2222"))
            var open = createTemporaryQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            open.target = panel; open.signalName = "connectRequested"
            tap(panel, "sshSessionOpen"); compare(open.signalArguments[0][3], "")
            tap(panel, "sshSessionEdit"); panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "second-profile-password"
            tap(panel, "sshSessionSave")
            compare(credentials.passwords[firstId].password, "first-profile-password")
            compare(credentials.passwords[secondId].password, "second-profile-password")
            tap(panel, "sshSessionEdit"); panel.rememberPassword = false
            tap(panel, "sshSessionSave")
            verify(credentials.hasSavedPassword(firstId, "same.example", "tester", "2222"))
            verify(!credentials.hasSavedPassword(secondId, "same.example", "tester", "2222"))
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteConfirm")
            verify(credentials.hasSavedPassword(firstId, "same.example", "tester", "2222"))
            tap(panel, "sshSessionOpen"); compare(open.signalArguments[1][3], firstId)
        }
        function test_endpoint_change_is_one_atomic_credential_operation() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "first.example")
            panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "old-password"
            tap(panel, "sshSessionSave")
            var id = profile(panel).credentialId
            tap(panel, "sshSessionEdit"); fill(panel, "second.example")
            findChild(panel, "sshSessionPasswordInput").text = "new-password"
            credentials.rejectForget = true
            var saves = credentials.saves, forgets = credentials.forgets
            tap(panel, "sshSessionSave")
            compare(panel.mode, ""); compare(credentials.saves, saves + 1)
            compare(credentials.forgets, forgets, "A host edit never deletes a second credential record")
            compare(profile(panel).credentialId, id); compare(profile(panel).host, "second.example")
            verify(!credentials.hasSavedPassword(id, "first.example", "tester", "2222"))
            verify(credentials.hasSavedPassword(id, "second.example", "tester", "2222"))
            var previousMetadata = findChild(panel, "sshSessionSettings").sessionsJson
            tap(panel, "sshSessionEdit"); fill(panel, "third.example")
            findChild(panel, "sshSessionPasswordInput").text = "rejected-password"
            credentials.rejectSave = true
            tap(panel, "sshSessionSave")
            compare(panel.mode, "edit")
            compare(findChild(panel, "sshSessionSettings").sessionsJson, previousMetadata)
            compare(credentials.passwords[id].password, "new-password")
            verify(credentials.hasSavedPassword(id, "second.example", "tester", "2222"))
            verify(!credentials.hasSavedPassword(id, "third.example", "tester", "2222"))
        }
        function test_legacy_and_duplicate_ids_migrate_to_stable_independent_profiles() {
            var panel = makePanel(), settings = findChild(panel, "sshSessionSettings")
            var legacy = {name: "Legacy", host: "same.example", user: "tester", port: "22"}
            settings.sessionsJson = JSON.stringify([legacy, legacy])
            panel.load()
            var first = profile(panel), second = profile(panel, 1)
            verify(panel.validCredentialId(first.credentialId))
            verify(panel.validCredentialId(second.credentialId))
            verify(first.credentialId !== second.credentialId)
            compare(first.rememberPassword, false); compare(second.rememberPassword, false)
            panel.load(); compare(profile(panel).credentialId, first.credentialId)
            compare(profile(panel, 1).credentialId, second.credentialId)
            first.rememberPassword = true
            credentials.savePassword(first.credentialId, first.host, first.user, first.port, "first-only-password")
            settings.sessionsJson = JSON.stringify([first, first])
            panel.load()
            compare(profile(panel).credentialId, first.credentialId)
            compare(profile(panel).rememberPassword, true)
            verify(profile(panel, 1).credentialId !== first.credentialId)
            compare(profile(panel, 1).rememberPassword, false)
            verify(settings.sessionsJson.indexOf("first-only-password") < 0)
        }
        function test_failed_opt_out_or_delete_keeps_profile_and_credential() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            panel.rememberPassword = true
            findChild(panel, "sshSessionPasswordInput").text = "retained-password"
            tap(panel, "sshSessionSave")
            var metadata = findChild(panel, "sshSessionSettings").sessionsJson, id = profile(panel).credentialId
            credentials.rejectForget = true
            tap(panel, "sshSessionEdit"); panel.rememberPassword = false
            tap(panel, "sshSessionSave")
            compare(panel.mode, "edit")
            compare(findChild(panel, "sshSessionSettings").sessionsJson, metadata)
            compare(credentials.passwords[id].password, "retained-password")
            tap(panel, "sshSessionCancel")
            tap(panel, "sshSessionDelete"); tap(panel, "sshSessionDeleteConfirm")
            compare(panel.count, 1)
            compare(findChild(panel, "sshSessionSettings").sessionsJson, metadata)
            compare(credentials.passwords[id].password, "retained-password")
        }
        function test_password_field_and_save_stay_above_keyboard() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "secret.example")
            panel.rememberPassword = true; panel.keyboardInset = 900
            waitForRendering(panel)
            var password = findChild(panel, "sshSessionPasswordInput")
            password.forceActiveFocus(); wait(80)
            var save = findChild(panel, "sshSessionSave"), scroll = findChild(panel, "sshSessionScroll")
            verify(scroll.contentY > 0)
            verify(password.mapToItem(scroll, 0, password.height).y <= scroll.height)
            verify(save.mapToItem(panel, 0, save.height).y <= panel.height - panel.keyboardInset)
        }
        function test_connection_feedback_is_visible_after_editing_with_keyboard() {
            var panel = makePanel()
            tap(panel, "sshSessionNew"); fill(panel, "server.example")
            panel.keyboardInset = 900
            var port = findChild(panel, "sshSessionPortInput")
            port.forceActiveFocus(); wait(80)
            tap(panel, "sshSessionSave")
            var scroll = findChild(panel, "sshSessionScroll")
            compare(scroll.contentY, 0)
            panel.showMessage("Connection is busy. Return to the menu first.")
            compare(scroll.contentY, 0)
            verify(panel.message.indexOf("busy") >= 0)
        }
        function test_validation_and_damaged_settings_are_safe() {
            var panel = makePanel()
            verify(!panel.valid("-oProxyCommand=x", "user", "22"))
            verify(!panel.valid("host\ncommand", "user", "22"))
            verify(!panel.valid("host", "user;touch", "22"))
            verify(!panel.valid("host", "user", "0"))
            verify(!panel.valid("host", "user", "65536"))
            verify(panel.valid("fe80::1%wlan0", "user-name", "22"))
            findChild(panel, "sshSessionSettings").sessionsJson = '{"malformed":true}'
            panel.load(); compare(panel.count, 0)
            compare(panel.selectedIndex, -1)
            tap(panel, "sshSessionNew"); fill(panel, "bad host")
            tap(panel, "sshSessionSave"); compare(panel.count, 0); compare(panel.mode, "add")
            tap(panel, "sshSessionCancel"); compare(panel.mode, "")
        }
    }
}
