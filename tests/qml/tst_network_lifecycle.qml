import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404; height: 1872
    TestCase {
        name: "NetworkLifecycle"
        when: windowShown
        property var app: null
        property var issued: []

        function makeRequest() {
            var xhr = {readyState: 0, status: 0, statusText: "", responseText: "",
                responseURL: "", onreadystatechange: null, aborted: false,
                open: function(method, url) { this.url = url },
                setRequestHeader: function() {}, getResponseHeader: function() { return "" },
                send: function() {},
                abort: function() { this.aborted = true; this.readyState = 4; if (this.onreadystatechange) this.onreadystatechange() }}
            issued.push(xhr)
            return xhr
        }
        function create(name, options) {
            issued = []
            var component = Qt.createComponent("../../product/payload/apps/" + name + "/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            var properties = options || {}
            properties.requestFactory = makeRequest
            app = component.createObject(scene, properties)
            verify(app !== null, component.errorString())
            waitForRendering(app)
        }
        function complete(xhr, text, status) {
            xhr.responseText = text; xhr.status = status; xhr.readyState = 4
            if (xhr.onreadystatechange) xhr.onreadystatechange()
        }
        function cleanup() {
            if (app) { app.unloading(); app.destroy(); app = null }
        }
        function test_web_abort_is_silent_and_old_callback_cannot_replace_new_page() {
            create("paperweb")
            app.navigate("https://first.example/", true)
            var old = issued[issued.length - 1], late = old.onreadystatechange
            app.navigate("https://second.example/", true)
            old.status = 200; old.readyState = 4
            old.responseText = "<html><body>Outdated document</body></html>"
            late()
            compare(app.currentUrl, "https://second.example/")
            verify(old.aborted)
            compare(app.loading, true)
            app.abortAll()
            compare(app.request, null)
            verify(!findChild(app, "webNavigationRetryTimer").running)
        }
        function test_web_stalled_page_times_out() {
            create("paperweb", {networkTimeoutMs: 60})
            app.navigate("https://stalled.example/", true)
            var request = issued[issued.length - 1]
            tryCompare(app, "loading", false, 1000)
            verify(request.aborted)
            compare(app.request, null)
        }
        function test_web_missing_css_does_not_block_rendering() {
            create("paperweb", {stylesheetTimeoutMs: 60})
            app.abortAll()
            app.mobileMode = false
            var rendered = 0
            app.fetchStylesheets("<html><head><link rel='stylesheet' href='/slow.css'></head><body>Readable page</body></html>",
                                 "https://example.com/", function(css) { rendered++ })
            var request = issued[issued.length - 1]
            tryVerify(function() { return rendered === 1 }, 1000)
            verify(request.aborted)
            compare(app.styleRequests.length, 0)
            wait(100)
            compare(rendered, 1)
        }
        function test_rss_cancelled_refresh_cannot_restart_its_queue() {
            create("paperrss")
            app.abortRequests()
            app.refreshFeeds = [{name: "Old", url: "https://old.example/feed"}]
            app.refreshQueueIndex = 0; app.loading = true
            app.fetchNextFeed()
            var old = issued[issued.length - 1], late = old.onreadystatechange
            app.abortRequests()
            var count = issued.length
            old.readyState = 4; old.status = 500
            late()
            wait(60)
            compare(issued.length, count)
            compare(app.refreshFailures, 0)
            compare(app.loading, false)
        }
        function test_rss_stalled_feed_is_skipped_and_request_is_released() {
            create("paperrss", {networkTimeoutMs: 60})
            app.abortRequests()
            app.refreshFeeds = [{name: "Slow", url: "https://slow.example/feed"}]
            app.refreshQueueIndex = 0; app.refreshFailures = 0; app.loading = true
            app.fetchNextFeed()
            var xhr = issued[issued.length - 1]
            tryCompare(app, "loading", false, 1000)
            compare(app.refreshFailures, 1)
            compare(app.requests.length, 0)
            verify(xhr.aborted)
        }
        function test_rss_feed_completion_keeps_the_active_article_request() {
            create("paperrss")
            app.abortRequests()
            var article = {id: "article", title: "Story", link: "https://article.example/story",
                content: "<p>Feed copy.</p>", summary: "Feed copy", date: 0, source: "Fixture", feedUrl: "fixture"}
            app.articles = [article]; app.currentArticle = article
            app.refreshFeeds = [{name: "Feed", url: "https://feed.example/rss"}]
            app.refreshQueueIndex = 0; app.loading = true
            app.fetchNextFeed()
            var feed = issued[issued.length - 1]
            app.fetchFullArticle()
            var full = issued[issued.length - 1]
            complete(feed, "<rss><channel></channel></rss>", 200)
            tryCompare(app, "loading", false)
            verify(app.requests.indexOf(full) >= 0, "Feed completion must not orphan the active reader download")
            complete(full, "<html><body><article><p>" + new Array(30).join("Full article text. ") + "</p></article></body></html>", 200)
            compare(app.currentArticle.fullText, true)
            compare(app.fullTextLoading, false)
            compare(app.requests.length, 0)
        }
        function test_care_rejects_invalid_manifest_and_ignores_stale_status() {
            create("papercare")
            verify(!app.applyManifest({product: "PaperDesk", version: "wat", archiveUrl: "file:///tmp/a", archiveSha256: "bad"}))
            app.activeRequestId = "new-job"; app.requestActive = true; app.state = "queued"
            verify(!app.applyInstallStatus({requestId: "old-job", state: "success", message: "Old success"}))
            compare(app.requestActive, true)
            verify(app.applyInstallStatus({requestId: "new-job", state: "success", message: "Done"}))
            compare(app.state, "success")
            compare(app.requestActive, false)
        }
        function test_care_stalled_check_and_unloading_cannot_leave_live_callbacks() {
            create("papercare", {networkTimeoutMs: 60})
            var xhr = issued[issued.length - 1], late = xhr.onreadystatechange
            tryCompare(app, "state", "offline", 1000)
            verify(xhr.aborted)
            app.unloading()
            xhr.status = 200; xhr.readyState = 4; xhr.responseText = "{}"
            late()
            compare(app.state, "offline")
        }
    }
}
