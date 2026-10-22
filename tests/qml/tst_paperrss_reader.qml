import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404
    height: 1872
    property var app: null

    TestCase {
        name: "PaperRssReaderGestures"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperrss/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.app = component.createObject(scene)
            verify(scene.app !== null, component.errorString())

            var paragraphs = ""
            for (var i = 0; i < 100; ++i)
                paragraphs += "<p><a href='https://example.com/" + i + "'>Linked full-text paragraph " + i + "</a> with enough words to wrap across the reader.</p>"
            scene.app.articles = [{
                id: "gesture-test",
                title: "Full text gesture test",
                source: "Test",
                date: Date.now(),
                link: "https://example.com/article",
                summary: "Test",
                content: paragraphs,
                fullText: true,
                feedUrl: "test"
            }]
            scene.app.openArticle(0)
            waitForRendering(scene.app)
        }

        function cleanupTestCase() {
            if (scene.app) scene.app.destroy()
        }

        function test_full_text_scrolls_even_when_links_cover_content() {
            var touchArea = findChild(scene.app, "readerTouch")
            var flick = findChild(scene.app, "readerFlick")
            verify(touchArea !== null)
            verify(flick !== null)
            verify(flick.contentHeight > flick.height)
            compare(flick.contentY, 0)

            var touch = touchEvent(touchArea)
            touch.press(0, touchArea, touchArea.width / 2, touchArea.height * 0.75).commit()
            touch.move(0, touchArea, touchArea.width / 2, touchArea.height * 0.55).commit()
            touch.move(0, touchArea, touchArea.width / 2, touchArea.height * 0.30).commit()
            touch.release(0, touchArea, touchArea.width / 2, touchArea.height * 0.30).commit()

            verify(flick.contentY > 100, "Full-text touch drag must change contentY")
        }
    }
}
