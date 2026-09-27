import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404
    height: 1872
    property var care: null

    TestCase {
        name: "PaperDeskCare"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/papercare/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.care = component.createObject(scene)
            verify(scene.care !== null, component.errorString())
            waitForRendering(scene.care)
        }

        function cleanupTestCase() {
            if (scene.care) scene.care.destroy()
        }

        function tap(name) {
            var control = findChild(scene.care, name)
            verify(control !== null, "Missing PaperDesk Care action: " + name)
            verify(control.visible && control.enabled, "Inactive PaperDesk Care action: " + name)
            mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton)
        }

        function test_01_manifest_and_version_comparison() {
            verify(scene.care.isNewer("1.1.1", "1.1.0"))
            verify(scene.care.isNewer("1.2.0", "1.1.9"))
            verify(!scene.care.isNewer("1.1.0", "1.1.0"))
            verify(scene.care.applyManifest({
                product: "PaperDesk",
                version: "1.1.1",
                publishedAt: "2026-09-28",
                archiveUrl: "/download/paperdesk-1.1.1.zip",
                archiveSha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                releaseNotes: ["A useful change", "A repaired interaction"]
            }))
            compare(scene.care.state, "available")
            compare(scene.care.latestVersion, "1.1.1")
            verify(scene.care.releaseNotes.indexOf("A useful change") >= 0)
        }

        function test_02_install_requires_a_newer_valid_manifest() {
            scene.care.unloading()
            wait(50)
            scene.care.requestActive = false
            scene.care.state = "available"
            scene.care.latestVersion = "1.1.1"
            var installButton = findChild(scene.care, "careInstallButton")
            verify(installButton !== null)
            compare(installButton.available, true)
            scene.care.requestInstall()
            compare(scene.care.state, "queued")
            compare(scene.care.requestActive, true)
        }

        function test_03_close_emits_once() {
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = scene.care
            tap("careCloseButton")
            compare(spy.count, 1)
            spy.destroy()
        }
    }
}
