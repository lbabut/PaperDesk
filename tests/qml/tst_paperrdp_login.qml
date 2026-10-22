import QtQuick 2.15
import QtTest 1.3
import net.asivery.AppLoad 1.0

Item {
    id: scene
    width: 1404
    height: 1872
    property var app: null

    TestCase {
        name: "PaperRdpNativeLogin"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperrdp-login/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.app = component.createObject(scene)
            verify(scene.app !== null, component.errorString())
            waitForRendering(scene.app)
        }

        function cleanupTestCase() {
            if (scene.app) scene.app.destroy()
        }

        function init() {
            AppLoadLauncher.reset()
            scene.app.connectionLaunching = false
            scene.app.profileActionPending = false
            scene.app.profileDomain = ""
            scene.app.editorMode = ""
            scene.app.deleteConfirmationIndex = -1
            scene.app.rememberPassword = true
            scene.app.orientation = "portrait"
        }

        function test_orientation_is_saved_per_profile_and_legacy_defaults_upright() {
            scene.app.parseSavedProfiles("v1\t686f7374\t75736572\t\t3389\t\t75\t8\n" +
                "v2\t77696465\t75736572\t\t3389\t\t75\t8\tlandscape\n")
            compare(scene.app.savedProfileCount, 2)
            scene.app.chooseProfile(1)
            compare(scene.app.orientation, "landscape")
            scene.app.chooseProfile(0)
            compare(scene.app.orientation, "portrait")
            scene.app.beginEditProfile()
            var scroll = findChild(scene.app, "rdpProfileScroll")
            scroll.contentY = scroll.contentHeight - scroll.height
            var wide = findChild(scene.app, "rdpOrientationButton_landscape")
            mouseClick(wide, wide.width / 2, wide.height / 2)
            compare(scene.app.orientation, "landscape")
            scene.app.saveProfileChanges()
            compare(AppLoadLauncher.lastArgs[9], "landscape")
            compare(AppLoadLauncher.lastArgs[10], "v2")
            scene.app.profileActionPending = false
            scene.app.chooseProfile(1)
            scene.app.chooseProfile(0)
            compare(scene.app.orientation, "landscape")
            scene.app.connectRdp()
            compare(AppLoadLauncher.lastArgs[14], "--orientation")
            compare(AppLoadLauncher.lastArgs[15], "landscape")
            scroll.contentY = 0
        }

        function test_backspace_edits_username() {
            var username = findChild(scene.app, "usernameInput")
            verify(username !== null)
            scene.app.editorMode = "edit"
            username.text = "lukasza"
            username.forceActiveFocus()
            keyClick(Qt.Key_Backspace)
            compare(username.text, "lukasz")
        }

        function test_keyboard_leaves_action_dock_and_focused_port_reachable() {
            scene.app.beginAddProfile()
            scene.app.keyboardInset = 710
            var port = findChild(scene.app, "portInput")
            var scroll = findChild(scene.app, "rdpProfileScroll")
            port.forceActiveFocus()
            scene.app.ensureFocusedFieldVisible(); wait(60)
            verify(scroll.contentY > 0)
            var save = findChild(scene.app, "rdpProfileSaveButton")
            verify(save.mapToItem(scene.app, 0, save.height).y <= scene.app.height - 710)
            verify(port.mapToItem(scroll, 0, port.height).y <= scroll.height)
            mouseClick(save, save.width / 2, save.height / 2)
            verify(scene.app.editorMode === "add", "An empty profile must fail validation, not save")
            scene.app.cancelProfileEdit()
            scene.app.keyboardInset = 0
        }

        function test_connect_launches_engine() {
            var closeSpy = Qt.createQmlObject('import QtTest 1.3; SignalSpy {}', scene)
            closeSpy.target = scene.app
            closeSpy.signalName = "close"
            var server = findChild(scene.app, "serverInput")
            var username = findChild(scene.app, "usernameInput")
            var password = findChild(scene.app, "passwordInput")
            var port = findChild(scene.app, "portInput")
            server.text = "192.168.1.113"
            username.text = "lukasz"
            password.text = "secret"
            port.text = "3389"
            scene.app.profileDomain = "WORKGROUP"
            scene.app.scalePercent = 50
            scene.app.colorDepth = 8
            scene.app.connectRdp()
            tryCompare(AppLoadLauncher, "launchCount", 1)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp")
            compare(AppLoadLauncher.lastArgs[0], "--host")
            compare(AppLoadLauncher.lastArgs[1], "192.168.1.113")
            compare(AppLoadLauncher.lastArgs[2], "--user")
            compare(AppLoadLauncher.lastArgs[3], "lukasz")
            compare(AppLoadLauncher.lastArgs[4], "--domain-hex")
            compare(AppLoadLauncher.lastArgs[5], "574f524b47524f5550")
            compare(AppLoadLauncher.lastArgs[6], "--password-hex")
            compare(AppLoadLauncher.lastArgs[7], "736563726574")
            compare(AppLoadLauncher.lastArgs[8], "--port")
            compare(AppLoadLauncher.lastArgs[9], "3389")
            compare(AppLoadLauncher.lastArgs[10], "--scale-percent")
            compare(AppLoadLauncher.lastArgs[11], "50")
            compare(AppLoadLauncher.lastArgs[12], "--color-depth")
            compare(AppLoadLauncher.lastArgs[13], "8")
            wait(650)
            compare(closeSpy.count, 0)
            closeSpy.destroy()
        }

        function test_connect_respects_password_storage_opt_out() {
            findChild(scene.app, "serverInput").text = "server.example"
            findChild(scene.app, "usernameInput").text = "reader"
            findChild(scene.app, "passwordInput").text = "session-only"
            findChild(scene.app, "portInput").text = "3389"
            scene.app.rememberPassword = false
            scene.app.connectRdp()
            verify(AppLoadLauncher.lastArgs.indexOf("--no-save-password") >= 0)
            compare(AppLoadLauncher.lastArgs[7], scene.app.toHex("session-only"))
            scene.app.connectionLaunching = false
            scene.app.rememberPassword = true
            scene.app.connectRdp()
            compare(AppLoadLauncher.lastArgs.indexOf("--no-save-password"), -1)
        }

        function test_connect_guard_allows_a_later_reconnect() {
            var server = findChild(scene.app, "serverInput")
            var username = findChild(scene.app, "usernameInput")
            var port = findChild(scene.app, "portInput")
            server.text = "nostalgiczny"
            username.text = "lukasz"
            port.text = "3389"
            scene.app.connectRdp()
            scene.app.connectRdp()
            compare(AppLoadLauncher.launchCount, 1)
            tryCompare(scene.app, "connectionLaunching", false, 1400)
            scene.app.connectRdp()
            compare(AppLoadLauncher.launchCount, 2)
        }

        function test_close_action_emits_once() {
            var close = findChild(scene.app, "rdpCloseButton")
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = scene.app
            mouseClick(close, close.width / 2, close.height / 2, Qt.LeftButton)
            compare(spy.count, 1)
            spy.destroy()
        }

        function test_keyboard_and_all_editors_are_real_targets() {
            verify(findChild(scene.app, "rdpKeyboardButton") !== null)
            for (var name of ["serverInput", "usernameInput", "passwordInput", "portInput"])
                verify(findChild(scene.app, name) !== null, name)
            verify(findChild(scene.app, "rdpSavedProfilesList") !== null)
            verify(findChild(scene.app, "rdpRememberPasswordButton") !== null)
            for (var action of ["New", "Edit", "Delete", "Cancel", "Save"])
                verify(findChild(scene.app, "rdpProfile" + action + "Button") !== null, action)
            verify(findChild(scene.app, "rdpDeleteConfirmation") !== null)
            verify(findChild(scene.app, "rdpDeleteCancelButton") !== null)
            verify(findChild(scene.app, "rdpDeleteConfirmButton") !== null)
            verify(findChild(scene.app, "rdpProfileOpenButton") === null)
            for (var scale of [50, 75, 100])
                verify(findChild(scene.app, "rdpScaleButton_" + scale) !== null)
            for (var depth of [8, 16, 24])
                verify(findChild(scene.app, "rdpColorDepthButton_" + depth) !== null)
        }

        function test_performance_selectors_are_touch_native() {
            var scale = findChild(scene.app, "rdpScaleButton_75")
            var colors = findChild(scene.app, "rdpColorDepthButton_8")
            verify(scale !== null && colors !== null)
            scene.app.editorMode = "edit"
            mouseClick(scale, scale.width / 2, scale.height / 2, Qt.LeftButton)
            mouseClick(colors, colors.width / 2, colors.height / 2, Qt.LeftButton)
            compare(scene.app.scalePercent, 75)
            compare(scene.app.colorDepth, 8)
        }

        function test_profile_layout_is_vertical_clear_and_on_screen() {
            scene.app.parseSavedProfiles(
                "v1\t" + scene.app.toHex("first-server") + "\t" + scene.app.toHex("first-user") +
                "\t\t3389\t\t75\t8\n" +
                "v1\t" + scene.app.toHex("second-server") + "\t" + scene.app.toHex("second-user") +
                "\t\t3390\t\t100\t16\n")
            scene.app.chooseProfile(0)
            waitForRendering(scene.app)

            var list = findChild(scene.app, "rdpSavedProfilesList")
            var create = findChild(scene.app, "rdpProfileNewButton")
            var edit = findChild(scene.app, "rdpProfileEditButton")
            var remove = findChild(scene.app, "rdpProfileDeleteButton")
            var cancel = findChild(scene.app, "rdpProfileCancelButton")
            var save = findChild(scene.app, "rdpProfileSaveButton")
            var saveLabel = findChild(scene.app, "rdpProfileSaveLabel")
            var connectButton = findChild(scene.app, "connectButton")
            var connect = findChild(scene.app, "rdpConnectLabel")
            compare(list.flickableDirection, Flickable.VerticalFlick)
            compare(connect.text, "Connect")
            verify(findChild(scene.app, "rdpProfileOpenButton") === null)

            var createPosition = create.mapToItem(scene.app, 0, 0)
            var editPosition = edit.mapToItem(scene.app, 0, 0)
            var removePosition = remove.mapToItem(scene.app, 0, 0)
            verify(createPosition.x + create.width <= editPosition.x)
            verify(editPosition.x + edit.width <= removePosition.x)
            verify(removePosition.x + remove.width <= scene.app.width)
            verify(Math.abs(createPosition.y - editPosition.y) < 2)
            verify(Math.abs(editPosition.y - removePosition.y) < 2)

            mouseClick(create, create.width / 2, create.height / 2, Qt.LeftButton)
            compare(scene.app.editorMode, "add")
            verify(cancel.visible)
            verify(save.visible)
            compare(saveLabel.text, "Save new profile")
            verify(!connectButton.visible)
            mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)
            compare(scene.app.editorMode, "")
            verify(connectButton.visible)
            compare(connect.text, "Connect")
        }

        function test_saved_profiles_populate_fields_and_keep_edits() {
            var host = scene.app.toHex("nostalgiczny")
            var user = scene.app.toHex("lukasz")
            var domain = scene.app.toHex("HOME")
            var secondHost = scene.app.toHex("office")
            var secondUser = scene.app.toHex("admin")
            var secondDomain = scene.app.toHex("WORK")
            scene.app.parseSavedProfiles(
                "v1\t" + host + "\t" + user + "\t" + domain + "\t3389\t" + scene.app.toHex("old") + "\t100\t16\n" +
                "v1\t" + secondHost + "\t" + secondUser + "\t" + secondDomain + "\t3390\t\t75\t8\n")
            compare(scene.app.savedProfileCount, 2)
            scene.app.chooseProfile(0)
            compare(findChild(scene.app, "serverInput").text, "nostalgiczny")
            compare(findChild(scene.app, "usernameInput").text, "lukasz")
            compare(findChild(scene.app, "passwordInput").text, "old")
            compare(scene.app.profileDomain, "HOME")
            compare(scene.app.scalePercent, 100)
            compare(scene.app.colorDepth, 16)

            findChild(scene.app, "passwordInput").text = "new"
            scene.app.scalePercent = 50
            scene.app.colorDepth = 8
            scene.app.beginEditProfile()
            scene.app.saveProfileChanges()
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp-profile")
            compare(AppLoadLauncher.lastArgs[0], "--save")
            compare(AppLoadLauncher.lastArgs[1], "0")
            scene.app.profileActionPending = false
            scene.app.chooseProfile(0)
            compare(findChild(scene.app, "passwordInput").text, "new")
            compare(scene.app.scalePercent, 50)
            compare(scene.app.colorDepth, 8)
            compare(scene.app.profileDomain, "HOME")

            scene.app.chooseProfile(1)
            compare(scene.app.profileDomain, "WORK")
            scene.app.connectionLaunching = false
            scene.app.connectRdp()
            compare(AppLoadLauncher.lastArgs[4], "--domain-hex")
            compare(scene.app.fromHex(AppLoadLauncher.lastArgs[5]), "WORK")
        }

        function test_profile_actions_new_edit_cancel_delete_and_connect() {
            scene.app.parseSavedProfiles(
                "v1\t" + scene.app.toHex("first") + "\t" + scene.app.toHex("user") +
                "\t\t3389\t\t75\t8\n" +
                "v1\t" + scene.app.toHex("second") + "\t" + scene.app.toHex("admin") +
                "\t\t3390\t\t100\t16\n")
            scene.app.chooseProfile(0)

            var add = findChild(scene.app, "rdpProfileNewButton")
            var edit = findChild(scene.app, "rdpProfileEditButton")
            var remove = findChild(scene.app, "rdpProfileDeleteButton")
            var deleteOverlay = findChild(scene.app, "rdpDeleteConfirmation")
            var deleteConfirm = findChild(scene.app, "rdpDeleteConfirmButton")
            var cancel = findChild(scene.app, "rdpProfileCancelButton")
            var save = findChild(scene.app, "rdpProfileSaveButton")
            var primary = findChild(scene.app, "connectButton")
            mouseClick(add, add.width / 2, add.height / 2, Qt.LeftButton)
            compare(scene.app.editorMode, "add")
            verify(scene.app.rememberPassword)
            verify(cancel.visible)
            mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)
            compare(scene.app.editorMode, "")
            compare(findChild(scene.app, "serverInput").text, "first")

            mouseClick(add, add.width / 2, add.height / 2, Qt.LeftButton)
            findChild(scene.app, "serverInput").text = "new-host"
            findChild(scene.app, "usernameInput").text = "new-user"
            findChild(scene.app, "passwordInput").text = "new-password"
            var remember = findChild(scene.app, "rdpRememberPasswordButton")
            mouseClick(remember, remember.width / 2, remember.height / 2, Qt.LeftButton)
            verify(!scene.app.rememberPassword)
            mouseClick(save, save.width / 2, save.height / 2, Qt.LeftButton)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp-profile")
            compare(AppLoadLauncher.lastArgs[0], "--save")
            compare(AppLoadLauncher.lastArgs[1], "-1")
            compare(AppLoadLauncher.lastArgs[6], "")
            compare(scene.app.savedProfileCount, 3)

            scene.app.profileActionPending = false
            mouseClick(edit, edit.width / 2, edit.height / 2, Qt.LeftButton)
            compare(scene.app.editorMode, "edit")
            verify(!scene.app.rememberPassword)
            findChild(scene.app, "serverInput").text = "edited-host"
            mouseClick(remember, remember.width / 2, remember.height / 2, Qt.LeftButton)
            verify(scene.app.rememberPassword)
            mouseClick(save, save.width / 2, save.height / 2, Qt.LeftButton)
            compare(AppLoadLauncher.lastArgs[0], "--save")
            compare(AppLoadLauncher.lastArgs[1], "0")
            compare(scene.app.savedProfileCount, 3)

            scene.app.profileActionPending = false
            mouseClick(remove, remove.width / 2, remove.height / 2, Qt.LeftButton)
            compare(scene.app.deleteConfirmationIndex, 0)
            verify(deleteOverlay.visible)
            compare(AppLoadLauncher.lastArgs[0], "--save")
            mouseClick(deleteConfirm, deleteConfirm.width / 2, deleteConfirm.height / 2, Qt.LeftButton)
            verify(!deleteOverlay.visible)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp-profile")
            compare(AppLoadLauncher.lastArgs[0], "--delete")
            compare(AppLoadLauncher.lastArgs[1], "0")
            compare(scene.app.savedProfileCount, 2)

            scene.app.profileActionPending = false
            scene.app.connectionLaunching = false
            mouseClick(primary, primary.width / 2, primary.height / 2, Qt.LeftButton)
            compare(AppLoadLauncher.lastApplicationId, "external::paperrdp")
            compare(AppLoadLauncher.lastArgs[0], "--host")
        }

        function test_profile_hex_round_trips_unicode() {
            var value = "Łukasz · żółć"
            compare(scene.app.fromHex(scene.app.toHex(value)), value)
        }

        function test_actions_share_one_visual_system() {
            var close = findChild(scene.app, "rdpCloseButton")
            var keyboard = findChild(scene.app, "rdpKeyboardButton")
            var closeLabel = findChild(scene.app, "rdpCloseLabel")
            var keyboardLabel = findChild(scene.app, "rdpKeyboardLabel")
            var connectLabel = findChild(scene.app, "rdpConnectLabel")
            verify(close !== null && keyboard !== null)
            compare(close.width, 176)
            compare(keyboard.width, close.width)
            compare(close.height, 76)
            compare(keyboard.height, close.height)
            compare(close.radius, 8)
            compare(keyboard.radius, close.radius)
            compare(closeLabel.font.pointSize, 16)
            compare(keyboardLabel.font.pointSize, closeLabel.font.pointSize)
            compare(connectLabel.font.pointSize, closeLabel.font.pointSize)
            verify(closeLabel.font.bold)
            verify(keyboardLabel.font.bold)
            verify(connectLabel.font.bold)
        }
    }
}
