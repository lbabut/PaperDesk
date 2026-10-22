import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQml 2.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    signal close
    function unloading() {
        nativeDownload.shutdown()
        dismissKeyboard()
        abortAll()
    }
    function gainedFocus() {
        root.forceActiveFocus()
        Qt.inputMethod.hide()
    }

    property var request: null
    property var styleRequests: []
    property var requestFactory: function() { return new XMLHttpRequest() }
    property int networkTimeoutMs: 30000
    property int stylesheetTimeoutMs: 6000
    property var finishStylesheets: null
    property int loadGeneration: 0
    property var history: []
    property int historyIndex: -1
    property string currentUrl: ""
    property string pageTitle: "PaperWeb"
    property bool loading: false
    property bool mobileMode: webSettings.savedMobileMode
    property bool showPictures: webSettings.savedShowPictures
    readonly property string mobileUserAgent: "Mozilla/5.0 (Linux; Android 13; Mobile; rv:121.0) Gecko/121.0 Firefox/121.0"
    readonly property int automaticRetryDelay: 850
    property real contentZoom: 1.0
    property real pendingZoom: 1.0
    property bool e2eScrollLogged: false
    property alias downloadPanel: nativeDownload

    Timer {
        id: pageTimeout
        interval: root.networkTimeoutMs
        onTriggered: {
            root.abortAll()
            root.showError("The connection timed out. Please try Reload.")
        }
    }
    Timer {
        id: stylesheetTimeout
        interval: root.stylesheetTimeoutMs
        onTriggered: if (root.finishStylesheets) root.finishStylesheets()
    }

    Settings {
        id: webSettings
        category: "PaperWeb"
        property bool savedMobileMode: true
        property bool savedShowPictures: false
        property string savedLastUrl: ""
    }

    Timer {
        id: navigationRetryTimer
        objectName: "webNavigationRetryTimer"
        interval: root.automaticRetryDelay
        repeat: false
        property string targetUrl: ""
        property bool addToHistory: false
        property int attempt: 0
        property int expectedGeneration: -1
        onTriggered: {
            if (expectedGeneration !== root.loadGeneration || root.request !== null)
                return
            root.navigate(targetUrl, addToHistory, attempt)
        }
    }

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property int scenarioVersion: 0
        property bool webFixture: false
        property bool webBlockedFileFixture: false
        property bool webDownloadFixture: false
        property bool webTraceGestures: false
        property bool webLiveWp: false
        property bool webLiveNineGag: false
        property bool webLiveLinkedImages: false
        property bool webLiveDenseCards: false
        property bool webLiveArticleJourney: false
        property bool webLiveScriptFilter: false
        property bool webLivePolishText: false
    }

    component ActionButton: Rectangle {
        property string label: "Action"
        property bool primary: false
        property real labelPointSize: 16
        property string iconName: ""
        signal triggered

        implicitWidth: 176
        implicitHeight: 76
        radius: 8
        color: actionTap.pressed || primary ? "black" : "white"
        border.color: enabled ? "black" : "#777777"
        border.width: 2
        opacity: 1

        Text {
            anchors.centerIn: parent
            visible: parent.iconName.length === 0
            text: parent.label
            color: !parent.enabled ? "#666666" : (actionTap.pressed || parent.primary ? "white" : "black")
            font.pointSize: parent.labelPointSize
            font.bold: true
        }
        Canvas {
            id: vectorIcon
            objectName: parent.objectName + "VectorIcon"
            anchors.centerIn: parent
            width: 46
            height: 46
            visible: parent.iconName.length > 0
            property color inkColor: parent.enabled && (actionTap.pressed || parent.primary) ? "white" : "black"

            onInkColorChanged: requestPaint()
            onVisibleChanged: requestPaint()
            onPaint: {
                var context = getContext("2d")
                var centerX = width / 2
                var centerY = height / 2
                context.clearRect(0, 0, width, height)
                context.strokeStyle = inkColor
                context.fillStyle = inkColor
                context.lineWidth = 4.5
                context.lineCap = "round"
                context.lineJoin = "round"

                if (parent.iconName === "back") {
                    context.beginPath()
                    context.moveTo(34, centerY)
                    context.lineTo(12, centerY)
                    context.lineTo(22, 13)
                    context.moveTo(12, centerY)
                    context.lineTo(22, 33)
                    context.stroke()
                    return
                }

                if (parent.iconName !== "reload")
                    return

                var radius = 13.5
                var endAngle = 1.8 * Math.PI
                var tipX = centerX + radius * Math.cos(endAngle)
                var tipY = centerY + radius * Math.sin(endAngle)
                var tangentX = -Math.sin(endAngle)
                var tangentY = Math.cos(endAngle)
                var normalX = -tangentY
                var normalY = tangentX

                context.beginPath()
                context.arc(centerX, centerY, radius, 0.2 * Math.PI, endAngle, false)
                context.stroke()

                context.beginPath()
                context.moveTo(tipX + 2.5 * tangentX, tipY + 2.5 * tangentY)
                context.lineTo(tipX - 8.5 * tangentX + 5.5 * normalX,
                               tipY - 8.5 * tangentY + 5.5 * normalY)
                context.lineTo(tipX - 8.5 * tangentX - 5.5 * normalX,
                               tipY - 8.5 * tangentY - 5.5 * normalY)
                context.closePath()
                context.fill()
            }
        }
        TapHandler {
            id: actionTap
            enabled: parent.enabled
            onTapped: {
                root.dismissKeyboard()
                parent.triggered()
            }
        }
    }

    function dismissKeyboard() {
        var wasEditing = address.activeFocus || Qt.inputMethod.visible
        address.focus = false
        root.forceActiveFocus()
        Qt.inputMethod.hide()
        if (wasEditing)
            console.log("PaperWeb keyboard hidden")
    }

    function finishAddressSelection() {
        if (!address.activeFocus)
            return
        address.selectAll()
        Qt.inputMethod.show()
        console.log("PaperWeb address selected", address.selectedText.length)
        Qt.callLater(function() {
            if (address.activeFocus)
                console.log("PaperWeb address selection stable", address.selectedText.length, address.text.length)
        })
    }

    function selectAddressForEditing() {
        address.forceActiveFocus()
        // The TextInput also receives the physical tap. Let that event finish
        // positioning its cursor before selecting the URL, otherwise the tap
        // can replace selectAll() with a partial selection on the tablet.
        Qt.callLater(finishAddressSelection)
    }

    function configurePageRequest(xhr) {
        if (!mobileMode)
            return
        try {
            xhr.setRequestHeader("User-Agent", mobileUserAgent)
            xhr.setRequestHeader("Accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5")
        } catch (error) {
            console.log("PaperWeb mobile request headers unavailable", error)
        }
    }

    function hasDownloadExtension(url) {
        return /\.(?:7z|apk|bz2|csv|deb|doc|docx|epub|exe|gif|gz|iso|mobi|mp3|mp4|msi|odp|ods|odt|pdf|png|jpg|jpeg|rar|svg|tar|tgz|txt|webp|xls|xlsx|zip)(?:[?#]|$)/i.test(String(url || ""))
    }

    function responseWantsDownload(xhr, url) {
        var disposition = String(xhr.getResponseHeader("Content-Disposition") || "")
        var type = String(xhr.getResponseHeader("Content-Type") || "").toLowerCase()
        return /\battachment\b/i.test(disposition) || hasDownloadExtension(url) ||
               (/^(?:application\/octet-stream|application\/pdf|application\/zip|application\/epub\+zip|audio\/|video\/)/.test(type))
    }

    function showUnsupportedDownload(value) {
        var url = normalizeUrl(value)
        currentUrl = url
        address.text = url
        pageTitle = "Download unavailable"
        pageText.text = "<h1>Unsupported file type</h1>" +
                        "<p>My files supports PDF and EPUB documents. Other file types cannot be added to the tablet reader. " +
                        "Open this address on another device instead.</p>"
        contentFlick.contentY = 0
        statusText.text = "Download unavailable"
        loading = false
        console.log("PaperWeb file download blocked", url)
    }

    function offerFileDownload(value, xhr) {
        var url=normalizeUrl(value),type=xhr?String(xhr.getResponseHeader("Content-Type")||"").toLowerCase():""
        var disposition=xhr?String(xhr.getResponseHeader("Content-Disposition")||""):""
        var size=xhr?Number(xhr.getResponseHeader("Content-Length")||0):0
        var match=/filename\*?\s*=\s*(?:UTF-8''|["']?)([^"';\r\n]+)/i.exec(disposition)
        var name=match?match[1]:url.split(/[?#]/)[0].split("/").pop()
        try{name=decodeURIComponent(name)}catch(e){}
        var nativeFile=/\.(pdf|epub)(?:[?#]|$)/i.test(url)||/\.(pdf|epub)$/i.test(name)||/^(application\/(pdf|epub\+zip))(?:;|$)/i.test(type)
        if(!nativeFile && (hasDownloadExtension(url)||/filename/i.test(disposition))){showUnsupportedDownload(url);return false}
        name=(name||"PaperWeb document").replace(/\.(pdf|epub)$/i,"").slice(0,120)
        nativeDownload.offer(url,name,size)
        return true
    }

    function settlePagePosition() {
        contentFlick.contentX = 0
        var bottom = Math.max(0, contentFlick.contentHeight - contentFlick.height)
        contentFlick.contentY = Math.max(0, Math.min(bottom, contentFlick.contentY))
        contentFlick.returnToBounds()
    }

    function applyZoom(value) {
        contentZoom = Math.max(1.0, Math.min(2.5, value))
        pendingZoom = contentZoom
        statusText.text = Math.round(contentZoom * 100) + "%  " + pageTitle
        Qt.callLater(settlePagePosition)
    }

    function escapeHtml(value) {
        return String(value)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/\"/g, "&quot;")
    }

    function unicodeCharacter(code) {
        code = Number(code)
        if (!isFinite(code) || code < 0 || code > 1114111)
            return ""
        if (code <= 65535)
            return String.fromCharCode(code)
        code -= 65536
        return String.fromCharCode(55296 + (code >> 10), 56320 + (code & 1023))
    }

    function decodeHtmlEntities(value) {
        var text = String(value || "")
        var named = {
            nbsp: " ", amp: "&", quot: "\"", apos: "'", lt: "<", gt: ">",
            aogon: "ą", Aogon: "Ą", cacute: "ć", Cacute: "Ć",
            eogon: "ę", Eogon: "Ę", lstrok: "ł", Lstrok: "Ł",
            nacute: "ń", Nacute: "Ń", oacute: "ó", Oacute: "Ó",
            sacute: "ś", Sacute: "Ś", zacute: "ź", Zacute: "Ź",
            zdot: "ż", Zdot: "Ż"
        }
        // Two passes also handle source text containing &amp;#347;.
        for (var pass = 0; pass < 2; ++pass) {
            text = text.replace(/&#x([0-9a-f]+);?/gi,
                                function(all, hex) { return unicodeCharacter(parseInt(hex, 16)) })
            text = text.replace(/&#([0-9]+);?/g,
                                function(all, decimal) { return unicodeCharacter(parseInt(decimal, 10)) })
            text = text.replace(/&([a-zA-Z]+);/g,
                                function(all, name) { return named[name] !== undefined ? named[name] : all })
        }
        return text
    }

    function repairUtf8Mojibake(value) {
        var text = String(value || "")
        if (!/[\u00c2-\u00c5]/.test(text))
            return text
        var encoded = ""
        var windows1252 = {
            8364: 128, 8218: 130, 402: 131, 8222: 132, 8230: 133,
            8224: 134, 8225: 135, 710: 136, 8240: 137, 352: 138,
            8249: 139, 338: 140, 381: 142, 8216: 145, 8217: 146,
            8220: 147, 8221: 148, 8226: 149, 8211: 150, 8212: 151,
            732: 152, 8482: 153, 353: 154, 8250: 155, 339: 156,
            382: 158, 376: 159
        }
        for (var i = 0; i < text.length; ++i) {
            var code = text.charCodeAt(i)
            if (code > 255) {
                if (windows1252[code] === undefined)
                    return text
                code = windows1252[code]
            }
            encoded += "%" + ("0" + code.toString(16)).slice(-2)
        }
        try {
            return decodeURIComponent(encoded)
        } catch (error) {
            return text
        }
    }

    function plainTextFromHtml(value) {
        var text = stripTechnicalBlocks(value)
            .replace(/<[^>]+>/g, " ")
        text = decodeHtmlEntities(repairUtf8Mojibake(text))
        return text
            .replace(/\s+/g, " ")
            .trim()
    }

    function stripTechnicalBlocks(value) {
        var text = String(value || "")
        // Remove payloads, not just their tags. This must happen before text
        // extraction and before size limiting: cutting a large document in
        // the middle of a script otherwise exposes the remaining JavaScript.
        text = text.replace(/<(script|style|noscript|svg|canvas|video|audio|iframe|object|embed|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
        text = text.replace(/<(script|style|noscript|svg|canvas|video|audio|iframe|object|embed|template)\b[^>]*>[\s\S]*$/gi, " ")
        return text
    }

    function visibleDocumentText(source) {
        var html = String(source || "")
        html = html.replace(/<!--[\s\S]*?-->/g, " ")
        html = html.replace(/<(script|style|noscript|svg|canvas|video|audio|iframe|object|embed|template)[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
        var bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)
        return plainTextFromHtml(bodyMatch ? bodyMatch[1] : html)
    }

    function shouldUseCompactReader(source) {
        if (mobileMode)
            return true

        // Computer mode keeps a denser desktop document. JavaScript-only app
        // shells are the exception: QML cannot execute their web runtime, so
        // use embedded article/feed data instead of displaying an empty page.
        var html = String(source || "")
        var visibleText = visibleDocumentText(html)
        var scriptCount = (html.match(/<script\b/gi) || []).length
        var applicationShell = /__NEXT_DATA__|__NUXT__|__APOLLO_STATE__|application\/(?:ld\+)?json|JSON\.parse\(/i.test(html)
        return (scriptCount >= 6 && visibleText.length < 700) ||
               (applicationShell && visibleText.length < 1400)
    }

    function pageReaderTitle(source, finalUrl) {
        var titleMatch = String(source || "").match(/<title[^>]*>([\s\S]*?)<\/title>/i)
        var title = titleMatch ? plainTextFromHtml(titleMatch[1]) : ""
        if (title.length > 52)
            title = title.substring(0, 49) + "..."
        if (title.length)
            return title
        var host = String(finalUrl || "").match(/^https?:\/\/([^\/?#]+)/i)
        return host ? host[1].replace(/^www\./i, "") : "Web"
    }

    function readerPicture(imageUrl) {
        imageUrl = String(imageUrl || "").replace(/\\\//g, "/")
        if (!showPictures || !/^https?:\/\//i.test(imageUrl))
            return ""
        return "<p class=\"paper-picture\"><img src=\"" + escapeHtml(displayImageUrl(imageUrl)) + "\" width=\"560\"></p>"
    }

    function displayImageUrl(imageUrl) {
        imageUrl = String(imageUrl || "").replace(/\\\//g, "/")
        if (!/^https?:\/\//i.test(imageUrl))
            return ""
        if (/^https:\/\/images\.weserv\.nl\//i.test(imageUrl))
            return imageUrl
        // Compatibility gateway for image CDNs that reject the tablet's
        // legacy TLS stack. It also removes animation and limits bandwidth.
        return "https://images.weserv.nl/?url=" + encodeURIComponent(imageUrl) +
               "&w=560&output=jpg"
    }

    function imageSourceFromTag(tag) {
        tag = String(tag || "")
        var names = ["src", "data-src", "data-original", "data-lazy-src", "data-url"]
        for (var i = 0; i < names.length; ++i) {
            var pattern = new RegExp("\\b" + names[i] + "\\s*=\\s*[\"']([^\"']+)[\"']", "i")
            var match = tag.match(pattern)
            if (match && match[1].length)
                return match[1]
        }
        var srcset = tag.match(/\b(?:srcset|data-srcset)\s*=\s*["']([^"']+)["']/i)
        if (srcset) {
            var first = srcset[1].split(",")[0].trim().split(/\s+/)[0]
            if (first.length)
                return first
        }
        return ""
    }

    function htmlStoryReader(source, finalUrl) {
        var html = String(source || "")
        var articleMatch = html.match(/<article\b[^>]*>([\s\S]*?)<\/article\s*>/i)
        var headingCount = (html.match(/<h[1-4]\b/gi) || []).length
        if (articleMatch && plainTextFromHtml(articleMatch[1]).length > 1200 && headingCount < 4)
            return ""
        var anchorPattern = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi
        var imageAnchorPattern = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi
        var linkedPictures = ({})
        var imageAnchor
        while ((imageAnchor = imageAnchorPattern.exec(html)) !== null) {
            var imageHref = imageAnchor[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)
            var imageTag = imageAnchor[2].match(/<img\b[^>]*>/i)
            if (!imageHref || !imageTag)
                continue
            var linkedPage = resolveUrl(imageHref[1], finalUrl)
            var linkedImage = resolveUrl(imageSourceFromTag(imageTag[0]), finalUrl)
            if (/^https?:\/\//i.test(linkedPage) && /^https?:\/\//i.test(linkedImage))
                linkedPictures[linkedPage] = linkedImage
        }
        var cards = []
        var pictureCards = 0
        var seen = ({})
        var match
        while ((match = anchorPattern.exec(html)) !== null && cards.length < 60) {
            var hrefMatch = match[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)
            var titleMatch = match[2].match(/<h[1-4]\b[^>]*>([\s\S]*?)<\/h[1-4]\s*>/i)
            if (!hrefMatch || !titleMatch)
                continue
            var href = resolveUrl(hrefMatch[1], finalUrl)
            var title = plainTextFromHtml(titleMatch[1])
            if (!/^https?:\/\//i.test(href) || title.length < 12 || seen[href])
                continue
            seen[href] = true
            var picture = ""
            if (showPictures && cards.length < 24) {
                var imageMatch = match[2].match(/<img\b[^>]*>/i)
                var imageSource = imageMatch ? imageSourceFromTag(imageMatch[0]) : linkedPictures[href]
                if (imageSource)
                    picture = readerPicture(resolveUrl(imageSource, finalUrl))
            }
            if (picture.length)
                ++pictureCards
            cards.push("<div class=\"paper-story\"><p class=\"paper-story-title\"><a href=\"" +
                       escapeHtml(href) + "\">" + escapeHtml(title) + "</a></p>" + picture + "</div>")
        }
        var linkedHeadingPattern = /<h[1-4]\b[^>]*>\s*<a\b([^>]*)>([\s\S]*?)<\/a\s*>\s*<\/h[1-4]\s*>/gi
        while ((match = linkedHeadingPattern.exec(html)) !== null && cards.length < 60) {
            var linkedHrefMatch = match[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)
            if (!linkedHrefMatch)
                continue
            var linkedHref = resolveUrl(linkedHrefMatch[1], finalUrl)
            var linkedTitle = plainTextFromHtml(match[2])
            if (!/^https?:\/\//i.test(linkedHref) || linkedTitle.length < 3 || seen[linkedHref])
                continue
            seen[linkedHref] = true
            var linkedPicture = showPictures && cards.length < 24 ? readerPicture(linkedPictures[linkedHref]) : ""
            if (linkedPicture.length)
                ++pictureCards
            cards.push("<div class=\"paper-story\"><p class=\"paper-story-title\"><a href=\"" +
                       escapeHtml(linkedHref) + "\">" + escapeHtml(linkedTitle) + "</a></p>" +
                       linkedPicture + "</div>")
        }
        if (cards.length < 4)
            return ""
        var heading = pageReaderTitle(source, finalUrl)
        console.log("PaperWeb HTML reader items", cards.length, "pictures", pictureCards)
        return "<html><head><title>" + escapeHtml(heading) + "</title></head><body><div class=\"paper-reader-head\">" +
               escapeHtml(heading) + "</div>" +
               cards.join("") + "</body></html>"
    }

    function firstEmbeddedText(object, names) {
        if (!object || typeof object !== "object")
            return ""
        for (var i = 0; i < names.length; ++i) {
            var value = object[names[i]]
            if (typeof value === "string" && value.length)
                return plainTextFromHtml(value)
        }
        return ""
    }

    function embeddedImageUrl(object, depth) {
        if (!object || typeof object !== "object" || depth > 5)
            return ""
        var direct = ["imageUrl", "thumbnailUrl", "posterUrl", "src", "url", "webpUrl"]
        for (var i = 0; i < direct.length; ++i) {
            var value = object[direct[i]]
            if (typeof value === "string" && /^https?:\/\//i.test(value.replace(/\\\//g, "/")))
                return value.replace(/\\\//g, "/")
        }
        var containers = ["images", "image", "thumbnail", "cover", "poster", "media", "image460", "image700"]
        for (var j = 0; j < containers.length; ++j) {
            var nested = object[containers[j]]
            if (typeof nested === "string" && /^https?:\/\//i.test(nested.replace(/\\\//g, "/")))
                return nested.replace(/\\\//g, "/")
            var found = embeddedImageUrl(nested, depth + 1)
            if (found.length)
                return found
        }
        if (object instanceof Array) {
            for (var k = 0; k < object.length && k < 4; ++k) {
                var arrayImage = embeddedImageUrl(object[k], depth + 1)
                if (arrayImage.length)
                    return arrayImage
            }
        }
        return ""
    }

    function findEmbeddedArticle(node, depth, best) {
        if (!node || typeof node !== "object" || depth > 9)
            return
        if (node instanceof Array) {
            for (var i = 0; i < node.length && i < 80; ++i)
                findEmbeddedArticle(node[i], depth + 1, best)
            return
        }
        var type = node["@type"]
        if (type instanceof Array)
            type = type.join(" ")
        type = String(type || "")
        var body = firstEmbeddedText(node, ["articleBody", "text"])
        var headline = firstEmbeddedText(node, ["headline", "title", "name"])
        var score = (/Article|NewsArticle|ReportageNewsArticle/i.test(type) ? 6 : 0) +
                    (body.length > 300 ? 6 : 0) + (headline.length ? 2 : 0)
        if (score > best.score) {
            best.score = score
            best.item = node
        }
        var keys = Object.keys(node)
        for (var j = 0; j < keys.length && j < 100; ++j)
            findEmbeddedArticle(node[keys[j]], depth + 1, best)
    }

    function articleDocumentReader(source, finalUrl) {
        var html = String(source || "")
        var articleMatch = html.match(/<article\b[^>]*>([\s\S]*?)<\/article\s*>/i)
        var articleHeading = articleMatch ? articleMatch[1].match(/<h1\b[^>]*>([\s\S]*?)<\/h1\s*>/i) : null
        if (articleMatch && articleHeading && visibleDocumentText(articleMatch[1]).length > 500) {
            var articleTitle = articleHeading ? plainTextFromHtml(articleHeading[1]) : pageReaderTitle(html, finalUrl)
            var articleContent = articleMatch[1].replace(/<h1\b[^>]*>[\s\S]*?<\/h1\s*>/i, "")
            console.log("PaperWeb article reader DOM", articleTitle)
            return "<html><head><title>" + escapeHtml(articleTitle) +
                   "</title></head><body><div class=\"paper-reader-head\">" +
                   escapeHtml(articleTitle) + "</div>" + articleContent + "</body></html>"
        }

        var scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi
        var match
        var best = { score: 0, item: null }
        while ((match = scriptPattern.exec(html)) !== null) {
            if (!/\btype\s*=\s*["']application\/(?:ld\+)?json["']/i.test(match[1]))
                continue
            try {
                if (match[2].length < 1500000)
                    findEmbeddedArticle(JSON.parse(match[2]), 0, best)
            } catch (error) {}
        }
        if (best.score < 12 || !best.item)
            return ""
        var title = firstEmbeddedText(best.item, ["headline", "title", "name"])
        var body = firstEmbeddedText(best.item, ["articleBody", "text"])
        var description = firstEmbeddedText(best.item, ["description"])
        var imageUrl = embeddedImageUrl({ image: best.item.image, thumbnail: best.item.thumbnailUrl }, 0)
        var paragraphs = body.split(/\n+/)
        var bodyHtml = ""
        for (var p = 0; p < paragraphs.length; ++p) {
            var paragraph = paragraphs[p].trim()
            if (paragraph.length)
                bodyHtml += "<p>" + escapeHtml(paragraph) + "</p>"
        }
        console.log("PaperWeb article reader JSON", title)
        return "<html><head><title>" + escapeHtml(title) + "</title></head><body>" +
               "<div class=\"paper-reader-head\">" + escapeHtml(title) + "</div>" +
               readerPicture(imageUrl) +
               (description.length ? "<p><b>" + escapeHtml(description) + "</b></p>" : "") +
               bodyHtml + "</body></html>"
    }

    function embeddedItemScore(item) {
        if (!item || typeof item !== "object" || item instanceof Array)
            return 0
        var title = firstEmbeddedText(item, ["title", "headline", "name", "caption"])
        var link = firstEmbeddedText(item, ["url", "permalink", "link", "canonicalUrl"])
        if (!title.length || !link.length)
            return 0
        var description = firstEmbeddedText(item, ["description", "summary", "excerpt", "altText", "text"])
        var image = embeddedImageUrl({ images: item.images, image: item.image,
                                       thumbnail: item.thumbnail, media: item.media }, 0)
        // Navigation arrays are often longer than content feeds. Richness per
        // item is a stronger signal than raw array length.
        return 4 + (description.length ? 3 : 0) + (image.length ? 2 : 0)
    }

    function findEmbeddedItemArray(node, depth, best) {
        if (!node || typeof node !== "object" || depth > 8)
            return
        if (node instanceof Array) {
            var score = 0
            for (var i = 0; i < node.length && i < 8; ++i)
                score += embeddedItemScore(node[i])
            if (score > best.score) {
                best.score = score
                best.items = node
            }
            for (var j = 0; j < node.length && j < 3; ++j)
                findEmbeddedItemArray(node[j], depth + 1, best)
            return
        }
        var keys = Object.keys(node)
        for (var k = 0; k < keys.length && k < 80; ++k)
            findEmbeddedItemArray(node[keys[k]], depth + 1, best)
    }

    function embeddedFeedReader(source, finalUrl) {
        var html = String(source || "")
        var candidates = []
        var parsePattern = /JSON\.parse\("((?:\\.|[^"\\])*)"\)/g
        var match
        while ((match = parsePattern.exec(html)) !== null && candidates.length < 8) {
            try {
                var decoded = JSON.parse("\"" + match[1] + "\"")
                if (decoded.length < 1500000)
                    candidates.push(JSON.parse(decoded))
            } catch (error) {}
        }
        var scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi
        while ((match = scriptPattern.exec(html)) !== null && candidates.length < 12) {
            if (!/\btype\s*=\s*["']application\/(?:ld\+)?json["']/i.test(match[1]))
                continue
            try {
                if (match[2].length < 1500000)
                    candidates.push(JSON.parse(match[2]))
            } catch (error) {}
        }
        var best = { score: 0, items: [] }
        for (var c = 0; c < candidates.length; ++c)
            findEmbeddedItemArray(candidates[c], 0, best)
        if (best.score < 8)
            return ""

        var cards = []
        var seen = ({})
        for (var i = 0; i < best.items.length && cards.length < 24; ++i) {
            var item = best.items[i]
            if (embeddedItemScore(item) === 0)
                continue
            var title = firstEmbeddedText(item, ["title", "headline", "name", "caption"])
            var link = resolveUrl(firstEmbeddedText(item, ["url", "permalink", "link", "canonicalUrl"]), finalUrl)
            if (!/^https?:\/\//i.test(link) || seen[link])
                continue
            seen[link] = true
            var details = firstEmbeddedText(item, ["description", "summary", "excerpt", "altText", "text"])
            if (details.length > 360)
                details = details.substring(0, 357) + "..."
            var imageUrl = embeddedImageUrl({ images: item.images, image: item.image,
                                              thumbnail: item.thumbnail, cover: item.cover,
                                              poster: item.poster, media: item.media }, 0)
            cards.push("<div class=\"paper-story\"><p class=\"paper-story-title\"><a href=\"" +
                       escapeHtml(link) + "\">" + escapeHtml(title) + "</a></p>" + readerPicture(imageUrl) +
                       (details.length ? "<p>" + escapeHtml(details) + "</p>" : "") + "</div>")
        }
        if (cards.length < 2)
            return ""
        var heading = pageReaderTitle(source, finalUrl)
        console.log("PaperWeb embedded reader items", cards.length)
        return "<html><head><title>" + escapeHtml(heading) + "</title></head><body><div class=\"paper-reader-head\">" +
               escapeHtml(heading) + "</div>" +
               cards.join("") + "</body></html>"
    }

    function abortAll() {
        loadGeneration += 1
        navigationRetryTimer.stop()
        pageTimeout.stop()
        stylesheetTimeout.stop()
        finishStylesheets = null
        loading = false
        var previous = request
        request = null
        if (previous !== null) {
            previous.onreadystatechange = null
            previous.abort()
        }
        var styles = styleRequests.slice()
        styleRequests = []
        for (var i = 0; i < styles.length; ++i) {
            styles[i].onreadystatechange = null
            styles[i].abort()
        }
    }

    function usablePageResponse(status, value) {
        var body = String(value || "")
        if (status >= 200 && status < 400)
            return true
        // Qt 5 can occasionally expose a completed first HTTPS request as
        // status 0 while still providing the whole document.
        return status === 0 && body.length >= 200 &&
               /<(?:!doctype|html|body|article|main)\b/i.test(body)
    }

    function shouldRetryPageRequest(status, attempt) {
        if (attempt >= 1)
            return false
        return status === 0 || status === 408 || status === 425 ||
               status === 429 || status >= 500
    }

    function schedulePageRetry(url, addHistory, attempt, generation, status) {
        request = null
        loading = true
        statusText.text = "Retrying..."
        pageText.text = "<h1>Opening page...</h1><p>The first connection did not complete. PaperWeb is trying once more.</p>"
        navigationRetryTimer.targetUrl = url
        navigationRetryTimer.addToHistory = addHistory
        navigationRetryTimer.attempt = attempt + 1
        navigationRetryTimer.expectedGeneration = generation
        navigationRetryTimer.restart()
        console.log("PaperWeb automatic retry", status, url)
    }

    function normalizeUrl(value) {
        var url = String(value || "").trim()
        if (url.length === 0)
            return ""
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(url))
            return url
        return "https://" + url
    }

    function rememberLastAddress(value) {
        var url = normalizeUrl(value)
        if (!/^https?:\/\//i.test(url))
            return false
        webSettings.savedLastUrl = url
        console.log("PaperWeb remembered address", url)
        return true
    }

    function restoreLastAddress() {
        var url = String(webSettings.savedLastUrl || "").trim()
        if (!/^https?:\/\//i.test(url))
            return false
        navigate(url, true)
        console.log("PaperWeb restored address", url)
        return true
    }

    function resolveUrl(link, base) {
        link = decodeHtmlEntities(String(link || "")).trim()
        if (link.length === 0)
            return base
        if (/^(https?|mailto):/i.test(link))
            return link
        if (/^(javascript|data|file):/i.test(link))
            return ""
        var scheme = (base.match(/^([a-z]+:)/i) || ["", "https:"])[1]
        if (link.indexOf("//") === 0)
            return scheme + link
        var originMatch = base.match(/^(https?:\/\/[^\/]+)/i)
        var origin = originMatch ? originMatch[1] : ""
        if (link.charAt(0) === "/")
            return origin + link
        if (link.charAt(0) === "#")
            return base.replace(/#.*$/, "") + link
        var cleanBase = base.replace(/[?#].*$/, "")
        var slash = cleanBase.lastIndexOf("/")
        var combined = (slash > 7 ? cleanBase.substring(0, slash + 1) : cleanBase + "/") + link
        var parts = combined.split("/")
        var output = []
        for (var i = 0; i < parts.length; ++i) {
            if (parts[i] === "..") {
                if (output.length > 3)
                    output.pop()
            } else if (parts[i] !== ".") {
                output.push(parts[i])
            }
        }
        return output.join("/")
    }

    function sanitizeCss(source) {
        var css = String(source || "")
        css = css.replace(/@font-face\s*\{[^}]*\}/gi, "")
        css = css.replace(/@(?:-webkit-)?keyframes\s+[^\{]+\{(?:[^{}]|\{[^{}]*\})*\}/gi, "")
        css = css.replace(/(?:animation|transition)(?:-[a-z-]+)?\s*:[^;}{]+;?/gi, "")
        css = css.replace(/(?:position\s*:\s*fixed|scroll-behavior\s*:\s*smooth)\s*;?/gi, "")
        return css
    }

    function stylesheetUrls(source, finalUrl) {
        var urls = []
        var tags = String(source || "").match(/<link\b[^>]*>/gi) || []
        for (var i = 0; i < tags.length && urls.length < 6; ++i) {
            var rel = tags[i].match(/\brel\s*=\s*["']([^"']+)["']/i)
            var href = tags[i].match(/\bhref\s*=\s*["']([^"']+)["']/i)
            if (!rel || !href || !/stylesheet/i.test(rel[1]))
                continue
            var absolute = resolveUrl(href[1], finalUrl)
            if (/^https?:\/\//i.test(absolute) && urls.indexOf(absolute) < 0)
                urls.push(absolute)
        }
        return urls
    }

    function fetchStylesheets(source, finalUrl, done) {
        if (shouldUseCompactReader(source)) {
            done("")
            return
        }
        var urls = stylesheetUrls(source, finalUrl)
        if (urls.length === 0) {
            done("")
            return
        }
        var pending = urls.length
        var chunks = []
        var total = 0
        var generation = loadGeneration
        var completed = false
        styleRequests = []
        function finish() {
            if (completed || generation !== loadGeneration) return
            completed = true
            stylesheetTimeout.stop()
            finishStylesheets = null
            var active = styleRequests.slice()
            styleRequests = []
            for (var n = 0; n < active.length; ++n) {
                active[n].onreadystatechange = null
                active[n].abort()
            }
            done(chunks.join("\n"))
        }
        finishStylesheets = finish
        stylesheetTimeout.restart()
        function finished() {
            --pending
            if (pending === 0) finish()
        }
        for (var i = 0; i < urls.length; ++i) {
            (function(cssUrl) {
                var cssRequest = requestFactory()
                styleRequests.push(cssRequest)
                cssRequest.onreadystatechange = function() {
                    if (completed || generation !== loadGeneration || cssRequest.readyState !== XMLHttpRequest.DONE)
                        return
                    styleRequests = styleRequests.filter(function(item) { return item !== cssRequest })
                    if (cssRequest.status >= 200 && cssRequest.status < 400 && total < 600000) {
                        var chunk = String(cssRequest.responseText || "").substring(0, 200000)
                        total += chunk.length
                        chunks.push(sanitizeCss(chunk))
                    }
                    finished()
                }
                cssRequest.open("GET", cssUrl, true)
                configurePageRequest(cssRequest)
                cssRequest.send()
            })(urls[i])
        }
    }

    function sanitizeHtml(source, finalUrl, externalCss) {
        var html = String(source || "")
        var compactLayout = shouldUseCompactReader(html)
        if (compactLayout) {
            externalCss = ""
            var adapted = articleDocumentReader(html, finalUrl)
            if (adapted.length === 0)
                adapted = htmlStoryReader(html, finalUrl)
            if (adapted.length === 0)
                adapted = embeddedFeedReader(html, finalUrl)
            if (adapted.length > 0)
                html = adapted
        }
        var titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)
        pageTitle = titleMatch ? plainTextFromHtml(titleMatch[1]) : finalUrl

        var baseMatch = html.match(/<base[^>]+href\s*=\s*[\"']([^\"']+)[\"'][^>]*>/i)
        var documentBase = baseMatch ? resolveUrl(baseMatch[1], finalUrl) : finalUrl

        var inlineCss = ""
        html = html.replace(/<!--[\s\S]*?-->/g, "")
        html = stripTechnicalBlocks(html)
        if (html.length > 2000000)
            html = html.substring(0, 2000000) + "<p><b>[Document shortened to 2 MB]</b></p>"
        html = html.replace(/<(script|link|meta|base|source|track|input|button|textarea|select|option|form)[^>]*\/?\s*>/gi, "")
        var pictureCount = 0
        html = html.replace(/<img\b[^>]*>/gi, function(tag) {
            if (!showPictures || pictureCount >= 12)
                return ""
            var source = imageSourceFromTag(tag)
            if (!source.length)
                return ""
            var imageUrl = resolveUrl(source, documentBase)
            if (!/^https?:\/\//i.test(imageUrl))
                return ""
            imageUrl = displayImageUrl(imageUrl)
            var altMatch = tag.match(/\balt\s*=\s*["']([^"']*)["']/i)
            var caption = altMatch ? plainTextFromHtml(altMatch[1]) : ""
            ++pictureCount
            return "<p class=\"paper-picture\"><img src=\"" + escapeHtml(imageUrl) +
                   "\" width=\"560\">" + (caption.length ? "<br><small>" + escapeHtml(caption) + "</small>" : "") + "</p>"
        })

        html = html.replace(/<a\b([^>]*)href\s*=\s*[\"']([^\"']+)[\"']([^>]*)>/gi,
                            function(all, before, href, after) {
                                var absolute = resolveUrl(href, documentBase)
                                return absolute ? "<a href=\"" + escapeHtml(absolute) + "\">" : "<span>"
                            })
        html = html.replace(/\s(on[a-z]+|background|srcset|autoplay|loop)\s*=\s*([\"'])[^\"']*\2/gi, "")
        html = html.replace(/\s(on[a-z]+|background|srcset|autoplay|loop)\s*=\s*[^\s>]+/gi, "")
        // Source inline geometry can survive even after its stylesheet has
        // been removed. Fixed heights leave enormous gaps and fixed
        // transforms/widths make pictures appear torn. PaperWeb emits its own
        // width for retained images, so dropping source styles is safe.
        html = html.replace(/\sstyle\s*=\s*([\"'])[^\"']*\1/gi, "")
        html = html.replace(/\sstyle\s*=\s*[^\s>]+/gi, "")

        var bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i)
        if (bodyMatch)
            html = bodyMatch[1]

        html = html.replace(/<(\/?)((?!a\b|p\b|br\b|hr\b|img\b|h[1-6]\b|b\b|strong\b|i\b|em\b|u\b|s\b|strike\b|ul\b|ol\b|li\b|pre\b|code\b|blockquote\b|table\b|thead\b|tbody\b|tfoot\b|tr\b|th\b|td\b|span\b|div\b|small\b|big\b|sub\b|sup\b|center\b)[a-z0-9]+)(?:\s[^>]*)?>/gi, "")
        var baseCss = "body{color:#000;background:#fff;font-family:sans-serif;font-size:" +
                      (compactLayout ? "18pt;line-height:1.48" : "14pt;line-height:1.3") + "}" +
                      "a{color:#000;text-decoration:underline;font-weight:600}table{border-collapse:collapse}th,td{border:1px solid #000;padding:7px}" +
                      (showPictures ? "img{display:block!important;background:#fff!important;max-width:100%!important;margin:0 auto!important}video,canvas,svg{display:none!important}" : "img,video,canvas,svg{display:none!important}") +
                      "*[style*='position: fixed'],*[style*='position:fixed']{position:static!important}"
        var commonCss = "html,body{color:#000!important;background:#fff!important}" +
                        "body *{color:#000!important;background-color:#fff!important;box-shadow:none!important;text-shadow:none!important}" +
                        "h1,h2,h3{line-height:1.15!important}a{text-decoration:underline!important;text-decoration-thickness:2px!important}" +
                        ".paper-reader-head{font-weight:700!important;line-height:1.15!important;border-bottom:4px solid #000!important;padding:8px 2px 12px!important;margin-bottom:4px!important}" +
                        ".paper-story{border-bottom:2px solid #000!important;padding:14px 2px 18px!important;margin:0!important}" +
                        ".paper-story a{white-space:normal!important;word-wrap:break-word!important}" +
                        ".paper-picture{text-align:center!important;margin:8px 0 10px!important}.paper-picture small{font-size:12pt!important}" +
                        "button,input,select,textarea{display:none!important}"
        var compactCss =
                       "body{margin:0!important;padding:8px 4px 40px!important;line-height:1.48!important}" +
                       "body div,body section,body article,body main,body header,body footer,body nav,body aside," +
                       "body table,body tbody,body tr,body td,body ul,body ol{float:none!important;position:static!important;" +
                       "display:block!important;width:auto!important;min-width:0!important;max-width:100%!important;" +
                       "column-count:1!important;columns:1!important;grid-template-columns:1fr!important;transform:none!important}" +
                       "h1,h2,h3{margin-top:1.1em!important;margin-bottom:.45em!important}" +
                       "p,li{line-height:1.48!important}a{text-decoration:underline!important;text-decoration-thickness:2px!important}" +
                       ".paper-reader-head{font-size:22pt!important}" +
                       ".paper-story{display:block!important;border-bottom:2px solid #000!important;padding:14px 2px 18px!important;margin:0!important}" +
                       ".paper-story p{font-size:18pt!important;line-height:1.28!important;margin:0!important;white-space:normal!important}" +
                       ".paper-story .paper-story-title{font-size:20pt!important;font-weight:700!important;margin:0 0 10px!important}" +
                       ".paper-story a{display:inline!important;white-space:normal!important;word-wrap:break-word!important}" +
                       ".paper-picture small{font-size:12pt!important}"
        var computerCss = "body{margin:0!important;padding:6px 8px 36px!important;line-height:1.3!important;max-width:100%!important}" +
                          "body *{max-width:100%!important}" +
                          "header,footer,nav,aside{font-size:12pt!important}" +
                          "h1{font-size:22pt!important}h2{font-size:19pt!important}h3{font-size:16pt!important}" +
                          "p,li{line-height:1.3!important;margin-top:.35em!important;margin-bottom:.55em!important}" +
                          ".paper-reader-head{font-size:20pt!important}" +
                          ".paper-story p{font-size:14pt!important;line-height:1.25!important;margin:0!important}" +
                          ".paper-story .paper-story-title{font-size:16pt!important;font-weight:700!important;margin:0 0 7px!important}"
        console.log("PaperWeb renderer", compactLayout ? (mobileMode ? "mobile reader" : "computer fallback") : "computer page")
        return "<html><head><style>" + baseCss + inlineCss + "\n" + sanitizeCss(externalCss) +
               "\n" + commonCss + (compactLayout ? compactCss : computerCss) +
               "</style></head><body>" + html + "</body></html>"
    }

    function showError(message) {
        pageTimeout.stop()
        request = null
        pageText.text = "<h1>Could not open this page</h1><p>" + escapeHtml(message) + "</p>"
        statusText.text = "Error"
        loading = false
    }

    function navigate(value, addHistory, retryAttempt) {
        dismissKeyboard()
        var url = normalizeUrl(value)
        if (url.length === 0)
            return
        abortAll()
        if (!/^https?:\/\//i.test(url)) {
            showError("PaperWeb supports HTTP and HTTPS addresses only.")
            return
        }
        if (hasDownloadExtension(url)) {
            offerFileDownload(url,null)
            return
        }
        var generation = loadGeneration
        currentUrl = url
        address.text = url
        statusText.text = "Loading..."
        pageText.text = "<h1>Loading page...</h1><p>" + escapeHtml(url) + "</p>"
        contentFlick.contentY = 0
        loading = true
        pageTimeout.restart()

        var xhr = requestFactory()
        var attempt = retryAttempt || 0
        request = xhr
        xhr.onreadystatechange = function() {
            if (generation !== loadGeneration || request !== xhr) return
            if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED && request === xhr &&
                    responseWantsDownload(xhr, xhr.responseURL || url)) {
                var downloadUrl = xhr.responseURL || url
                // Only headers; binary data must never enter a QML string.
                var downloadHeaders={}
                for(var header of ["Content-Type","Content-Disposition","Content-Length"])
                    downloadHeaders[header]=xhr.getResponseHeader(header)
                request = null
                loading = false
                pageTimeout.stop()
                // Aborting a QML XMLHttpRequest from inside its own
                // HEADERS_RECEIVED callback can crash Xochitl. Leave the
                // callback first, then stop the unsupported file transfer.
                Qt.callLater(function() {
                    xhr.onreadystatechange = null
                    xhr.abort()
                    if (generation === loadGeneration)
                        offerFileDownload(downloadUrl,{getResponseHeader:function(name){return downloadHeaders[name]||""}})
                })
                return
            }
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (request !== xhr)
                return
            var finalUrl = xhr.responseURL && xhr.responseURL.length ? xhr.responseURL : url
            var responseBody = ""
            try { responseBody = String(xhr.responseText || "") } catch (responseError) {}
            console.log("PaperWeb response", xhr.status, responseBody.length, finalUrl)
            if (usablePageResponse(xhr.status, responseBody)) {
                currentUrl = finalUrl
                address.text = finalUrl
                rememberLastAddress(finalUrl)
                statusText.text = "Style..."
                fetchStylesheets(responseBody, finalUrl, function(css) {
                    if (generation !== loadGeneration)
                        return
                    pageText.text = sanitizeHtml(responseBody, finalUrl, css)
                    if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveScriptFilter) {
                        if (/var MMG|cmpCmd\.push|document\.createElement\s*\(\s*["']script/i.test(pageText.text))
                            console.log("PaperWeb E2E technical content leaked")
                        else
                            console.log("PaperWeb E2E technical content clean")
                    }
                    if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLivePolishText) {
                        if (/&(?:amp;)?#(?:260|261|262|263|280|281|321|322|323|324|346|347|377|378|379|380);|(?:Ä|Å|Ã)[\u0080-\u00bf\u201a\u2026]/.test(pageText.text))
                            console.log("PaperWeb E2E Polish text broken")
                        else
                            console.log("PaperWeb E2E Polish text clean")
                    }
                    statusText.text = Math.round(contentZoom * 100) + "%  " + pageTitle
                    loading = false
                    pageTimeout.stop()
                    request = null
                    if (addHistory) {
                        history = history.slice(0, historyIndex + 1)
                        history.push(finalUrl)
                        historyIndex = history.length - 1
                    }
                })
            } else if (shouldRetryPageRequest(xhr.status, attempt)) {
                schedulePageRetry(url, addHistory, attempt, generation, xhr.status)
            } else {
                showError("HTTP " + xhr.status + " " + xhr.statusText + "\n" + finalUrl)
            }
        }
        xhr.open("GET", url, true)
        configurePageRequest(xhr)
        console.log("PaperWeb request profile", mobileMode ? "mobile" : "desktop")
        xhr.send()
    }

    function goBack() {
        if (historyIndex <= 0)
            return
        historyIndex -= 1
        navigate(history[historyIndex], false)
    }

    ColumnLayout {
        anchors.fill: parent
        enabled: !nativeDownload.visible
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            color: "black"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Column {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    spacing: 1
                    Text {
                        text: "PAPERDESK  /  READER MODE"
                        color: "white"
                        font.pointSize: 10
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "PaperWeb"
                        color: "white"
                        font.pointSize: 25
                        font.bold: true
                    }
                }

                ActionButton {
                    objectName: "webCloseButton"
                    label: "Close"
                    Layout.preferredWidth: 176
                    Layout.preferredHeight: 76
                    onTriggered: {
                        console.log("PaperWeb action close")
                        root.close()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            color: "white"
            border.color: "black"
            border.width: 2
            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                ActionButton {
                    objectName: "webBackButton"
                    label: ""
                    iconName: "back"
                    Layout.preferredWidth: 82
                    Layout.fillHeight: true
                    enabled: historyIndex > 0 && !loading
                    onTriggered: {
                        console.log("PaperWeb action back")
                        goBack()
                    }
                }
                ActionButton {
                    objectName: "webReloadButton"
                    label: ""
                    iconName: "reload"
                    Layout.preferredWidth: 82
                    Layout.fillHeight: true
                    enabled: /^https?:\/\//i.test(root.currentUrl) && !loading
                    onTriggered: {
                        console.log("PaperWeb action reload")
                        root.navigate(root.currentUrl, false)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: "white"
                    border.color: "black"
                    border.width: address.activeFocus ? 4 : 2
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        verticalAlignment: Text.AlignVCenter
                        visible: address.text.length === 0 && !address.activeFocus
                        text: "Enter a web address"
                        color: "black"
                        font.pointSize: 17
                    }
                    TextInput {
                        id: address
                        objectName: "webAddressInput"
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: TextInput.AlignVCenter
                        font.pointSize: 18
                        color: "black"
                        clip: true
                        selectByMouse: false
                        persistentSelection: true
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                Qt.inputMethod.show()
                                Qt.callLater(root.finishAddressSelection)
                                console.log("PaperWeb keyboard opened")
                            } else {
                                Qt.inputMethod.hide()
                            }
                        }
                        onAccepted: navigate(text, true)
                    }
                    TapHandler {
                        onTapped: root.selectAddressForEditing()
                    }
                }
                ActionButton {
                    objectName: "webGoButton"
                    label: loading ? "Stop" : "Go"
                    primary: true
                    Layout.preferredWidth: 156
                    Layout.fillHeight: true
                    onTriggered: {
                        console.log("PaperWeb action", loading ? "stop" : "go")
                        if (loading && request !== null) {
                            abortAll()
                            loading = false
                            statusText.text = "Stopped"
                        } else {
                            navigate(address.text, true)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            color: "white"
            border.color: "#000000"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8
                Text {
                    id: statusText
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    font.pointSize: 15
                    font.bold: true
                    text: "Ready to browse"
                }
                Text {
                    text: ""
                    visible: false
                }
                ActionButton {
                    objectName: "webViewModeButton"
                    label: root.mobileMode ? "View: Mobile" : "View: Computer"
                    Layout.preferredWidth: 230
                    Layout.preferredHeight: 76
                    onTriggered: {
                        root.mobileMode = !root.mobileMode
                        webSettings.savedMobileMode = root.mobileMode
                        console.log("PaperWeb view mode", root.mobileMode ? "mobile" : "computer")
                        if (/^https?:\/\//i.test(root.currentUrl))
                            root.navigate(root.currentUrl, false)
                    }
                }
                ActionButton {
                    objectName: "webPicturesButton"
                    label: root.showPictures ? "Pictures: on" : "Pictures: off"
                    primary: root.showPictures
                    Layout.preferredWidth: 210
                    Layout.preferredHeight: 76
                    onTriggered: {
                        root.showPictures = !root.showPictures
                        webSettings.savedShowPictures = root.showPictures
                        console.log("PaperWeb pictures", root.showPictures ? "shown" : "hidden")
                        if (/^https?:\/\//i.test(root.currentUrl))
                            root.navigate(root.currentUrl, false)
                    }
                }
                Text {
                    text: Math.round(root.contentZoom * 100) + "%"
                    font.pointSize: 15
                    font.bold: true
                    font.letterSpacing: 1
                }
                ActionButton {
                    objectName: "webZoomOutButton"
                    label: "−"
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 76
                    onTriggered: {
                        console.log("PaperWeb action zoom out")
                        root.applyZoom(root.contentZoom - 0.2)
                    }
                }
                ActionButton {
                    objectName: "webZoomInButton"
                    label: "+"
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 76
                    onTriggered: {
                        console.log("PaperWeb action zoom in")
                        root.applyZoom(root.contentZoom + 0.2)
                    }
                }
            }
        }

        Item {
            id: contentPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 18

            Rectangle {
                anchors.fill: parent
                color: "white"
                border.color: "black"
                border.width: 2
                radius: 8
            }

            Flickable {
                id: contentFlick
                anchors.fill: parent
                anchors.margins: 3
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, pageText.paintedHeight * root.contentZoom + 48)
                flickableDirection: Flickable.VerticalFlick
                interactive: false
                pixelAligned: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    width: 16
                }

                Text {
                    id: pageText
                    x: 24
                    y: 20
                    width: (contentFlick.width - 64) / root.contentZoom
                    scale: root.contentZoom
                    transformOrigin: Item.TopLeft
                    textFormat: Text.RichText
                    wrapMode: Text.WordWrap
                    font.pointSize: 18
                    color: "black"
                    linkColor: "black"
                    text: "<h1>Read the web quietly.</h1><p>Enter an address above. PaperWeb removes visual noise and prepares the page for a crisp e-ink screen.</p><p><b>One finger</b> scrolls. <b>Two fingers</b> change the text size.</p>"
                    onLinkActivated: function(link) {
                        navigate(link, true)
                    }
                }
            }

            MultiPointTouchArea {
                id: pageTouch
                // A sibling of the Flickable: stationary viewport coordinates
                // keep scrolling, pinch zoom and link hit-testing in sync.
                anchors.fill: parent
                anchors.margins: 3
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
                    pinchStartZoom = root.contentZoom
                    root.pendingZoom = root.contentZoom
                }
                function updatePinch() {
                    var ids = pointIds()
                    if (!pinchActive || ids.length < 2)
                        return
                    var distance = distanceBetween(pointState[ids[0]], pointState[ids[1]])
                    root.pendingZoom = Math.max(1.0, Math.min(2.5,
                        pinchStartZoom * distance / pinchStartDistance))
                    statusText.text = Math.round(root.pendingZoom * 100) + "%  " + root.pageTitle
                }
                function finishPinch() {
                    if (!pinchActive)
                        return
                    pinchActive = false
                    root.applyZoom(root.pendingZoom)
            if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webTraceGestures)
                        console.log("PaperWeb E2E zoom gesture", root.contentZoom)
                }

                function linkAtViewport(x, y) {
                    var localX = (x - pageText.x) / root.contentZoom
                    var localY = (y + contentFlick.contentY - pageText.y) / root.contentZoom
                    var probes = [[0, 0], [-8, 0], [8, 0], [0, -7], [0, 7]]
                    for (var i = 0; i < probes.length; ++i) {
                        var link = pageText.linkAt(localX + probes[i][0] / root.contentZoom,
                                                   localY + probes[i][1] / root.contentZoom)
                        if (link && link.length)
                            return link
                    }
                    return ""
                }

                onPressed: function(points) {
                    root.dismissKeyboard()
                    remember(points)
                    if (pointIds().length >= 2) {
                        beginPinch()
                    } else if (points.length > 0) {
                        activePoint = points[0].pointId
                        pressX = points[0].x
                        pressY = points[0].y
                        suppressTap = false
                        startContentY = contentFlick.contentY
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
                            var bottom = Math.max(0, contentFlick.contentHeight - contentFlick.height)
                            contentFlick.contentY = Math.max(0, Math.min(bottom, startContentY - delta))
                            if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webTraceGestures && !root.e2eScrollLogged && contentFlick.contentY > 50) {
                                root.e2eScrollLogged = true
                                console.log("PaperWeb E2E content scrolled", contentFlick.contentY)
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
                            var link = linkAtViewport(points[i].x, points[i].y)
                            if (link && link.length) {
                                console.log("PaperWeb link activated", link)
                                navigate(link, true)
                            } else {
                                console.log("PaperWeb link miss", points[i].x, points[i].y)
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

    NativeDownload {
        id:nativeDownload
        onCloseWeb:{root.unloading();root.close()}
    }

    function logDownloadTargets(item) {
        if(!item.visible)return
        if(item.objectName && /^webDownload/.test(item.objectName) && item.mapToItem){
            var p=item.mapToItem(null,item.width/2,item.height/2)
            console.log("PaperWeb download target",item.objectName,Math.round(p.x),Math.round(p.y),item.enabled)
        }
        if(item.children)for(var i=0;i<item.children.length;i++)logDownloadTargets(item.children[i])
    }
    Timer {
        interval:1500;repeat:true;running:e2eSettings.webDownloadFixture
        onTriggered:{console.log("PaperWeb download state",nativeDownload.phase);root.logDownloadTargets(root)}
    }

    Component.onDestruction:nativeDownload.shutdown()

    DisplayMethodArea {
        anchors.fill: parent
        displayMethod: DisplayMethodArea.Fast
        z: -1
    }

    Component.onCompleted: {
        if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webDownloadFixture) {
            pageText.text="<h1>Download test</h1><p><a href='https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'>Download the small PDF document</a></p><p><a href='https://example.com/unsupported.zip'>Unsupported ZIP</a></p>"
            pageTitle="Download test";statusText.text="Tap the PDF link";console.log("PaperWeb download fixture ready")
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webBlockedFileFixture) {
            pageText.text = "<p><a href='https://paperdesk.lukaszbabut.info/download/SHA256SUMS'>" +
                            "<b>Open unsupported file</b></a></p>"
            pageTitle = "Unsupported file test"
            currentUrl = "https://paperdesk.lukaszbabut.info/file-test"
            address.text = currentUrl
            statusText.text = "Tap the file link"
            console.log("PaperWeb E2E blocked file fixture ready")
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveArticleJourney) {
            mobileMode = true
            showPictures = false
            navigate("https://kryminalne.o2.pl/", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveScriptFilter) {
            mobileMode = true
            showPictures = true
            navigate("https://demotywatory.pl/", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLivePolishText) {
            mobileMode = true
            showPictures = false
            navigate("https://m.gazeta.pl/0,0.html", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveDenseCards) {
            mobileMode = true
            navigate("https://jbzd.com.pl/motoryzacja", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveLinkedImages) {
            mobileMode = true
            navigate("https://chamsko.pl/", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveNineGag) {
            mobileMode = true
            navigate("https://9gag.com/", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webLiveWp) {
            mobileMode = true
            navigate("https://www.wp.pl/", true)
        } else if (e2eSettings.scenarioVersion === 20260927 && e2eSettings.webFixture) {
            var fixture = "<h1>PaperWeb hardware action test</h1>"
            for (var i = 0; i < 100; ++i)
                fixture += "<p><a href='gopher://fixture.invalid/" + i + "'>Fixture link " + i + "</a> and enough text to exercise scrolling and zoom.</p>"
            pageText.text = fixture
            pageTitle = "Hardware action test"
            currentUrl = "gopher://second.invalid"
            address.text = currentUrl
            history = ["gopher://first.invalid", currentUrl]
            historyIndex = 1
            statusText.text = "100%  " + pageTitle
            console.log("PaperWeb E2E fixture ready")
        } else {
            // Let the window, Settings backend and Qt network stack finish
            // their first event-loop turn before restoring a saved page.
            Qt.callLater(restoreLastAddress)
        }
    }

}
