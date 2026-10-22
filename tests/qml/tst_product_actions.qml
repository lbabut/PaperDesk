import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404
    height: 1872
    property var web: null
    property var rss: null

    TestCase {
        name: "PaperWebActions"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperweb/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.web = component.createObject(scene)
            verify(scene.web !== null, component.errorString())
            waitForRendering(scene.web)
        }

        function cleanupTestCase() {
            if (scene.web) scene.web.destroy()
        }

        function tap(name) {
            var control = findChild(scene.web, name)
            verify(control !== null, "Missing PaperWeb action: " + name)
            verify(control.visible && control.enabled, "Inactive PaperWeb action: " + name)
            mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton)
        }

        function test_01_zoom_controls() {
            compare(scene.web.contentZoom, 1.0)
            tap("webZoomInButton")
            compare(scene.web.contentZoom, 1.2)
            tap("webZoomOutButton")
            compare(scene.web.contentZoom, 1.0)
        }

        function test_00_keyboard_is_contextual() {
            var address = findChild(scene.web, "webAddressInput")
            address.text = "https://example.com/a/long/address"
            scene.web.dismissKeyboard()

            // Reproduce a real user tap in the middle of a long URL. The
            // pointer event must not overwrite the deferred selectAll().
            mouseClick(address, address.width * 0.65, address.height / 2, Qt.LeftButton)
            tryCompare(address, "activeFocus", true)
            tryCompare(address, "selectedText", address.text)
            scene.web.dismissKeyboard()
            verify(!address.activeFocus)
        }

        function test_00_mobile_request_profile() {
            var headers = ({})
            var request = {
                setRequestHeader: function(name, value) { headers[name] = value }
            }
            scene.web.configurePageRequest(request)
            verify(headers["User-Agent"].indexOf("Mobile") >= 0)
            verify(headers["Accept"].indexOf("text/html") >= 0)
        }

        function test_00_first_page_load_has_one_bounded_automatic_retry() {
            var html = "<html><body><main>" + new Array(80).join("reader content ") +
                       "</main></body></html>"
            verify(scene.web.usablePageResponse(0, html))
            verify(scene.web.usablePageResponse(200, html))
            verify(!scene.web.usablePageResponse(0, ""))
            verify(scene.web.shouldRetryPageRequest(0, 0))
            verify(scene.web.shouldRetryPageRequest(503, 0))
            verify(scene.web.shouldRetryPageRequest(429, 0))
            verify(!scene.web.shouldRetryPageRequest(404, 0))
            verify(!scene.web.shouldRetryPageRequest(0, 1))
            verify(findChild(scene.web, "webNavigationRetryTimer") !== null)
        }

        function test_00_download_detection_and_native_offer() {
            verify(scene.web.hasDownloadExtension("https://example.com/manual.pdf?edition=2"))
            verify(scene.web.hasDownloadExtension("https://example.com/archive.zip"))
            verify(scene.web.hasDownloadExtension("https://example.com/image.svg?download=1"))
            verify(!scene.web.hasDownloadExtension("https://example.com/article"))
            var attachment = {
                getResponseHeader: function(name) {
                    if (name === "Content-Disposition")
                        return "attachment; filename=guide.epub"
                    if (name === "Content-Type")
                        return "application/epub+zip"
                    return ""
                }
            }
            verify(scene.web.responseWantsDownload(attachment, "https://example.com/get/42"))
            scene.web.navigate("https://example.com/files/manual.pdf", true)
            compare(scene.web.downloadPanel.phase, "offered")
            verify(scene.web.downloadPanel.message.indexOf("64 MB")>=0)
            mouseClick(findChild(scene.web,"webDownloadCancelButton"),30,30,Qt.LeftButton)
            compare(scene.web.downloadPanel.phase,"idle")
            scene.web.navigate("https://example.com/archive.zip",true)
            compare(scene.web.pageTitle,"Download unavailable")
            compare(scene.web.loading, false)
        }

        function test_00_last_successful_http_address_is_remembered() {
            verify(!scene.web.rememberLastAddress("gopher://example.invalid"))
            verify(scene.web.rememberLastAddress("example.com/remember-me"))
            verify(scene.web.restoreLastAddress())
            compare(scene.web.currentUrl, "https://example.com/remember-me")
            scene.web.abortAll()
        }

        function test_00_mobile_reader_discards_site_columns() {
            var html = "<html><head><title>Columns</title><style>.layout{display:grid;grid-template-columns:1fr 1fr}</style></head>" +
                       "<body><div class='layout'><section>First</section><section>Second</section></div></body></html>"
            var clean = scene.web.sanitizeHtml(html, "https://example.com/", ".external{columns:3}")
            verify(clean.indexOf(".layout{display:grid") < 0)
            verify(clean.indexOf(".external{columns:3}") < 0)
            verify(clean.indexOf("column-count:1!important") >= 0)
            verify(clean.indexOf("grid-template-columns:1fr!important") >= 0)
        }

        function test_00_repeated_headline_links_become_a_clean_story_list() {
            var html = "<html><body><main class='app-container'><div class='header'>Menu Logowanie</div>" +
                       "<a href='https://wiadomosci.wp.pl/one' class='wp-teaser-inline'><img alt='photo'><h3 class='wp-title'><span>Pierwsza ważna</span> wiadomość dnia</h3></a>" +
                       "<a class='wp-teaser-tile' href='https://wiadomosci.wp.pl/two'><h3 class='wp-title'>Druga bardzo ważna wiadomość</h3></a>" +
                       "<a href='/three' class='wp-teaser-inline'><h3 class='wp-title'>Trzecia wiadomość z kraju</h3></a>" +
                       "<a href='/four'><h2>Czwarta wiadomość ze świata</h2></a></main></body></html>"
            var clean = scene.web.sanitizeHtml(html, "https://www.wp.pl/", "")
            verify(clean.indexOf("paper-reader-head") >= 0)
            verify(clean.indexOf("paper-story") >= 0)
            verify(clean.indexOf("Pierwsza ważna wiadomość dnia") >= 0)
            verify(clean.indexOf("https://www.wp.pl/three") >= 0)
            verify(clean.indexOf("Menu Logowanie") < 0)
            verify(clean.indexOf("[image") < 0)
        }

        function test_00_story_images_can_be_separate_links_and_lazy_loaded() {
            var html = "<html><head><title>Pictures</title></head><body>" +
                       "<a href='/one'><h2>First useful headline</h2></a>" +
                       "<a href='/one'><img data-src='/images/one.jpg'></a>" +
                       "<a href='/two'><h2>Second useful headline</h2></a>" +
                       "<a href='/two'><img srcset='/images/two.jpg 1x, /images/two-large.jpg 2x'></a>" +
                       "<a href='/three'><h2>Third useful headline</h2></a>" +
                       "<a href='/three'><img src='/images/three.jpg'></a>" +
                       "<a href='/four'><h2>Fourth useful headline</h2></a>" +
                       "<a href='/four'><img data-original='/images/four.jpg'></a></body></html>"
            scene.web.mobileMode = true
            scene.web.showPictures = true
            var rendered = scene.web.sanitizeHtml(html, "https://pictures.example/", "")
            verify(rendered.indexOf("pictures.example%2Fimages%2Fone.jpg") >= 0, rendered)
            verify(rendered.indexOf("pictures.example%2Fimages%2Ftwo.jpg") >= 0, rendered)
            verify(rendered.indexOf("pictures.example%2Fimages%2Ffour.jpg") >= 0, rendered)
            scene.web.showPictures = false
        }

        function test_00_headings_may_wrap_the_story_link() {
            var longIntroduction = new Array(1250).join("x")
            var html = "<html><head><title>Dense cards</title></head><body>" +
                       "<article><h2><a href='/one'>One</a></h2>" + longIntroduction +
                       "<a href='/one'><img src='/one.jpg'></a></article>" +
                       "<h2><a href='/two'>Two</a></h2><a href='/two'><img src='/two.jpg'></a>" +
                       "<h2><a href='/three'>Three</a></h2><a href='/three'><img src='/three.jpg'></a>" +
                       "<h2><a href='/four'>Four</a></h2><a href='/four'><img src='/four.jpg'></a></body></html>"
            scene.web.mobileMode = true
            scene.web.showPictures = true
            var rendered = scene.web.sanitizeHtml(html, "https://dense.example/", "")
            verify(rendered.indexOf("paper-story-title") >= 0, rendered)
            verify(rendered.indexOf("dense.example%2Fone.jpg") >= 0, rendered)
            verify(rendered.indexOf("Latest items") < 0, rendered)
            scene.web.showPictures = false
        }

        function test_00_embedded_json_feed_is_rendered_generically() {
            var feed = { config: { navigation: [
                { title: "Shuffle", url: "/shuffle" },
                { title: "Get App", url: "/app" },
                { title: "Shop", url: "/shop" }
            ] }, data: { posts: [
                { title: "First dynamic post", url: "/post/one", description: "First summary", images: { image460: { url: "https://cdn.example/one.jpg" } } },
                { title: "Second dynamic post", url: "/post/two", description: "Second summary", images: { image460: { url: "https://cdn.example/two.jpg" } } }
            ] } }
            var html = "<html><head><title>Dynamic Site</title></head><body><div id='app'></div>" +
                       "<script>window.state=JSON.parse(" + JSON.stringify(JSON.stringify(feed)) + ")</script></body></html>"
            scene.web.showPictures = false
            var textOnly = scene.web.sanitizeHtml(html, "https://dynamic.example/", "")
            verify(textOnly.indexOf("First dynamic post") >= 0)
            verify(textOnly.indexOf("First summary") >= 0)
            verify(textOnly.indexOf("Shuffle") < 0)
            verify(textOnly.indexOf("<img") < 0)

            scene.web.showPictures = true
            var illustrated = scene.web.sanitizeHtml(html, "https://dynamic.example/", "")
            verify(illustrated.indexOf("images.weserv.nl") >= 0)
            verify(illustrated.indexOf("cdn.example%2Fone.jpg") >= 0)
            scene.web.showPictures = false
        }

        function test_00_desktop_mode_falls_back_for_javascript_shells() {
            var feed = { data: { posts: [
                { title: "First useful story", url: "/post/one" },
                { title: "Second useful story", url: "/post/two" }
            ] } }
            var html = "<html><head><title>Application Shell</title></head><body>" +
                       "<div id='app'>one-id,two-id</div><script>window.state=JSON.parse(" +
                       JSON.stringify(JSON.stringify(feed)) + ")</script></body></html>"
            scene.web.mobileMode = false
            verify(scene.web.shouldUseCompactReader(html))
            var rendered = scene.web.sanitizeHtml(html, "https://dynamic.example/", "")
            verify(rendered.indexOf("First useful story") >= 0)
            verify(rendered.indexOf("one-id,two-id") < 0)
            scene.web.mobileMode = true
        }

        function test_00b_desktop_pages_use_a_distinct_dense_layout() {
            scene.web.mobileMode = false
            var html = "<html><body><main style='display:grid;height:5000px'>" +
                       "<h2>Desktop story with enough visible text for a normal page</h2>" +
                       "<p>" + Array(80).join("ordinary desktop content ") + "</p>" +
                       "</main></body></html>"
            verify(scene.web.visibleDocumentText(html).length > 240)
            verify(!scene.web.shouldUseCompactReader(html))
            var rendered = scene.web.sanitizeHtml(html, "https://example.com/news", "main{display:grid}")
            verify(rendered.indexOf("display:grid;height:5000px") < 0)
            verify(rendered.indexOf("main{display:grid}") >= 0)
            verify(rendered.indexOf("font-size:14pt") >= 0)
            verify(rendered.indexOf("column-count:1!important") < 0)
            scene.web.mobileMode = true
        }

        function test_00c_article_pages_do_not_turn_into_related_link_lists() {
            var body = Array(45).join("This is the actual article body and must remain visible. ")
            var data = {
                "@context": "https://schema.org",
                "@type": "NewsArticle",
                headline: "The article the reader selected",
                description: "A useful article summary.",
                articleBody: body,
                image: { url: "https://cdn.example/article.jpg" }
            }
            var html = "<html><head><title>News</title>" +
                       "<script type='application/ld+json'>" + JSON.stringify(data) + "</script>" +
                       "</head><body><nav>" + Array(12).join("<h2><a href='/related'>Unrelated story list</a></h2>") +
                       "</nav></body></html>"
            scene.web.showPictures = true
            var rendered = scene.web.sanitizeHtml(html, "https://example.com/article", "")
            verify(rendered.indexOf("The article the reader selected") >= 0)
            verify(rendered.indexOf("actual article body") >= 0)
            verify(rendered.indexOf("Unrelated story list") < 0)
            verify(rendered.indexOf("images.weserv.nl") >= 0)
            scene.web.showPictures = false
        }

        function test_00d_script_payloads_never_become_reader_text() {
            compare(scene.web.plainTextFromHtml("<h2>Readable title<script>var MMG = {}; document.createElement('script')</script></h2>"),
                    "Readable title")
            compare(scene.web.plainTextFromHtml("<h2>Readable title</h2><script>var danglingCode = window.location"),
                    "Readable title")
            var html = "<html><body><p>Article text</p><script>const leakedCode = 'never visible';</script></body></html>"
            var rendered = scene.web.sanitizeHtml(html, "https://example.com/article", "")
            verify(rendered.indexOf("Article text") >= 0)
            verify(rendered.indexOf("leakedCode") < 0)
        }

        function test_00e_polish_text_and_entities_are_decoded() {
            compare(scene.web.plainTextFromHtml("GrbiÄ zdobyÅ duÅ¼Ä… nagrodÄ"),
                    "Grbić zdobył dużą nagrodę")
            compare(scene.web.plainTextFromHtml("&amp;#347;wiat, &lstrok;&oacute;d&amp;#378;"),
                    "świat, łódź")
            compare(scene.web.resolveUrl("/news?a=1&amp;b=2", "https://example.com/"),
                    "https://example.com/news?a=1&b=2")
        }

        function test_00_view_mode_toggle() {
            scene.web.currentUrl = "gopher://fixture.invalid"
            scene.web.mobileMode = true
            tap("webViewModeButton")
            compare(scene.web.mobileMode, false)
            tap("webViewModeButton")
            compare(scene.web.mobileMode, true)
        }

        function test_00_pictures_are_optional_and_bounded() {
            var html = "<html><body><img src='/photo.jpg' alt='Example photo'><p>Text</p></body></html>"
            scene.web.showPictures = false
            var hidden = scene.web.sanitizeHtml(html, "https://example.com/article", "")
            verify(hidden.indexOf("<img") < 0)
            verify(hidden.indexOf("[image") < 0)

            scene.web.showPictures = true
            var shown = scene.web.sanitizeHtml(html, "https://example.com/article", "")
            verify(shown.indexOf("images.weserv.nl") >= 0, shown)
            verify(shown.indexOf("example.com%2Fphoto.jpg") >= 0, shown)
            verify(shown.indexOf('width=\"560\"') >= 0)
            verify(shown.indexOf("Example photo") >= 0)

            scene.web.currentUrl = "gopher://fixture.invalid"
            tap("webPicturesButton")
            compare(scene.web.showPictures, false)
        }

        function test_02_go_rejects_unsupported_scheme_without_network() {
            var address = findChild(scene.web, "webAddressInput")
            address.text = "gopher://example.invalid"
            tap("webGoButton")
            compare(scene.web.loading, false)
        }

        function test_03_close_emits_once() {
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = scene.web
            tap("webCloseButton")
            compare(spy.count, 1)
            spy.destroy()
        }

        function test_04_stop_aborts_an_active_request() {
            var aborted = false
            scene.web.request = { abort: function() { aborted = true } }
            scene.web.loading = true
            tap("webGoButton")
            verify(aborted)
            compare(scene.web.loading, false)
        }

        function test_05_remaining_navigation_targets_exist() {
            var back = findChild(scene.web, "webBackButton")
            var reload = findChild(scene.web, "webReloadButton")
            var address = findChild(scene.web, "webAddressInput")
            verify(back !== null)
            verify(reload !== null)
            verify(findChild(scene.web, "webHomeButton") === null)
            compare(back.label, "")
            compare(back.iconName, "back")
            compare(reload.label, "")
            compare(reload.iconName, "reload")
            var backIcon = findChild(back, "webBackButtonVectorIcon")
            var reloadIcon = findChild(reload, "webReloadButtonVectorIcon")
            verify(backIcon !== null && backIcon.visible)
            verify(reloadIcon !== null && reloadIcon.visible)
            compare(backIcon.width, reloadIcon.width)
            compare(backIcon.height, reloadIcon.height)
            compare(backIcon.x, reloadIcon.x)
            compare(backIcon.y, reloadIcon.y)
            var backPosition = back.mapToItem(scene.web, 0, 0)
            var reloadPosition = reload.mapToItem(scene.web, 0, 0)
            var addressPosition = address.mapToItem(scene.web, 0, 0)
            verify(backPosition.x < reloadPosition.x)
            verify(reloadPosition.x < addressPosition.x)
            verify(Math.abs(backPosition.y - addressPosition.y) < 12)
        }
    }

    TestCase {
        name: "PaperRssActions"
        when: windowShown

        function initTestCase() {
            var component = Qt.createComponent("../../product/payload/apps/paperrss/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            scene.rss = component.createObject(scene)
            verify(scene.rss !== null, component.errorString())
            scene.rss.abortRequests()
            scene.rss.articles = [{
                id: "action-test", title: "Action test", source: "Tests",
                date: Date.now(), link: "https://example.invalid/article",
                summary: "Fixture", content: "<p>Fixture article body.</p>", fullText: true,
                feedUrl: "fixture"
            }]
            scene.rss.rebuildArticles()
            waitForRendering(scene.rss)
        }

        function cleanupTestCase() {
            if (scene.rss) scene.rss.destroy()
        }

        function tap(name) {
            var control = findChild(scene.rss, name)
            verify(control !== null, "Missing PaperRSS action: " + name)
            verify(control.visible && control.enabled, "Inactive PaperRSS action: " + name)
            mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton)
        }

        function test_00_internal_and_local_links_cannot_replace_an_article() {
            var articleUrl = "https://www.sciencedaily.com/releases/2026/09/story.htm"
            compare(scene.rss.resolveHttpUrl("#main", articleUrl), "")
            compare(scene.rss.resolveHttpUrl("qrc:/IQQJGFMQIG/ui/main.qml", articleUrl), "")
            compare(scene.rss.resolveHttpUrl("/news/next.htm", articleUrl),
                    "https://www.sciencedaily.com/news/next.htm")

            var cleaned = scene.rss.sanitizeArticle(
                "<p><a href='#main'>Skip</a><a href=qrc:/bad.qml>Bad</a>" +
                "<a href='/news/next.htm'>Next</a></p>", articleUrl)
            verify(cleaned.indexOf("#main") < 0)
            verify(cleaned.indexOf("qrc:") < 0)
            verify(cleaned.indexOf("https://www.sciencedaily.com/news/next.htm") >= 0)

            var original = scene.rss.articles
            scene.rss.articles = [{
                id: articleUrl, title: "Corrupt cache", source: "Tests", date: Date.now(),
                link: "#", summary: "import QtQuick 2.15 Rectangle {",
                content: "import QtQuick 2.15\nimport net.asivery.ApploadUtils\nRectangle {",
                feedUrl: "fixture"
            }]
            verify(scene.rss.repairUnsafeCachedArticles())
            compare(scene.rss.articles[0].link, articleUrl)
            compare(scene.rss.articles[0].content, "")
            verify(scene.rss.articles[0].summary.indexOf("repaired") >= 0)
            scene.rss.articles = original
        }

        function test_00b_completed_full_text_response_updates_the_reader() {
            var original = scene.rss.articles
            var originalCurrent = scene.rss.currentArticle
            var articleUrl = "https://www.sciencedaily.com/releases/2026/09/story.htm"
            scene.rss.articles = [{
                id: articleUrl, title: "Fetched article", source: "Tests", date: Date.now(),
                link: articleUrl, summary: "Old summary", content: "", feedUrl: "fixture"
            }]
            scene.rss.currentArticle = scene.rss.articles[0]
            verify(scene.rss.applyFullArticleResponse(
                "<html><body><article><h1>Fetched article</h1><p>Fresh full text body.</p></article></body></html>",
                articleUrl, articleUrl, "Fetched article", false))
            verify(scene.rss.currentArticle.content.indexOf("Fresh full text body") >= 0)
            verify(scene.rss.currentArticle.content.indexOf("<h1>Fetched article</h1>") < 0)
            var responseReader = findChild(scene.rss, "readerText")
            verify(responseReader !== null)
            verify(responseReader.text.indexOf("<h1>") < 0)
            verify(scene.rss.articles[0].summary.indexOf("Fresh full text body") >= 0)
            verify(scene.rss.currentArticle.fullText)
            scene.rss.articles = original
            scene.rss.currentArticle = originalCurrent
        }

        function test_00c_duplicate_feed_title_and_status_zero_https_are_handled() {
            var title = "Sharks can hear nearly 250 feet away"
            var duplicated = "<p><strong>" + title + "</strong></p><p>Article body.</p>"
            var cleaned = scene.rss.stripDuplicateLeadingTitle(duplicated, title)
            verify(cleaned.indexOf("<strong>") < 0)
            verify(cleaned.indexOf("Article body") >= 0)

            var different = "<p><strong>A useful introduction</strong></p><p>Article body.</p>"
            compare(scene.rss.stripDuplicateLeadingTitle(different, title), different)

            var original = scene.rss.articles
            scene.rss.articles = [{
                id: "deduplicated-reader", title: title, source: "Tests", date: Date.now(),
                link: "", summary: "Article body", content: duplicated,
                fullText: true, feedUrl: "fixture"
            }]
            scene.rss.openArticle(0)
            var reader = findChild(scene.rss, "readerText")
            verify(reader !== null)
            verify(reader.text.indexOf(title) < 0)
            verify(reader.text.indexOf("Article body") >= 0)
            scene.rss.articles = original

            var html = "<html><body><article><p>" + new Array(80).join("full text ") +
                       "</p></article></body></html>"
            verify(scene.rss.usableFullTextResponse(0, html))
            verify(scene.rss.usableFullTextResponse(200, html))
            verify(!scene.rss.usableFullTextResponse(0, ""))
            verify(!scene.rss.usableFullTextResponse(500, html))

            var page = "<html><body><nav>Site menu</nav><main><h1>" + title +
                "</h1><div id='story_text'><div><p>Nested lead paragraph.</p></div>" +
                "<p>" + new Array(80).join("proper article body ") + "</p></div>" +
                "<footer>Related stories</footer></main></body></html>"
            var article = scene.rss.extractArticleHtml(page)
            verify(article.indexOf("Nested lead paragraph") >= 0)
            verify(article.indexOf("proper article body") >= 0)
            verify(article.indexOf("Site menu") < 0)
            verify(article.indexOf("Related stories") < 0)
        }

        function test_00d_opening_an_uncached_article_requests_full_text_automatically() {
            var original = scene.rss.articles
            var originalCurrent = scene.rss.currentArticle
            var spy = Qt.createQmlObject(
                'import QtTest 1.3; SignalSpy { signalName: "fullTextRequested" }', scene)
            spy.target = scene.rss
            scene.rss.articles = [{
                id: "auto-full-text", title: "Automatic full text", source: "Tests",
                date: Date.now(), link: "https://example.invalid/auto-full-text",
                summary: "Feed copy", content: "<p>Feed copy.</p>", fullText: false,
                feedUrl: "fixture"
            }]
            scene.rss.openArticle(0)
            tryCompare(spy, "count", 1, 1000)
            compare(spy.signalArguments[0][0], "https://example.invalid/auto-full-text")
            scene.rss.abortRequests()

            spy.clear()
            scene.rss.articles[0].fullText = true
            scene.rss.openArticle(0)
            wait(100)
            compare(spy.count, 0)
            compare(scene.rss.fullTextLoading, false)

            scene.rss.abortRequests()
            scene.rss.articles = original
            scene.rss.currentArticle = originalCurrent
            scene.rss.rebuildArticles()
            scene.rss.view = "list"
            spy.destroy()
        }

        function test_01_reader_actions() {
            scene.rss.openArticle(0)
            compare(scene.rss.view, "reader")
            verify(findChild(scene.rss, "rssFavouriteButton") === null)
            tap("rssBackButton")
            compare(scene.rss.view, "list")
        }

        function test_01b_long_article_title_keeps_every_reader_action_on_screen() {
            scene.rss.articles = [{
                id: "long-title-test",
                title: new Array(40).join("A very long article title "),
                source: "Tests", date: Date.now(),
                link: "https://example.invalid/long-title",
                summary: "Fixture", content: "<p>Fixture article body.</p>",
                fullText: true, feedUrl: "fixture"
            }]
            scene.rss.openArticle(0)
            waitForRendering(scene.rss)

            var names = ["rssBackButton", "rssReaderCloseButton"]
            for (var i = 0; i < names.length; ++i) {
                var control = findChild(scene.rss, names[i])
                verify(control !== null, "Missing reader action: " + names[i])
                var position = control.mapToItem(scene.rss, 0, 0)
                verify(position.x >= 0, names[i] + " starts outside the screen")
                verify(position.x + control.width <= scene.rss.width,
                       names[i] + " ends outside the screen at " +
                       (position.x + control.width))
            }
        }

        function test_02_filter_and_add_cancel() {
            scene.rss.view = "list"
            scene.rss.selectedFeedUrl = "fixture"
            tap("rssAllArticlesButton")
            compare(scene.rss.selectedFeedUrl, "")
            tap("rssAddFeedViewButton")
            compare(scene.rss.view, "add")
            tap("rssCancelAddButton")
            compare(scene.rss.view, "list")
        }

        function test_03_add_and_delete_temporary_feed() {
            scene.rss.view = "add"
            var before = scene.rss.feedCountForTest()
            var name = findChild(scene.rss, "rssFeedNameInput")
            var url = findChild(scene.rss, "rssFeedUrlInput")
            name.text = "PaperDesk automated test"
            url.text = "https://example.invalid/paperdesk-test.xml"
            tap("rssAddButton")
            compare(scene.rss.view, "list")
            compare(scene.rss.feedCountForTest(), before + 1)
            scene.rss.revealFeedForTest(before)
            wait(50)
            var deleteButton = findChild(scene.rss, "rssDeleteFeedButton_" + before)
            verify(deleteButton !== null)
            mouseClick(deleteButton, deleteButton.width / 2, deleteButton.height / 2, Qt.LeftButton)
            compare(scene.rss.feedCountForTest(), before + 1)
            compare(deleteButton.label, "Confirm")
            mouseClick(deleteButton, deleteButton.width / 2, deleteButton.height / 2, Qt.LeftButton)
            compare(scene.rss.feedCountForTest(), before)
        }

        function test_04_close_emits_once() {
            scene.rss.view = "list"
            var spy = Qt.createQmlObject('import QtTest 1.3; SignalSpy { signalName: "close" }', scene)
            spy.target = scene.rss
            tap("rssCloseButton")
            compare(spy.count, 1)
            scene.rss.openArticle(0)
            compare(scene.rss.view, "reader")
            tap("rssReaderCloseButton")
            compare(spy.count, 2)
            spy.destroy()
        }

        function test_05_refresh_target_exists() {
            verify(findChild(scene.rss, "rssRefreshButton") !== null)
        }

        function test_06_oversized_feed_is_bounded() {
            var body = ""
            for (var word = 0; word < 400; ++word)
                body += "bounded parser payload "
            var xml = "<rss><channel>"
            for (var index = 0; index < 160; ++index)
                xml += "<item><title>Stress " + index + "</title><link>https://example.com/" + index + "</link><description><![CDATA[<p>" + body + "</p>]]></description></item>"
            xml += "</channel></rss>"
            var started = Date.now()
            var parsed = scene.rss.parseFeed(xml, "Stress", "fixture")
            compare(parsed.length, scene.rss.feedItemLimit)
            verify(parsed[0].content.length <= scene.rss.feedBodyLimit + 32)
            verify(Date.now() - started < 2000, "Oversized feed parser blocked the UI test thread")
        }
    }
}
