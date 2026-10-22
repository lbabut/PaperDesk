import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    focus: true

    signal close
    signal fullTextRequested(string url)

    property string view: "list"
    property string selectedFeedUrl: ""
    property var articles: []
    property var requests: []
    property var requestFactory: function() { return new XMLHttpRequest() }
    property int networkTimeoutMs: 25000
    property int refreshGeneration: 0
    property var feedRequest: null
    property var readIds: []
    property var currentArticle: ({})
    property real readerZoom: 1.0
    property real pendingZoom: 1.0
    property int refreshQueueIndex: 0
    property int refreshSuccesses: 0
    property int refreshFailures: 0
    property var refreshFeeds: []
    property var pendingArticles: []
    readonly property int feedItemLimit: 12
    readonly property int feedBodyLimit: 12000
    property bool loading: false
    property bool fullTextLoading: false
    property var fullTextRequest: null
    property bool disposed: false
    property bool e2eScrollLogged: false
    property real keyboardInset: Qt.inputMethod.visible
        ? Math.max(height * 0.38, Qt.inputMethod.keyboardRectangle.height) : 0

    Timer {
        id: feedTimeout
        interval: root.networkTimeoutMs
        onTriggered: root.finishFeed(root.feedRequest, root.refreshGeneration, null, true)
    }
    Timer {
        id: fullTextTimeout
        interval: root.networkTimeoutMs
        onTriggered: {
            var pending = root.fullTextRequest
            root.fullTextRequest = null
            root.fullTextLoading = false
            if (pending) {
                root.forgetRequest(pending)
                pending.onreadystatechange = null
                pending.abort()
                readerStatus.text = "Connection timed out · feed copy shown"
            }
        }
    }

    component ActionButton: Rectangle {
        id: button
        property string label: "Action"
        property bool primary: false
        signal triggered

        implicitWidth: 176
        implicitHeight: 76
        radius: 8
        color: actionTap.pressed || primary ? "black" : "white"
        border.color: "black"
        border.width: 2
        Text {
            anchors.fill: parent
            anchors.margins: 10
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: parent.label
            color: actionTap.pressed || parent.primary ? "white" : "black"
            font.pointSize: 16
            font.bold: true
        }
        TapHandler {
            id: actionTap
            onTapped: parent.triggered()
        }
    }

    Settings {
        id: store
        category: "PaperRSS"
        property string feedsJson: ""
        property string articlesJson: "[]"
        property string readJson: "[]"
        property real savedZoom: 1.0
        property bool scienceStarterAdded: false
    }
    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool autostart: false
        property int scenarioVersion: 0
        property bool rssLongArticle: false
        property bool rssAutoFullText: false
        property string rssAutoFullTextUrl: ""
        property string rssAutoFullTextTitle: ""
        property bool rssStressParser: false
        property bool rssTraceScroll: false
        property bool traceTouches: false
    }

    ListModel { id: feedsModel }
    ListModel { id: articlesModel }

    function unloading() {
        disposed = true
        abortRequests()
        saveState()
        Qt.inputMethod.hide()
    }

    function gainedFocus() {
        if (view === "add")
            feedUrl.forceActiveFocus()
    }

    function defaultFeeds() {
        return [
            { name: "BBC World", url: "https://feeds.bbci.co.uk/news/world/rss.xml" },
            { name: "BBC Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml" }
        ]
    }

    function scienceStarterFeeds() {
        return [
            { name: "Physics World", url: "https://physicsworld.com/feed/" },
            { name: "Quanta Magazine", url: "https://www.quantamagazine.org/feed/" },
            { name: "MIT Technology Review", url: "https://www.technologyreview.com/feed/" },
            { name: "ScienceDaily", url: "https://www.sciencedaily.com/rss/top/science.xml" },
            { name: "Nature Physics", url: "https://www.nature.com/nphys.rss" }
        ]
    }

    function safeParse(value, fallback) {
        try {
            var parsed = JSON.parse(value)
            return parsed === null ? fallback : parsed
        } catch (error) {
            return fallback
        }
    }

    function loadState() {
        var feeds = safeParse(store.feedsJson, [])
        if (!feeds || feeds.length === 0)
            feeds = defaultFeeds()
        // Migrate the initial PAP feed, whose HTTPS endpoint is rejected by
        // Qt networking on this OS build, to a verified endpoint.
        for (var migrationIndex = 0; migrationIndex < feeds.length; ++migrationIndex) {
            if (feeds[migrationIndex].url === "https://samorzad.pap.pl/rss.xml")
                feeds[migrationIndex] = defaultFeeds()[1]
        }
        if (!store.scienceStarterAdded) {
            var starters = scienceStarterFeeds()
            for (var starterIndex = 0; starterIndex < starters.length; ++starterIndex) {
                var alreadyPresent = false
                for (var feedIndex = 0; feedIndex < feeds.length; ++feedIndex) {
                    if (feeds[feedIndex].url === starters[starterIndex].url) {
                        alreadyPresent = true
                        break
                    }
                }
                if (!alreadyPresent)
                    feeds.push(starters[starterIndex])
            }
            store.feedsJson = JSON.stringify(feeds)
            store.scienceStarterAdded = true
        }
        feedsModel.clear()
        for (var i = 0; i < feeds.length; ++i)
            feedsModel.append({ name: String(feeds[i].name), url: String(feeds[i].url) })
        articles = safeParse(store.articlesJson, [])
        if (repairUnsafeCachedArticles()) {
            store.articlesJson = JSON.stringify(articles.slice(0, 160))
            console.log("PaperRSS repaired unsafe cached articles")
        }
        readIds = safeParse(store.readJson, [])
        readerZoom = Math.max(1.0, Math.min(2.4, store.savedZoom || 1.0))
        rebuildArticles()
    }

    function saveState() {
        if (e2eScenarioActive() && e2eSettings.rssLongArticle)
            return
        var feeds = []
        for (var i = 0; i < feedsModel.count; ++i)
            feeds.push({ name: feedsModel.get(i).name, url: feedsModel.get(i).url })
        store.feedsJson = JSON.stringify(feeds)
        store.articlesJson = JSON.stringify(articles.slice(0, 160))
        store.readJson = JSON.stringify(readIds.slice(-1000))
        store.savedZoom = readerZoom
    }

    function e2eScenarioActive() {
        return e2eSettings.traceTouches && e2eSettings.scenarioVersion === 20260927
    }

    function contains(array, value) {
        return array.indexOf(value) !== -1
    }

    function htmlDecode(value) {
        return String(value || "")
            .replace(/&nbsp;/gi, " ")
            .replace(/&amp;/gi, "&")
            .replace(/&lt;/gi, "<")
            .replace(/&gt;/gi, ">")
            .replace(/&quot;/gi, "\"")
            .replace(/&#39;|&apos;/gi, "'")
            .replace(/&#(\d+);/g, function(all, number) {
                return String.fromCharCode(parseInt(number))
            })
    }

    function plainText(value) {
        var text = String(value || "")
        text = text.replace(/<br\s*\/?>/gi, "\n")
        text = text.replace(/<\/p\s*>/gi, "\n\n")
        text = text.replace(/<[^>]+>/g, " ")
        text = htmlDecode(text)
        return text.replace(/[ \t]+/g, " ").replace(/\n\s+/g, "\n").trim()
    }

    function normalizedTitle(value) {
        return plainText(value).toLowerCase()
            .replace(/[\u2018\u2019]/g, "'")
            .replace(/[\u2013\u2014]/g, "-")
            .replace(/\s+/g, " ")
            .trim()
    }

    function stripDuplicateLeadingTitle(value, articleTitle) {
        var html = String(value || "")
        var wanted = normalizedTitle(articleTitle)
        if (!html || !wanted)
            return html

        // Feeds and article pages often repeat the title as their first h1-h6
        // or as a bold paragraph. Remove it only when no readable content
        // precedes it and its text is the same as PaperRSS's own heading.
        var candidates = [
            /<h[1-6]\b[^>]*>[\s\S]*?<\/h[1-6]\s*>/i,
            /<p\b[^>]*>[\s\S]*?<\/p\s*>/i
        ]
        for (var i = 0; i < candidates.length; ++i) {
            var match = candidates[i].exec(html)
            if (!match || match.index > 1200)
                continue
            if (plainText(html.substring(0, match.index)).length > 0)
                continue
            if (normalizedTitle(match[0]) === wanted)
                return html.substring(0, match.index) + html.substring(match.index + match[0].length)
        }
        return html
    }

    function usableFullTextResponse(status, value) {
        var body = String(value || "")
        if (body.length < 200 || looksLikeApplicationSource(body))
            return false
        if (status >= 200 && status < 400)
            return true
        // Qt 5 on the reMarkable occasionally exposes a completed HTTPS
        // response as status 0. A substantial HTML body is stronger evidence
        // than that missing status value; empty TLS/network failures stay out.
        return status === 0 && /<(?:!doctype|html|body|article|main|p)\b/i.test(body)
    }

    function balancedElementContents(source, openingExpression) {
        var html = String(source || "")
        openingExpression.lastIndex = 0
        var opening = openingExpression.exec(html)
        if (!opening)
            return ""
        var nameMatch = /^<([a-z0-9:-]+)/i.exec(opening[0])
        if (!nameMatch)
            return ""
        var tagName = regexEscape(nameMatch[1])
        var tokenExpression = new RegExp("<\\/?" + tagName + "\\b[^>]*>", "gi")
        tokenExpression.lastIndex = opening.index
        var depth = 0
        var token
        while ((token = tokenExpression.exec(html)) !== null) {
            if (/^<\//.test(token[0])) {
                depth -= 1
                if (depth === 0)
                    return html.substring(opening.index + opening[0].length, token.index)
            } else if (!/\/\s*>$/.test(token[0])) {
                depth += 1
            }
        }
        return ""
    }

    function extractArticleHtml(value) {
        var html = String(value || "")
        var content = balancedElementContents(html,
            /<(?:article|main|section|div)\b[^>]*(?:id|class)\s*=\s*["'][^"']*(?:story[_-]?text|article[_-]?(?:body|content)|entry[_-]?content|post[_-]?content|story[_-]?content)[^"']*["'][^>]*>/i)
        if (plainText(content).length >= 120)
            return content
        content = balancedElementContents(html, /<article\b[^>]*>/i)
        if (plainText(content).length >= 120)
            return content
        content = balancedElementContents(html, /<main\b[^>]*>/i)
        if (plainText(content).length >= 120)
            return content
        content = balancedElementContents(html, /<body\b[^>]*>/i)
        return content || html
    }

    function escapeHtml(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/\"/g, "&quot;")
    }

    function resolveHttpUrl(value, baseUrl) {
        var link = htmlDecode(String(value || "").trim())
        if (!link || link.charAt(0) === "#" || /^(?:javascript|data|file|qrc):/i.test(link))
            return ""
        if (/^https?:\/\//i.test(link))
            return link
        var base = String(baseUrl || "")
        var origin = /^(https?:\/\/[^\/?#]+)/i.exec(base)
        if (!origin)
            return ""
        if (/^\/\//.test(link))
            return origin[1].split(":")[0] + ":" + link
        if (link.charAt(0) === "/")
            return origin[1] + link
        var cleanBase = base.replace(/[?#].*$/, "")
        var slash = cleanBase.lastIndexOf("/")
        return cleanBase.substring(0, slash + 1) + link
    }

    function looksLikeApplicationSource(value) {
        var text = String(value || "")
        return /^\s*import\s+QtQuick\b/m.test(text) &&
            (/\bnet\.asivery\.ApploadUtils\b/.test(text) || /\bRectangle\s*\{/.test(text))
    }

    function repairUnsafeCachedArticles() {
        var repaired = false
        for (var i = 0; i < articles.length; ++i) {
            var article = articles[i]
            var safeLink = resolveHttpUrl(article.link, article.id)
            if (!safeLink)
                safeLink = resolveHttpUrl(article.id, "")
            if (article.link !== safeLink) {
                article.link = safeLink
                repaired = true
            }
            if (looksLikeApplicationSource(article.content) || looksLikeApplicationSource(article.summary)) {
                article.content = ""
                article.fullText = false
                article.summary = "Cached full text was repaired. It will download again when opened."
                repaired = true
            }
        }
        return repaired
    }

    function sanitizeArticle(value, baseUrl) {
        var html = String(value || "")
        html = html.replace(/<!--([\s\S]*?)-->/g, "")
        html = html.replace(/<(script|style|noscript|svg|canvas|video|audio|iframe|object|form)[^>]*>[\s\S]*?<\/\1\s*>/gi, "")
        html = html.replace(/<img\b[^>]*alt=[\"']([^\"']*)[\"'][^>]*>/gi, "<p>[image: $1]</p>")
        html = html.replace(/<img\b[^>]*>/gi, "")
        html = html.replace(/\s(on[a-z]+|style|class|id|src|srcset)\s*=\s*([\"'])[^\"']*\2/gi, "")
        html = html.replace(/\shref\s*=\s*([\"'])([^\"']*)\1/gi, function(all, quote, href) {
            var safeHref = resolveHttpUrl(href, baseUrl)
            return safeHref ? " href=\"" + escapeHtml(safeHref) + "\"" : ""
        })
        html = html.replace(/\shref\s*=\s*([^\s\"'<>`]+)/gi, function(all, href) {
            var safeHref = resolveHttpUrl(href, baseUrl)
            return safeHref ? " href=\"" + escapeHtml(safeHref) + "\"" : ""
        })
        html = html.replace(/<(\/?)(article|main|section|header|footer|figure|figcaption|aside|nav)(?:\s[^>]*)?>/gi, "<$1div>")
        html = html.replace(/<(\/?)(?!p\b|br\b|hr\b|h[1-6]\b|b\b|strong\b|i\b|em\b|u\b|ul\b|ol\b|li\b|pre\b|code\b|blockquote\b|a\b|div\b|span\b)[a-z0-9:-]+(?:\s[^>]*)?>/gi, "")
        return html
    }

    function regexEscape(value) {
        return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    function unwrapXml(value) {
        return String(value || "")
            .replace(/^\s*<!\[CDATA\[([\s\S]*)\]\]>\s*$/i, "$1")
            .trim()
    }

    function xmlBlocks(source, tag) {
        var escaped = regexEscape(tag)
        var expression = new RegExp("<(?:[a-z0-9_-]+:)?" + escaped + "\\b[^>]*>([\\s\\S]*?)<\\/(?:[a-z0-9_-]+:)?" + escaped + "\\s*>", "gi")
        var blocks = []
        var match
        while ((match = expression.exec(source)) !== null && blocks.length < feedItemLimit)
            blocks.push(match[1])
        return blocks
    }

    function xmlValue(source, names) {
        for (var i = 0; i < names.length; ++i) {
            var name = regexEscape(names[i])
            var expression = new RegExp("<" + name + "\\b[^>]*>([\\s\\S]*?)<\\/" + name + "\\s*>", "i")
            var match = expression.exec(source)
            if (match && unwrapXml(match[1]).length > 0)
                return unwrapXml(match[1])
            if (names[i].indexOf(":") < 0) {
                expression = new RegExp("<[a-z0-9_-]+:" + name + "\\b[^>]*>([\\s\\S]*?)<\\/[a-z0-9_-]+:" + name + "\\s*>", "i")
                match = expression.exec(source)
                if (match && unwrapXml(match[1]).length > 0)
                    return unwrapXml(match[1])
            }
        }
        return ""
    }

    function xmlLink(source) {
        var atom = /<link\b([^>]*)\/?\s*>/gi
        var match
        while ((match = atom.exec(source)) !== null) {
            var href = /\bhref\s*=\s*["']([^"']+)["']/i.exec(match[1])
            var rel = /\brel\s*=\s*["']([^"']+)["']/i.exec(match[1])
            if (href && (!rel || rel[1].toLowerCase() === "alternate"))
                return htmlDecode(href[1])
        }
        return plainText(xmlValue(source, ["link"]))
    }

    function timestamp(value) {
        var result = Date.parse(String(value || ""))
        return isNaN(result) ? Date.now() : result
    }

    function parseFeed(xmlText, feedName, feedUrl) {
        var xml = String(xmlText || "")
        if (!xml)
            return []
        var nodes = xmlBlocks(xml, "item")
        if (nodes.length === 0)
            nodes = xmlBlocks(xml, "entry")
        var parsed = []
        for (var i = 0; i < nodes.length && i < feedItemLimit; ++i) {
            var node = nodes[i]
            var title = plainText(xmlValue(node, ["title"]))
            var link = resolveHttpUrl(xmlLink(node), feedUrl)
            var body = xmlValue(node, ["content:encoded", "encoded", "content", "description", "summary"])
            if (body.length > feedBodyLimit)
                body = body.substring(0, feedBodyLimit)
            var dateText = xmlValue(node, ["pubDate", "published", "updated", "dc:date"])
            var identifier = plainText(xmlValue(node, ["guid", "id"])) || link || (feedUrl + "#" + title)
            if (!title)
                title = "Untitled"
            parsed.push({
                id: identifier,
                title: title,
                link: link,
                content: sanitizeArticle(body, link || feedUrl),
                fullText: false,
                summary: plainText(body).substring(0, 340),
                date: timestamp(dateText),
                source: feedName,
                feedUrl: feedUrl,
                cachedAt: Date.now()
            })
        }
        return parsed
    }

    function mergeArticles(incoming) {
        var previousById = ({})
        for (var previousIndex = 0; previousIndex < articles.length; ++previousIndex)
            previousById[articles[previousIndex].id] = articles[previousIndex]
        var byId = ({})
        var merged = []
        for (var i = 0; i < incoming.length; ++i) {
            var previous = previousById[incoming[i].id]
            if (previous && previous.fullText) {
                incoming[i].content = previous.content
                incoming[i].summary = previous.summary
                incoming[i].fullText = true
            }
            byId[incoming[i].id] = true
            merged.push(incoming[i])
        }
        for (var j = 0; j < articles.length; ++j) {
            if (!byId[articles[j].id]) {
                byId[articles[j].id] = true
                merged.push(articles[j])
            }
        }
        merged.sort(function(a, b) { return b.date - a.date })
        articles = merged.slice(0, 160)
        rebuildArticles()
        saveState()
    }

    function rebuildArticles() {
        articlesModel.clear()
        var filtered = []
        for (var i = 0; i < articles.length; ++i) {
            if (!selectedFeedUrl || articles[i].feedUrl === selectedFeedUrl)
                filtered.push(articles[i])
        }
        filtered.sort(function(a, b) { return b.date - a.date })
        for (var j = 0; j < filtered.length; ++j) {
            var item = filtered[j]
            articlesModel.append({
                articleIndex: articles.indexOf(item),
                articleId: item.id,
                title: item.title,
                summary: item.summary,
                source: item.source,
                date: item.date,
                isRead: contains(readIds, item.id)
            })
        }
        listStatus.text = articlesModel.count + " cached articles"
    }

    function abortRequests() {
        refreshGeneration += 1
        feedTimeout.stop()
        fullTextTimeout.stop()
        feedRequest = null
        var activeRequests = requests.slice(0)
        requests = []
        loading = false
        fullTextLoading = false
        fullTextRequest = null
        for (var i = 0; i < activeRequests.length; ++i) {
            activeRequests[i].onreadystatechange = null
            try { activeRequests[i].abort() } catch (error) {}
        }
    }

    function forgetRequest(xhr) {
        var active = requests.slice(0)
        var index = active.indexOf(xhr)
        if (index >= 0)
            active.splice(index, 1)
        requests = active
    }

    function applyFullArticleResponse(html, sourceUrl, articleId, articleTitle, persist) {
        if (!currentArticle || currentArticle.id !== articleId)
            return false
        if (looksLikeApplicationSource(html)) {
            readerStatus.text = "Blocked invalid page response"
            console.log("PaperRSS blocked application source response", sourceUrl)
            return false
        }
        var extracted = extractArticleHtml(html)
        extracted = sanitizeArticle(extracted.substring(0, 600000), sourceUrl)
        extracted = stripDuplicateLeadingTitle(extracted, articleTitle)
        readerText.text = extracted
        currentArticle.content = extracted
        currentArticle.fullText = true
        for (var i = 0; i < articles.length; ++i) {
            if (articles[i].id === articleId) {
                articles[i].content = extracted
                articles[i].summary = plainText(extracted).substring(0, 340)
                articles[i].fullText = true
                break
            }
        }
        if (persist !== false)
            saveState()
        readerStatus.text = "Full text saved offline"
        console.log("PaperRSS full text ready", articleId, plainText(extracted).length)
        return true
    }

    function refreshAll() {
        abortRequests()
        refreshQueueIndex = 0
        refreshSuccesses = 0
        refreshFailures = 0
        refreshFeeds = []
        pendingArticles = []
        for (var feedIndex = 0; feedIndex < feedsModel.count; ++feedIndex) {
            var candidate = feedsModel.get(feedIndex)
            if (!selectedFeedUrl || candidate.url === selectedFeedUrl)
                refreshFeeds.push({ name: candidate.name, url: candidate.url })
        }
        loading = true
        fetchNextFeed()
    }

    function fetchNextFeed() {
        if (disposed)
            return
        if (refreshQueueIndex >= refreshFeeds.length) {
            if (pendingArticles.length > 0)
                mergeArticles(pendingArticles)
            loading = false
            listStatus.text = "Done: " + refreshSuccesses + " feeds, errors: " + refreshFailures
            // Feed requests release themselves. A reader request may have
            // started while the feed queue was running; keep its ownership.
            pendingArticles = []
            console.log("PaperRSS refresh complete", refreshSuccesses, refreshFailures)
            return
        }
        var feed = refreshFeeds[refreshQueueIndex++]
        listStatus.text = "Loading: " + feed.name
        var xhr = requestFactory()
        var owner = root
        var generation = refreshGeneration
        feedRequest = xhr
        requests.push(xhr)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (owner) owner.finishFeed(xhr, generation, feed, false)
        }
        xhr.open("GET", feed.url, true)
        feedTimeout.restart()
        xhr.send()
    }

    function finishFeed(xhr, generation, feed, timedOut) {
        if (disposed || !xhr || xhr !== feedRequest || generation !== refreshGeneration)
            return
        feedTimeout.stop()
        feedRequest = null
        forgetRequest(xhr)
        xhr.onreadystatechange = null
        var parsed = []
        if (timedOut) {
            xhr.abort()
        } else if (xhr.status >= 200 && xhr.status < 400) {
            try { parsed = parseFeed(xhr.responseText, feed.name, feed.url) } catch (error) {}
        }
        if (parsed.length) {
            pendingArticles = pendingArticles.concat(parsed)
            refreshSuccesses += 1
        } else refreshFailures += 1
        Qt.callLater(function() {
            if (!disposed && generation === refreshGeneration) fetchNextFeed()
        })
    }

    function formatDate(epoch) {
        var date = new Date(epoch)
        function pad(value) { return value < 10 ? "0" + value : String(value) }
        return pad(date.getDate()) + "." + pad(date.getMonth() + 1) + "." + date.getFullYear() +
               "  " + pad(date.getHours()) + ":" + pad(date.getMinutes())
    }

    function openArticle(index) {
        if (index < 0 || index >= articles.length)
            return
        // A previous article must not keep downloading or change this reader.
        fullTextTimeout.stop()
        if (fullTextRequest) {
            var previous = fullTextRequest
            fullTextRequest = null
            forgetRequest(previous)
            previous.onreadystatechange = null
            previous.abort()
        }
        fullTextLoading = false
        currentArticle = articles[index]
        if (!contains(readIds, currentArticle.id))
            readIds = readIds.concat([currentArticle.id])
        readerTitle.text = currentArticle.title
        readerMeta.text = currentArticle.source + "  |  " + formatDate(currentArticle.date)
        var body = stripDuplicateLeadingTitle(currentArticle.content, currentArticle.title)
        if (!body || plainText(body).length < 20)
            body = "<p>" + escapeHtml(currentArticle.summary || "No content in this feed.") + "</p>"
        readerText.text = body
        readerFlick.contentY = 0
        view = "reader"
        Qt.inputMethod.hide()
        saveState()
        rebuildArticles()
        if (currentArticle.fullText) {
            readerStatus.text = "Full text saved offline"
        } else if (resolveHttpUrl(currentArticle.link, currentArticle.id)) {
            var openedArticleId = currentArticle.id
            Qt.callLater(function() {
                if (currentArticle && currentArticle.id === openedArticleId)
                    fetchFullArticle()
            })
        } else {
            readerStatus.text = "Feed text"
        }
    }

    function fetchFullArticle(targetUrl, retryAttempt) {
        if (!targetUrl && !currentArticle.link)
            return
        var sourceUrl = resolveHttpUrl(targetUrl || currentArticle.link, currentArticle.id)
        if (!sourceUrl) {
            readerStatus.text = "Internal page link ignored"
            console.log("PaperRSS blocked non-web article link", targetUrl || currentArticle.link)
            return
        }
        if (fullTextRequest) {
            var previousRequest = fullTextRequest
            fullTextRequest = null
            forgetRequest(previousRequest)
            previousRequest.onreadystatechange = null
            try { previousRequest.abort() } catch (error) {}
        }
        fullTextLoading = true
        readerStatus.text = "Loading full text..."
        var xhr = requestFactory()
        var owner = root
        var articleId = currentArticle.id
        var articleTitle = currentArticle.title
        var attempt = retryAttempt || 0
        fullTextRequest = xhr
        requests.push(xhr)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (!owner || owner.disposed || owner.requests.indexOf(xhr) < 0)
                return
            owner.forgetRequest(xhr)
            if (owner.fullTextRequest === xhr) {
                fullTextTimeout.stop()
                owner.fullTextRequest = null
                owner.fullTextLoading = false
            }
            if (!owner.currentArticle || owner.currentArticle.id !== articleId)
                return
            var html = ""
            try { html = String(xhr.responseText || "") } catch (responseError) {}
            console.log("PaperRSS full text response", xhr.status, html.length, sourceUrl)
            if (owner.usableFullTextResponse(xhr.status, html)) {
                owner.applyFullArticleResponse(html, sourceUrl, articleId, articleTitle, true)
            } else if (attempt < 1) {
                readerStatus.text = "Retrying full text..."
                console.log("PaperRSS full text retry", xhr.status, sourceUrl)
                Qt.callLater(function() {
                    if (owner && !owner.disposed && owner.currentArticle &&
                            owner.currentArticle.id === articleId)
                        owner.fetchFullArticle(sourceUrl, attempt + 1)
                })
            } else {
                readerStatus.text = "Full text unavailable · feed copy shown"
            }
        }
        console.log("PaperRSS full text request", sourceUrl)
        fullTextRequested(sourceUrl)
        xhr.open("GET", sourceUrl, true)
        xhr.setRequestHeader("Accept", "text/html,application/xhtml+xml")
        xhr.setRequestHeader("Cache-Control", "no-cache")
        fullTextTimeout.restart()
        xhr.send()
    }

    function addFeed() {
        var name = feedName.text.trim()
        var url = feedUrl.text.trim()
        if (!name || !url) {
            addStatus.text = "Enter a feed name and address"
            return
        }
        if (!/^https?:\/\//i.test(url))
            url = "https://" + url
        if (!/^https?:\/\/[^\s/?#]+(?:[/?#]|$)/i.test(url)) {
            addStatus.text = "Enter a valid HTTP or HTTPS feed address"
            return
        }
        for (var i = 0; i < feedsModel.count; ++i) {
            if (feedsModel.get(i).url === url) {
                addStatus.text = "This feed already exists"
                return
            }
        }
        feedsModel.append({ name: name, url: url })
        feedName.text = ""
        feedUrl.text = ""
        selectedFeedUrl = url
        saveState()
        rebuildArticles()
        view = "list"
        Qt.inputMethod.hide()
    }

    function removeFeed(index) {
        if (index < 0 || index >= feedsModel.count)
            return
        var url = feedsModel.get(index).url
        feedsModel.remove(index)
        if (selectedFeedUrl === url)
            selectedFeedUrl = ""
        saveState()
        rebuildArticles()
    }

    function feedCountForTest() {
        return feedsModel.count
    }

    function revealFeedForTest(index) {
        feedsList.positionViewAtIndex(index, ListView.Center)
    }

    function settleReader() {
        var bottom = Math.max(0, readerFlick.contentHeight - readerFlick.height)
        readerFlick.contentY = Math.max(0, Math.min(bottom, readerFlick.contentY))
        readerFlick.returnToBounds()
    }

    Rectangle {
        id: listView
        anchors.fill: parent
        color: "white"
        visible: root.view === "list"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                color: "black"
                border.color: "black"
                border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Column {
                        Layout.leftMargin: 10
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "PAPERDESK  /  OFFLINE READER"
                            color: "white"
                            font.pointSize: 10
                            font.bold: true
                            font.letterSpacing: 2
                        }
                        Text {
                            text: "Reading list"
                            color: "white"
                            font.pointSize: 25
                            font.bold: true
                        }
                    }
                    ActionButton {
                        id: refreshButton
                        objectName: "rssRefreshButton"
                        label: loading ? "Stop" : "Refresh"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action", loading ? "stop refresh" : "refresh")
                            loading ? abortRequests() : refreshAll()
                        }
                    }
                    ActionButton {
                        objectName: "rssAddFeedViewButton"
                        label: "+ Add feed"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action add feed view")
                            view = "add"
                            addKeyboardTimer.restart()
                        }
                    }
                    ActionButton {
                        objectName: "rssCloseButton"
                        label: "Close"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action close")
                            root.close()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: "white"
                border.color: "black"
                border.width: 1
                Text {
                    id: listStatus
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: "Ready"
                    color: "black"
                    font.pointSize: 15
                    font.bold: true
                    font.letterSpacing: 0.5
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 360
                    Layout.fillHeight: true
                    color: "white"
                    border.color: "black"
                    border.width: 2

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            color: "black"
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                text: "SOURCES"
                                color: "white"
                                font.pointSize: 11
                                font.bold: true
                                font.letterSpacing: 2
                            }
                        }

                        ActionButton {
                            objectName: "rssAllArticlesButton"
                            label: "All articles"
                            primary: !selectedFeedUrl
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            onTriggered: {
                                console.log("PaperRSS action all articles")
                                selectedFeedUrl = ""
                                rebuildArticles()
                            }
                        }

                        ListView {
                            id: feedsList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: feedsModel
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Rectangle {
                                property bool deleteArmed: false
                                width: feedsList.width
                                height: 120
                                color: model.url === selectedFeedUrl ? "black" : "white"
                                border.color: "black"
                                border.width: 1

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: deleteFeed.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 16
                                    anchors.topMargin: 14
                                    anchors.bottomMargin: 14
                                    text: model.name
                                    color: model.url === selectedFeedUrl ? "white" : "black"
                                    wrapMode: Text.WordWrap
                                    verticalAlignment: Text.AlignVCenter
                                    font.pointSize: 15
                                    font.bold: true
                                }
                                ActionButton {
                                    id: deleteFeed
                                    objectName: "rssDeleteFeedButton_" + index
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.rightMargin: 10
                                    width: 116
                                    height: 76
                                    label: parent.deleteArmed ? "Confirm" : "Remove"
                                    onTriggered: {
                                        if (!parent.deleteArmed) {
                                            parent.deleteArmed = true
                                            deleteReset.restart()
                                            console.log("PaperRSS action confirm delete feed", model.url)
                                        } else {
                                            console.log("PaperRSS action delete feed", model.url)
                                            removeFeed(index)
                                        }
                                    }
                                }
                                Timer {
                                    id: deleteReset
                                    interval: 3000
                                    onTriggered: parent.deleteArmed = false
                                }
                                Item {
                                    anchors.left: parent.left
                                    anchors.right: deleteFeed.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    TapHandler {
                                        onTapped: {
                                            console.log("PaperRSS action select feed", model.url)
                                            selectedFeedUrl = model.url
                                            rebuildArticles()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: articleList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: articlesModel
                    spacing: 12
                    topMargin: 18
                    bottomMargin: 18
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 3000
                    maximumFlickVelocity: 1800
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn; width: 15 }

                    delegate: Rectangle {
                        x: 20
                        width: articleList.width - 40
                        height: 184
                        color: "white"
                        border.color: "black"
                        border.width: 2
                        radius: 8

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 20
                            anchors.topMargin: 22
                            width: 12
                            height: 12
                            radius: 6
                            color: model.isRead ? "white" : "black"
                            border.color: "black"
                            border.width: 2
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 52
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.top: parent.top
                            anchors.topMargin: 16
                            height: 96
                            text: model.title
                            color: "black"
                            font.pointSize: 20
                            font.bold: !model.isRead
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 52
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            text: model.source + "  |  " + formatDate(model.date)
                            color: "black"
                            font.pointSize: 15
                            font.bold: true
                            font.letterSpacing: 0.3
                            elide: Text.ElideRight
                        }
                        TapHandler {
                            onTapped: {
                                console.log("PaperRSS action open article", model.articleId)
                                openArticle(model.articleIndex)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: articlesModel.count === 0
                        width: parent.width - 80
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: loading ? "Fetching your reading list…" : "No articles here yet.\nTap Refresh to download your feeds."
                        color: "black"
                        font.pointSize: 23
                        font.bold: true
                    }
                }
            }
        }
    }

    Rectangle {
        id: readerView
        anchors.fill: parent
        color: "white"
        visible: root.view === "reader"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                color: "black"
                border.color: "black"
                border.width: 0
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    ActionButton {
                        objectName: "rssBackButton"
                        label: "← Articles"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action articles")
                            view = "list"
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Text {
                            text: "PAPERDESK  /  ARTICLE"
                            color: "white"
                            font.pointSize: 9
                            font.bold: true
                            font.letterSpacing: 2
                        }
                        Text {
                            id: readerTitle
                            width: parent.width
                            text: "Article"
                            color: "white"
                            font.pointSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }
                    ActionButton {
                        objectName: "rssReaderCloseButton"
                        label: "Close"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action close")
                            root.close()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                color: "white"
                border.color: "black"
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    Text {
                        id: readerMeta
                        Layout.fillWidth: true
                        color: "black"
                        font.pointSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        id: readerStatus
                        text: Math.round(readerZoom * 100) + "%"
                        color: "black"
                        font.pointSize: 15
                        font.bold: true
                    }
                }
            }

            Item {
                id: readerViewport
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: readerFlick
                    objectName: "readerFlick"
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, readerText.paintedHeight * root.readerZoom + 64)
                    flickableDirection: Flickable.VerticalFlick
                    interactive: false
                    pixelAligned: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn; width: 16 }

                    Text {
                        id: readerText
                        objectName: "readerText"
                        x: 100
                        y: 36
                        width: (readerFlick.width - 220) / root.readerZoom
                        scale: root.readerZoom
                        transformOrigin: Item.TopLeft
                        textFormat: Text.RichText
                        wrapMode: Text.WordWrap
                        color: "black"
                        linkColor: "black"
                        font.pointSize: 21
                        font.bold: false
                        lineHeight: 1.28
                        lineHeightMode: Text.ProportionalHeight
                    }
                }

                MultiPointTouchArea {
                    id: readerTouch
                    objectName: "readerTouch"
                    anchors.fill: parent
                    z: 20
                    minimumTouchPoints: 1
                    maximumTouchPoints: 2
                    property int activePoint: -1
                    property var pointState: ({})
                    property bool pinchActive: false
                    property bool suppressTap: false
                    property real pressX: 0
                    property real pressY: 0
                    property real startContentY: 0
                    property real pinchStartDistance: 1
                    property real pinchStartZoom: 1

                    function remember(points) {
                        for (var i = 0; i < points.length; ++i)
                            pointState[points[i].pointId] = { x: points[i].x, y: points[i].y }
                    }
                    function pointIds() { return Object.keys(pointState) }
                    function distanceBetween(first, second) {
                        var dx = first.x - second.x
                        var dy = first.y - second.y
                        return Math.sqrt(dx * dx + dy * dy)
                    }
                    function beginPinch() {
                        var ids = pointIds()
                        if (ids.length < 2)
                            return
                        pinchActive = true
                        suppressTap = true
                        activePoint = -1
                        pinchStartDistance = Math.max(1, distanceBetween(pointState[ids[0]], pointState[ids[1]]))
                        pinchStartZoom = root.readerZoom
                        root.pendingZoom = root.readerZoom
                    }
                    function updatePinch() {
                        var ids = pointIds()
                        if (!pinchActive || ids.length < 2)
                            return
                        var distance = distanceBetween(pointState[ids[0]], pointState[ids[1]])
                        root.pendingZoom = Math.max(1.0, Math.min(2.4,
                            pinchStartZoom * distance / pinchStartDistance))
                        readerStatus.text = Math.round(root.pendingZoom * 100) + "%"
                    }
                    function finishPinch() {
                        if (!pinchActive)
                            return
                        pinchActive = false
                        root.readerZoom = Math.max(1.0, Math.min(2.4, root.pendingZoom))
                        readerStatus.text = Math.round(root.readerZoom * 100) + "%"
                        store.savedZoom = root.readerZoom
                        if (e2eSettings.rssTraceScroll)
                            console.log("PaperRSS E2E zoom gesture", root.readerZoom)
                        Qt.callLater(root.settleReader)
                    }

                    onPressed: function(points) {
                        remember(points)
                        if (pointIds().length >= 2) {
                            beginPinch()
                        } else if (points.length > 0) {
                            activePoint = points[0].pointId
                            pressX = points[0].x
                            pressY = points[0].y
                            suppressTap = false
                            startContentY = readerFlick.contentY
                        }
                    }
                    onUpdated: function(points) {
                        remember(points)
                        if (pinchActive) {
                            updatePinch()
                            return
                        }
                        for (var i = 0; i < points.length; ++i) {
                            if (points[i].pointId !== activePoint)
                                continue
                            var delta = points[i].y - pressY
                            if (!suppressTap && Math.abs(delta) >= 12)
                                suppressTap = true
                            if (suppressTap) {
                                var bottom = Math.max(0, readerFlick.contentHeight - readerFlick.height)
                                readerFlick.contentY = Math.max(0, Math.min(bottom, startContentY - delta))
                                if (e2eSettings.rssTraceScroll && !root.e2eScrollLogged && readerFlick.contentY > 50) {
                                    root.e2eScrollLogged = true
                                    console.log("PaperRSS E2E full text scrolled", readerFlick.contentY)
                                }
                            }
                            break
                        }
                    }
                    onReleased: function(points) {
                        remember(points)
                        if (pinchActive)
                            finishPinch()
                        for (var i = 0; i < points.length; ++i) {
                            if (points[i].pointId === activePoint && !suppressTap) {
                                var localX = (points[i].x - readerText.x) / root.readerZoom
                                var localY = (points[i].y + readerFlick.contentY - readerText.y) / root.readerZoom
                                var link = readerText.linkAt(localX, localY)
                                if (link && link.length) {
                                    var target = root.resolveHttpUrl(link, currentArticle.link || currentArticle.id)
                                    if (target) {
                                        console.log("PaperRSS follow article link", target)
                                        fetchFullArticle(target)
                                    } else {
                                        readerStatus.text = "Internal page link ignored"
                                        console.log("PaperRSS blocked non-web article link", link)
                                    }
                                }
                            }
                            delete pointState[points[i].pointId]
                        }
                        if (pointIds().length === 0) {
                            activePoint = -1
                            suppressTap = false
                        }
                    }
                    onCanceled: function(points) {
                        if (pinchActive)
                            finishPinch()
                        pointState = ({})
                        activePoint = -1
                        suppressTap = false
                    }
                }
            }
        }
    }

    Rectangle {
        id: addView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.keyboardInset
        color: "white"
        visible: root.view === "add"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 112
                color: "black"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12
                    ActionButton {
                        objectName: "rssCancelAddButton"
                        label: "← Cancel"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action cancel add")
                            view = "list"
                            Qt.inputMethod.hide()
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "PAPERDESK  /  SOURCES"
                            color: "white"
                            font.pointSize: 10
                            font.bold: true
                            font.letterSpacing: 2
                        }
                        Text {
                            text: "Add a feed"
                            color: "white"
                            font.pointSize: 24
                            font.bold: true
                        }
                    }
                    ActionButton {
                        objectName: "rssAddButton"
                        label: "Add feed"
                        primary: true
                        border.color: "white"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: {
                            console.log("PaperRSS action add feed")
                            addFeed()
                        }
                    }
                    ActionButton {
                        objectName: "rssAddCloseButton"
                        label: "Close"
                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 76
                        onTriggered: { Qt.inputMethod.hide(); root.close() }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Column {
                    anchors.top: parent.top
                    anchors.topMargin: 50
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 180, 1040)
                    spacing: 14
                    Text {
                        text: "NEW SOURCE"
                        color: "black"
                        font.pointSize: 13
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "Add RSS or Atom"
                        color: "black"
                        font.pointSize: 29
                        font.bold: true
                        bottomPadding: 10
                    }
                    Rectangle { width: parent.width; height: 2; color: "black" }
                    Text {
                        text: "FEED NAME"
                        color: "black"
                        font.pointSize: 14
                        font.bold: true
                        font.letterSpacing: 1
                        topPadding: 8
                    }
                    TextField {
                        id: feedName
                        objectName: "rssFeedNameInput"
                        width: parent.width
                        height: 82
                        leftPadding: 18
                        rightPadding: 18
                        font.pointSize: 20
                        color: "black"
                        placeholderText: "e.g. My blog"
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onAccepted: feedUrl.forceActiveFocus()
                        background: Rectangle {
                            color: "white"
                            radius: 8
                            border.color: "black"
                            border.width: feedName.activeFocus ? 4 : 2
                        }
                    }
                    Text {
                        text: "FEED ADDRESS"
                        color: "black"
                        font.pointSize: 14
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    TextField {
                        id: feedUrl
                        objectName: "rssFeedUrlInput"
                        width: parent.width
                        height: 82
                        leftPadding: 18
                        rightPadding: 18
                        font.pointSize: 19
                        color: "black"
                        placeholderText: "https://example.org/feed.xml"
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onAccepted: addFeed()
                        background: Rectangle {
                            color: "white"
                            radius: 8
                            border.color: "black"
                            border.width: feedUrl.activeFocus ? 4 : 2
                        }
                    }
                    Text {
                        id: addStatus
                        width: parent.width
                        color: "black"
                        font.pointSize: 15
                        font.bold: true
                        wrapMode: Text.WordWrap
                        topPadding: 8
                        text: "Saved locally. The first download starts when you refresh."
                    }
                }
            }
        }
    }

    Timer {
        id: addKeyboardTimer
        interval: 350
        repeat: false
        onTriggered: {
            feedName.forceActiveFocus()
            Qt.inputMethod.show()
        }
    }

    DisplayMethodArea {
        anchors.fill: parent
        displayMethod: DisplayMethodArea.Fast
        z: -1
    }

    Component.onCompleted: {
        loadState()
        if (e2eScenarioActive() && e2eSettings.rssStressParser) {
            var stressBody = ""
            for (var stressWord = 0; stressWord < 400; ++stressWord)
                stressBody += "bounded parser payload "
            var stressXml = "<rss><channel>"
            for (var stressIndex = 0; stressIndex < 160; ++stressIndex)
                stressXml += "<item><title>Stress " + stressIndex + "</title><link>https://example.com/stress/" + stressIndex + "</link><description><![CDATA[<p>" + stressBody + "</p>]]></description></item>"
            stressXml += "</channel></rss>"
            var stressStarted = Date.now()
            var stressParsed = parseFeed(stressXml, "PaperDesk stress", "e2e-stress")
            console.log("PaperRSS E2E stress parser ready", stressParsed.length,
                        stressXml.length, Date.now() - stressStarted)
        }
        if (e2eScenarioActive() && e2eSettings.rssAutoFullText) {
            var automaticFullTextUrl = e2eSettings.rssAutoFullTextUrl || "https://example.com"
            var automaticFullTextTitle = e2eSettings.rssAutoFullTextTitle || "Automatic full text test"
            articles = [{ id: "hardware-auto-full-text", title: automaticFullTextTitle,
                source: "PaperDesk E2E", date: Date.now(), link: automaticFullTextUrl,
                summary: "Feed copy remains visible while the page downloads.",
                content: "<p>Feed copy remains visible while the page downloads.</p>",
                fullText: false, feedUrl: "e2e" }]
            openArticle(0)
            console.log("PaperRSS E2E automatic full text ready")
        } else if (e2eScenarioActive() && e2eSettings.rssLongArticle) {
            var paragraphs = ""
            for (var i = 0; i < 120; ++i)
                paragraphs += "<p><a href='https://example.com/" + i + "'>Hardware full-text paragraph " + i + "</a> with enough words to wrap across the reader.</p>"
            articles = [{ id: "hardware-scroll", title: "Hardware scroll test",
                source: "PaperDesk E2E", date: Date.now(), link: "https://example.com",
                summary: "Hardware scroll test", content: paragraphs, fullText: true,
                feedUrl: "e2e" }]
            openArticle(0)
            console.log("PaperRSS E2E full text ready", readerFlick.contentHeight)
        } else if (articles.length === 0) {
            refreshAll()
        }
    }
}
