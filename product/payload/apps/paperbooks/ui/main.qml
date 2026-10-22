import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.1
import net.asivery.ApploadUtils
import net.asivery.AppLoad 1.0
import "../books.js" as Books
import "../catalogues.js" as Catalogues

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    focus: true
    signal close()

    property string view: "shelf"
    property string status: ""
    property var database: null
    property var cachedBooks: ({})
    property var searchRows: []
    property var searchPages: []
    property int searchGeneration: 0
    property bool searching: false
    property bool searched: false
    property bool sortExpanded: false
    readonly property string sortCaption: prefs.searchSort === "author" ? "Author" : prefs.searchSort === "newest" ? "Newest added" : "Title"
    readonly property var sortOptions: [
        {code: "title", title: "Title", target: "booksSortTitle"},
        {code: "author", title: "Author", target: "booksSortAuthor"},
        {code: "newest", title: "Newest added", target: "booksSortNewest"}
    ]
    onViewChanged: sortExpanded = false
    property bool gutenbergSucceeded: false
    property int searchFailures: 0
    property var requests: []
    property bool disposed: false
    property bool initialized: false
    property string downloadingId: ""
    property var catalogueCache: ({})
    property var nativeBridge: null
    property var nativeJob: null
    property bool pollingNative: false
    property var nativeBooks: ({})
    property string pendingNativePath: ""
    property string lastNativeId: ""
    property double arxivLastRequest: 0
    property string deleteId: ""
    property string deleteTitle: ""
    property string readingId: ""
    property string readingTitle: ""
    property string readingAuthor: ""
    property string readingText: ""
    property var readingBlocks: []
    property var chapters: []
    property int readerGeneration: 0
    property bool readerLoading: false
    property real pendingFont: prefs.readerFont
    property int visibleBlock: 0
    property real keyboardInset: Qt.inputMethod.visible ? Math.max(height * 0.38, Qt.inputMethod.keyboardRectangle.height) : 0
    readonly property var languageOptions: [
        {code: "pl", title: "Polski"}, {code: "en", title: "English"},
        {code: "no", title: "Norsk"}, {code: "de", title: "Deutsch"},
        {code: "fr", title: "Français"}, {code: "es", title: "Español"},
        {code: "it", title: "Italiano"}, {code: "pt", title: "Português"}
    ]
    readonly property var sourceOptions: Catalogues.sources
    readonly property int currentChapter: chapterAt(visibleBlock)

    Settings {
        id: prefs
        objectName: "booksPreferences"
        category: "PaperDeskBooks"
        property string preferredLanguages: "pl,en,no"
        property string preferredSources: "gutenberg,europepmc"
        property bool expandedSourcesV1: false
        property string nativeBooksJson: "{}"
        property string progressJson: "{}"
        property string offlineBooksJson: "{}"
        property string bookMetadataJson: "{}"
        property bool iliadHidden: false
        property bool typographyV2: false
        property int readerFont: 27
        property string searchSort: "title"
    }
    Settings { id: testSettings; category: "PaperDeskE2E"; property bool booksTrace: false; property string booksQuery: "" }
    ListModel { id: shelfModel }
    ListModel { id: searchModel }
    ListModel { id: readerModel }

    component ActionButton: Rectangle {
        id: button
        property string label: "Action"
        property bool primary: false
        property bool available: true
        signal triggered()
        implicitWidth: 176
        implicitHeight: 76
        radius: 8
        enabled: available
        color: available && (actionTap.pressed || primary) ? "black" : "white"
        border.color: available ? "black" : "#999999"
        border.width: 2
        Text {
            anchors.fill: parent
            anchors.margins: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: button.label
            color: !button.available ? "#888888" : (actionTap.pressed || button.primary ? "white" : "black")
            font.pointSize: 16
            font.bold: true
        }
        TapHandler { id: actionTap; enabled: button.available; onTapped: button.triggered() }
    }

    component SelectionTile: Rectangle {
        id: tile
        property bool checked: false
        property string title: ""
        property string detail: ""
        signal toggled()
        implicitHeight: detail ? 132 : 108
        radius: 8
        color: checked ? "black" : "white"
        border.color: "black"
        border.width: 2
        onCheckedChanged: selectionMark.requestPaint()
        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20
            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 5
                color: "white"
                border.width: 2
                border.color: "black"
                Canvas {
                    id: selectionMark
                    objectName: tile.objectName + "Mark"
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (!tile.checked) return
                        ctx.strokeStyle = "black"; ctx.lineWidth = 5
                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                        ctx.beginPath(); ctx.moveTo(10, 22); ctx.lineTo(18, 30); ctx.lineTo(33, 12); ctx.stroke()
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: tile.title; color: tile.checked ? "white" : "black"; font.pointSize: 18; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Text { visible: tile.detail !== ""; text: tile.detail; color: tile.checked ? "white" : "black"; font.pointSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
        TapHandler { onTapped: tile.toggled() }
    }

    function safeParse(text, fallback) {
        try { var value = JSON.parse(text || ""); return value && typeof value === "object" ? value : fallback }
        catch (error) { return fallback }
    }
    function syncPrefs() { if (typeof prefs.sync === "function") prefs.sync() }
    function storedBooks() { return safeParse(prefs.offlineBooksJson, {}) }
    function initialize() {
        if(disposed)return
        if (prefs.expandedSourcesV1 === false) {
            var selected = prefs.preferredSources.split(",")
            ;["wolnelektury", "openstax", "arxiv", "openlibrary"].forEach(function(s) { if (selected.indexOf(s) < 0) selected.push(s) })
            prefs.preferredSources = selected.join(","); prefs.expandedSourcesV1 = true
        }
        nativeBooks = safeParse(prefs.nativeBooksJson, {})
        catalogueCache = ({})
        if (!prefs.typographyV2) {
            prefs.readerFont = Math.max(14, Math.min(36, Math.round(prefs.readerFont * 0.78)))
            prefs.typographyV2 = true
        }
        var storage = null
        try {
            storage = Qt.createQmlObject('import QtQuick 2.15; import QtQuick.LocalStorage 2.0; QtObject { function openShelf() { return LocalStorage.openDatabaseSync("PaperDeskBooks", "1.0", "Offline book shelf", 50000000) } }', root, "PaperBooksOptionalStorage")
            database = storage.openShelf()
            database.transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY, title TEXT, author TEXT, language TEXT, content TEXT, bundled INTEGER)")
            })
        } catch (error) { database = null }
        if (storage !== null) storage.destroy()
        loadShelf()
        status = "Tap a title to read. Your offline books need no internet."
        initialized=true
    }
    function loadShelf() {
        var books = storedBooks()
        if (database !== null) {
            try {
                database.readTransaction(function(tx) {
                    var rows = tx.executeSql("SELECT id, title, author, language, content, bundled FROM books WHERE bundled = 0").rows
                    for (var i = 0; i < rows.length; ++i) books[rows.item(i).id] = rows.item(i)
                })
            } catch (error) { status = "Could not read some saved books. Your other books are still available." }
        }
        cachedBooks = books
        var rows = []
        if (!prefs.iliadHidden)
            rows.push({bookId: "gutenberg:2199", bookTitle: "The Iliad", fileFormat:"text",
                               bookAuthor: "Homer · Samuel Butler", bookLanguage: "en"})
        var ids = Object.keys(books).sort(function(a, b) { return String(books[a].title).localeCompare(String(books[b].title)) })
        for (var j = 0; j < ids.length; ++j) {
            var b = books[ids[j]]
            if (!b || ids[j] === "gutenberg:2199" || typeof b.content !== "string") continue
            rows.push({bookId: ids[j], bookTitle: String(b.title || "Untitled"), fileFormat:"text",
                               bookAuthor: Books.authorFromText(b.content, b.author), bookLanguage: String(b.language || "")})
        }
        for(var nativeId in nativeBooks) {
            var nativeBook=nativeBooks[nativeId]
            if(!nativeBook || (!nativeBook.documentId && !nativeBook.pending)) continue
            rows.push({bookId:nativeId,bookTitle:nativeBook.title,bookAuthor:nativeBook.author,
                bookLanguage:nativeBook.language,fileFormat:nativeBook.format})
        }
        reconcileRows(shelfModel, rows, typeof shelfList === "undefined" ? null : shelfList)
        renderSearchResults()
    }
    function isSaved(bookId) { return bookId === "gutenberg:2199" ? !prefs.iliadHidden : !!cachedBooks[bookId] || !!(nativeBooks[bookId] && nativeBooks[bookId].documentId) }
    function persistDownloadedBook(bookId, title, author, language, content) {
        if (database !== null) {
            database.transaction(function(tx) {
                tx.executeSql("INSERT OR REPLACE INTO books (id, title, author, language, content, bundled) VALUES (?, ?, ?, ?, ?, 0)",
                              [bookId, title, author, language, content])
            })
        } else {
            var books = storedBooks()
            books[bookId] = {id: bookId, title: title, author: author, language: language, content: content, bundled: 0}
            var serialized = JSON.stringify(books)
            if (serialized.length > 10000000) throw new Error("Offline shelf is full")
            prefs.offlineBooksJson = serialized
        }
        var meta = safeParse(prefs.bookMetadataJson, {})
        meta[bookId] = {savedAt: new Date().toISOString(), length: content.length, checksum: Books.checksum(content)}
        prefs.bookMetadataJson = JSON.stringify(meta)
        syncPrefs()
    }
    function requestDelete(bookId, title) { deleteId = bookId; deleteTitle = title; Qt.inputMethod.hide() }
    function deleteBook(bookId) {
        if(nativeBooks[bookId]) {
            var nativeCopy=Object.assign({},nativeBooks);delete nativeCopy[bookId];nativeBooks=nativeCopy
            prefs.nativeBooksJson=JSON.stringify(nativeBooks)
            if(lastNativeId===bookId)lastNativeId=""
            deleteId="";syncPrefs();loadShelf();status="Removed from Books. The document in My files has not been deleted.";return
        }
        if (bookId === "gutenberg:2199") prefs.iliadHidden = true
        else {
            if (database !== null) database.transaction(function(tx) { tx.executeSql("DELETE FROM books WHERE id = ?", [bookId]) })
            var books = storedBooks(); delete books[bookId]; prefs.offlineBooksJson = JSON.stringify(books)
        }
        var positions = savedPositions(); delete positions[bookId]; prefs.progressJson = JSON.stringify(positions)
        var meta = safeParse(prefs.bookMetadataJson, {}); delete meta[bookId]; prefs.bookMetadataJson = JSON.stringify(meta)
        deleteId = ""
        syncPrefs(); loadShelf(); status = "Deleted from offline shelf."
    }
    function supportedLang(code) { return prefs.preferredLanguages.split(",").indexOf(code) >= 0 }
    function setLanguage(code, enabled) {
        var selected = prefs.preferredLanguages.split(",").filter(function(v) { return v !== "" })
        var index = selected.indexOf(code)
        if (enabled && index < 0) selected.push(code)
        if (!enabled && index >= 0 && selected.length > 1) selected.splice(index, 1)
        prefs.preferredLanguages = selected.join(",")
        syncPrefs()
    }
    function supportedSource(code) { return prefs.preferredSources.split(",").indexOf(code) >= 0 }
    function setSource(code, enabled) {
        if (!Catalogues.known(code)) return
        var selected = prefs.preferredSources.split(",").filter(Catalogues.known)
        var index = selected.indexOf(code)
        if (enabled && index < 0) selected.push(code)
        if (!enabled && index >= 0 && selected.length > 1) selected.splice(index, 1)
        prefs.preferredSources = selected.join(",")
        syncPrefs()
    }
    function sourceSummary() {
        var names = []
        for (var i=0; i<Catalogues.sources.length; ++i) if (supportedSource(Catalogues.sources[i].code)) names.push(Catalogues.sources[i].title)
        return names.join(" + ")
    }
    function switchView(next) {
        sortExpanded = false; endSettleTimer.stop(); readerFlick.cancelFlick()
        savePosition(); Qt.inputMethod.hide(); view = next
        if (next === "shelf") {
            if (!searching && !downloadingId) status = "Tap a title to read. Your offline books need no internet."
            loadShelf() // A storage error must be allowed to replace the hint.
        }
        if (!searching && !downloadingId) {
            if (next === "search") status = searched ? "Tap a result to save it offline, or open a saved book." : "Search by title, author or research topic."
            else if (next === "settings") status = "Your choices are saved on this tablet."
        }
    }
    function unloading() {
        if(nativeJob && !pendingNativePath) AppLoadLauncher.launchApplication("external::paperbooks-download",["--cancel",nativeJob.token],{},false)
        if(nativeBridge) { nativeBridge.destroy();nativeBridge=null }
        disposed = true; readerFlick.cancelFlick(); savePosition(); positionSyncTimer.stop(); syncPrefs(); Qt.inputMethod.hide(); cancelRequests("")
    }
    function cancelRequests(category) {
        var pending = requests.slice()
        for (var i = 0; i < pending.length; ++i)
            if (!category || pending[i].category === category) pending[i].cancel()
    }
    function fetchText(url, category, success, failure) {
        var xhr = new XMLHttpRequest(), complete = false
        var ticket = {xhr: xhr, category: category, started: Date.now(), cancel: function(message) { finish(false, message || "Request cancelled."); xhr.abort() }}
        function finish(ok, message) {
            if (complete) return
            complete = true
            requests = requests.filter(function(item) { return item !== ticket })
            if (disposed) return
            if (ok) success(xhr.responseText)
            else failure(message)
        }
        requests = requests.concat([ticket])
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                finish(xhr.status === 200 || (category === "reader" && xhr.status === 0 && xhr.responseText.length > 0), "Could not fetch the book. Please check your connection.")
        }
        xhr.onerror = function() { finish(false, "Connection failed. Please try again.") }
        xhr.send()
    }
    // Update roles in place: resetting a ListModel destroys all delegates and
    // makes ListView jump to row zero after every completed download.
    function reconcileRows(model, rows, list) {
        var anchor = null
        if (list && model.count) {
            var index = list.indexAt(20, list.contentY + 20)
            var item = index >= 0 ? list.itemAtIndex(index) : null
            if (item) anchor = {id: model.get(index).bookId, offset: list.contentY - item.y}
        }
        var structural = false
        for (var i = 0; i < rows.length; ++i) {
            if (i >= model.count) { model.append(rows[i]); structural = true; continue }
            if (model.get(i).bookId !== rows[i].bookId) {
                var found = -1
                for (var j = i + 1; j < model.count; ++j)
                    if (model.get(j).bookId === rows[i].bookId) { found = j; break }
                if (found >= 0) model.move(found, i, 1)
                else model.insert(i, rows[i])
                structural = true
            }
            var keys = Object.keys(rows[i])
            for (var k = 0; k < keys.length; ++k)
                if (model.get(i)[keys[k]] !== rows[i][keys[k]]) model.setProperty(i, keys[k], rows[i][keys[k]])
        }
        if (model.count > rows.length) { model.remove(rows.length, model.count - rows.length); structural = true }
        if (anchor && structural) Qt.callLater(function() {
            if (disposed) return
            for (var i = 0; i < model.count; ++i) if (model.get(i).bookId === anchor.id) {
                list.positionViewAtIndex(i, ListView.Beginning)
                list.forceLayout()
                var item = list.itemAtIndex(i)
                if (item) list.contentY = Math.max(list.originY, Math.min(item.y + anchor.offset,
                    list.originY + Math.max(0, list.contentHeight - list.height)))
                break
            }
        })
    }
    function renderSearchResults() {
        var rows = []
        var sorted = Books.sortRows(searchRows, prefs.searchSort)
        for (var i = 0; i < sorted.length; ++i) {
            var b = sorted[i]
            rows.push({bookId: b.bookId, bookTitle: b.bookTitle, bookAuthor: b.bookAuthor,
                                bookLanguage: b.bookLanguage, bookSource: b.bookSource || Books.sourceName(b.bookId), downloadUrl: b.downloadUrl,
                                fileFormat: b.format || "text", savedOffline: isSaved(b.bookId)})
        }
        reconcileRows(searchModel, rows, typeof searchList === "undefined" ? null : searchList)
    }
    function setSearchSort(order) {
        sortExpanded = false
        if (["title", "author", "newest"].indexOf(order) < 0) return
        if (prefs.searchSort === order) return
        prefs.searchSort = order; syncPrefs(); renderSearchResults()
        if (searched) searchBooks()
    }
    function searchBooks() {
        sortExpanded = false
        var query = searchInput.text.trim()
        if (query.length > 150) { status = "Search is too long."; return }
        var token = ++searchGeneration
        cancelRequests("search"); Qt.inputMethod.hide()
        searchRows = []; searchPages = []; renderSearchResults(); searching = true; searched = true
        status = "Searching " + sourceSummary() + "…"
        searchFailures = 0; gutenbergSucceeded = false
        var languages = prefs.preferredLanguages.split(",")
        var serverSort = prefs.searchSort === "newest" ? "release_date" : prefs.searchSort
        var queue = supportedSource("gutenberg") ? languages.map(function(language) {
            return {source: "gutenberg", language: language, url: "https://www.gutenberg.org/ebooks/search.opds/?query=" + encodeURIComponent(query + " l." + language) + "&sort_order=" + serverSort}
        }) : []
        if (supportedSource("gutenberg")) queue.push({source: "gutendex", fallback: true, language: "",
            url: "https://gutendex.com/books/?languages=" + encodeURIComponent(prefs.preferredLanguages) +
                 "&copyright=false&search=" + encodeURIComponent(query) + (prefs.searchSort === "newest" ? "&sort=descending" : "")})
        if (supportedSource("europepmc")) queue.push({source: "europepmc", language: "",
            url: "https://www.ebi.ac.uk/europepmc/webservices/rest/search?format=json&resultType=core&pageSize=20&query=" +
                 encodeURIComponent(Books.scienceQuery(query, languages)) + (prefs.searchSort === "newest" ? "%20sort_date:y" : "")})
        if (supportedSource("wolnelektury") && languages.indexOf("pl") >= 0) queue.push({source:"wolnelektury",language:"",query:query,offset:0,
            url:"https://wolnelektury.pl/api/books/?format=json"})
        if (supportedSource("openstax")) queue.push({source:"openstax",language:"",query:query,offset:0,
            url:"https://openstax.org/apps/cms/api/v2/pages/?type=books.Book&fields=title,book_state,license_name,license_url,pdf_url,authors&limit=200"})
        if (supportedSource("arxiv") && languages.indexOf("en") >= 0) queue.push(arxivPage(query,0))
        if (supportedSource("openlibrary")) queue.push(openLibraryPage(query,0))
        searchQueue(queue, 0, token, 0)
    }
    function arxivPage(query, offset) {
        return {source:"arxiv",language:"",query:query,offset:offset,url:"https://export.arxiv.org/api/query?search_query="+
            encodeURIComponent(Catalogues.arxivQuery(query))+"&max_results=20&start="+offset+
            (prefs.searchSort === "newest" ? "&sortBy=submittedDate&sortOrder=descending" : "")}
    }
    function openLibraryPage(query, offset) {
        var langs={en:"eng",pl:"pol",no:"nor",de:"ger",fr:"fre",es:"spa",it:"ita",pt:"por"}
        var filter=prefs.preferredLanguages.split(",").map(function(l){return "language:"+langs[l]}).join(" OR ")
        var safe=String(query).replace(/["\\():]/g," ").trim().split(/\s+/).filter(function(w){return w}).map(function(w){return '"'+w+'"'}).join(" AND ")
        return {source:"openlibrary",language:"",query:query,offset:offset,url:"https://openlibrary.org/search.json?limit=20&offset="+offset+
            "&fields=key,title,author_name,language,ia,ebook_access,availability,first_publish_year&q="+encodeURIComponent((safe ? "("+safe+") AND " : "")+"ebook_access:public AND ("+filter+")")}
    }
    function searchQueue(queue, index, token, successes) {
        if (token !== searchGeneration) return
        if (index >= queue.length) {
            searching = false; renderSearchResults()
            status = !successes ? "Selected services are unavailable. Your offline shelf still works." :
                searchRows.length + " results · Tap a title to save or read offline." + (searchFailures ? " Some services could not be reached." : "")
            return
        }
        var page = queue[index]
        if (page.fallback && gutenbergSucceeded) { searchQueue(queue, index + 1, token, successes); return }
        function accept(xml, cached) {
            if (token !== searchGeneration) return
            var parsed
            try {
                if (page.source === "europepmc") parsed = Books.parseScience(xml)
                else if (page.source === "gutendex") parsed = parseGutendex(xml)
                else if (page.source === "arxiv") parsed = Catalogues.arxiv(xml, Books)
                else if (page.source === "openlibrary") parsed = Catalogues.openLibrary(xml, Books.languageCode)
                else if (page.source === "wolnelektury" || page.source === "openstax") {
                    var catalogue = cached || (page.source === "wolnelektury" ? Catalogues.wolneCatalogue(xml) : Catalogues.openstaxCatalogue(xml))
                    if (!cached) {
                        catalogueCache[page.source]={saved:Date.now(),rows:catalogue}
                    }
                    parsed=Catalogues.localPage(catalogue,page.query,prefs.preferredLanguages.split(","),page.offset||0,prefs.searchSort)
                }
                else {
                    if (!/<feed\b/i.test(xml)) throw new Error("Unexpected catalogue response")
                    parsed = Books.parseOpds(xml, page.language); gutenbergSucceeded = true
                }
            } catch (error) { ++searchFailures; searchQueue(queue, index + 1, token, successes); return }
            var seen = {}; for (var i = 0; i < searchRows.length; ++i) seen[searchRows[i].bookId] = true
            var merged = searchRows.slice()
            for (var j = 0; j < parsed.rows.length; ++j) if (!seen[parsed.rows[j].bookId]) { merged.push(parsed.rows[j]); seen[parsed.rows[j].bookId] = true }
            searchRows = merged
            if (parsed.next) searchPages = searchPages.concat([{url: parsed.next, language: page.language, source: page.source}])
            if (parsed.nextOffset >= 0) {
                var next = page.source === "arxiv" ? arxivPage(page.query,parsed.nextOffset) :
                    page.source === "openlibrary" ? openLibraryPage(page.query,parsed.nextOffset) :
                    {source:page.source,language:"",query:page.query,offset:parsed.nextOffset,url:page.url}
                searchPages=searchPages.concat([next])
            }
            renderSearchResults(); searchQueue(queue, index + 1, token, successes + 1)
        }
        var cache=(typeof catalogueCache !== "undefined" ? catalogueCache : {})[page.source]
        if (cache && cache.rows && Date.now()-cache.saved < 86400000) { accept("",cache.rows); return }
        // arXiv requests are paced across searches and pagination, not just within one queue.
        if (page.source === "arxiv" && Date.now()-arxivLastRequest < 3100) {
            arxivDelay.resume=function(){ if(token === searchGeneration) searchQueue(queue,index,token,successes) }
            arxivDelay.interval=3100-(Date.now()-arxivLastRequest); arxivDelay.restart(); return
        }
        if (page.source === "arxiv") arxivLastRequest=Date.now()
        fetchText(page.url,"search",function(xml){accept(xml,null)}, function() { if (token === searchGeneration) { ++searchFailures; searchQueue(queue, index + 1, token, successes) } })
    }
    function loadMore() {
        if (searching || !searchPages.length) return
        var pages = searchPages.slice(); searchPages = []; searching = true
        status = "Loading more books…"; searchQueue(pages, 0, searchGeneration, 1)
    }
    function parseGutendex(text) {
        var response = JSON.parse(text), rows = response.results || [], result = []
        for (var i = 0; i < rows.length; ++i) {
            var b = rows[i]
            if (!b.id || !b.title) continue
            result.push({bookId: "gutenberg:" + b.id, catalogueId: b.id, bookTitle: b.title,
                         bookAuthor: (b.authors || []).map(function(a) { return a.name }).join(" · ") || "Unknown author",
                         bookLanguage: (b.languages || []).join(", "), bookSource: "Project Gutenberg",
                         published: "", downloadUrl: findPlainText(b.formats || {})})
        }
        return {rows: result, next: /^https:\/\/gutendex\.com\/books\/\?/.test(response.next || "") ? response.next : ""}
    }
    function findPlainText(formats) {
        var fallback = ""
        for (var mime in formats) if (/^text\/plain/i.test(mime) && /^https:\/\//i.test(formats[mime]) && !/\.zip(?:$|\?)/i.test(formats[mime])) {
            if (/utf-8/i.test(mime)) return formats[mime]
            fallback = formats[mime]
        }
        return fallback
    }
    function selectSearchBook(bookId, title, author, language, url) {
        if (nativeBooks[bookId]) { openNativeBook(bookId);return }
        if (isSaved(bookId)) { openBook(bookId); return }
        if (bookId === "gutenberg:2199") { prefs.iliadHidden = false; loadShelf(); status = "Saved offline · " + title; return }
        if (/^(?:wolnelektury|openlibrary|openstax|arxiv):/.test(bookId)) {
            if (downloadingId) { status="Please wait for the current download to finish."; return }
            if (!nativeImporter()) { status="Native PDF/EPUB import is unavailable on this firmware. Your text books still work."; return }
            downloadingId=bookId
            var book={id:bookId,title:title,author:author,language:language,url:url}
            if (/^(?:wolnelektury|openlibrary):/.test(bookId)) {
                status="Checking the complete, unrestricted edition…"
                fetchText(url,"download",function(text){
                    try {
                        var edition=bookId.indexOf("wolnelektury:")===0 ? Catalogues.wolneEdition(text,bookId,prefs.preferredLanguages.split(",")) : Catalogues.archiveEdition(text,bookId,prefs.preferredLanguages.split(","))
                        book.url=edition.url;book.format=edition.format
                        if(edition.language)book.language=edition.language
                        startNativeDownload(book)
                    } catch(e) { downloadingId="";status=String(e) }
                },function(message){downloadingId="";status=message})
            } else { book.format="pdf";startNativeDownload(book) }
        } else downloadBook(bookId, title, author, language, url)
    }
    function nativeImporter() {
        if (nativeBridge && nativeBridge.importer) return nativeBridge.importer
        try {
            nativeBridge=Qt.createQmlObject('import QtQml; import xofm.libs.library; QtObject { property var importer: DocumentImporter; property var lib: Library; property var controller: LibraryController }',root,"PaperBooksNativeBridge")
            if(nativeBridge.importer && typeof nativeBridge.importer.importFromUrls === "function") return nativeBridge.importer
            nativeBridge.destroy();nativeBridge=null
        } catch(e) { /* Unsupported firmware: keep the text reader usable. */ }
        return null
    }
    function openNativeBook(bookId) {
        var b=nativeBooks[bookId]
        if(!b || !nativeImporter()) {status="Open this document from My files.";return}
        if(!b.documentId){status="An earlier import may already be in My files. Check there first; remove this shortcut from Books if you need to retry.";return}
        var entry=nativeBridge.lib.entryForId(b.documentId)
        if(!entry || entry.isTrashed) {status="This document is no longer in My files. Remove its shortcut to download it again.";return}
        status="“"+b.title+"” is in My files. Close Books and AppLoad, then tap it to use the built-in reader."
        lastNativeId=bookId
    }
    function nativeImported(document, collection, source) {
        if(!nativeJob || !pendingNativePath) return
        if(testSettings.booksTrace)console.log("PaperBooks import signal",String(document),String(collection),String(source),document ? String(document.id) : "")
        if(!source || decodeURIComponent(String(source)) !== "file://"+pendingNativePath)return
        nativeJob.importReported=true;nativeJob.importSource=String(source)
        var id=document && document.id ? document.id.toString().replace(/^\{|\}$/g,"") : ""
        if(!/^[0-9a-fA-F-]{36}$/.test(id)){resolveNativeImport();return}
        finishNativeImport(id,String(source))
    }
    function noteNativeEntry(entryId) {
        if(!nativeJob || !pendingNativePath || !nativeBridge)return
        var id=entryId.toString().replace(/^\{|\}$/g,"")
        var entry=nativeBridge.lib.entryForId(id)
        var expected=pendingNativePath.slice(pendingNativePath.lastIndexOf("/")+1).replace(/\.(pdf|epub)$/i,"")
        if(!entry || entry.visibleName!==expected)return
        var candidates=nativeJob.candidates||[]
        if(candidates.indexOf(id)<0)candidates.push(id)
        nativeJob.candidates=candidates
        if(testSettings.booksTrace)console.log("PaperBooks matching native entry",id)
        resolveNativeImport()
    }
    function resolveNativeImport() {
        // DocumentImporter emits a raw C++ shared_ptr, not the QML wrapper.
        // Library supplies the corresponding public wrapper/UUID. Match both
        // the source-completion event and the newly added filename.
        if(!nativeJob || !nativeJob.importReported || !(nativeJob.candidates||[]).length)return
        if(nativeJob.candidates.length!==1){status="Import completed. Check My files; more than one matching document appeared.";return}
        finishNativeImport(nativeJob.candidates[0],nativeJob.importSource)
    }
    function finishNativeImport(id,source) {
        var b=nativeJob.book,token=nativeJob.token,copy=Object.assign({},nativeBooks)
        copy[b.id]={documentId:id,title:b.title,author:b.author,language:b.language,format:b.format}
        nativeBooks=copy;prefs.nativeBooksJson=JSON.stringify(copy);lastNativeId=b.id
        syncPrefs();loadShelf();status="Added to My files · "+b.title+". Close Books and AppLoad to use the built-in reader."
        if(testSettings.booksTrace)console.log("PaperBooks native imported",b.id,id,String(source))
        nativeJob=null;pendingNativePath="";downloadingId=""
        AppLoadLauncher.launchApplication("external::paperbooks-download",["--clean",token],{},false)
    }
    function cancelNativeDownload() {
        if(!nativeJob || pendingNativePath)return
        AppLoadLauncher.launchApplication("external::paperbooks-download",["--cancel",nativeJob.token],{},false)
        nativeJob=null;downloadingId="";status="Download cancelled. Nothing was added to My files."
    }
    function startNativeDownload(book) {
        var token=Date.now().toString(36)+"-"+Math.floor(Math.random()*0x7fffffff).toString(36)
        nativeJob={token:token,book:book,started:Date.now()}
        pendingNativePath=""
        status="Downloading "+book.format.toUpperCase()+" for the tablet reader…"
        AppLoadLauncher.launchApplication("external::paperbooks-download",[token,book.url,book.format,book.title],{},false)
    }
    function pollNativeDownload() {
        if (!nativeJob) return
        if (Date.now()-nativeJob.started>360000) {
            status=pendingNativePath ? "Import is taking longer than expected. Check My files before trying again." : "The download timed out. Please try again."
            if(!pendingNativePath)AppLoadLauncher.launchApplication("external::paperbooks-download",["--cancel",nativeJob.token],{},false)
            nativeJob=null;downloadingId="";pendingNativePath="";return
        }
        if(pendingNativePath){resolveNativeImport();return}
        if (pollingNative) return
        pollingNative=true
        var token=nativeJob.token
        fetchText("file:///home/root/.local/share/paperdesk/books-inbox/"+token+"/status.json","reader",function(text){
            pollingNative=false
            if (!nativeJob || nativeJob.token!==token) return
            var result=safeParse(text,{})
            if (result.state==="error") { status=result.message;nativeJob=null;downloadingId="";return }
            if (result.state!=="ready") return
            var prefix="/home/root/.local/share/paperdesk/books-inbox/"+token+"/"
            if (typeof result.path!=="string" || result.path.indexOf(prefix)!==0 || result.path.slice(prefix.length).indexOf("/")>=0 ||
                !/\.(?:pdf|epub)$/.test(result.path)) { nativeJob=null;downloadingId="";status="The download returned an invalid path.";return }
            pendingNativePath=result.path
            var b=nativeJob.book,pending=Object.assign({},nativeBooks)
            pending[b.id]={documentId:"",pending:true,title:b.title,author:b.author,language:b.language,format:b.format}
            nativeBooks=pending;prefs.nativeBooksJson=JSON.stringify(pending);syncPrefs()
            status="Adding to My files with the tablet’s native importer…"
            try { nativeImporter().importFromUrls(["file://"+result.path.split("/").map(encodeURIComponent).join("/")],"") }
            catch(e) { pendingNativePath="";nativeJob=null;downloadingId="";status="Native import could not start: "+String(e) }
        },function(){pollingNative=false})
    }
    function downloadBook(bookId, title, author, language, url) {
        if (downloadingId) { status = "Please wait for the current download to finish."; return }
        if (!/^https:\/\//i.test(url)) { status = "No plain-text edition is available for this book."; return }
        downloadingId = bookId; status = "Saving “" + title + "” offline…"
        fetchText(url, "download", function(content) {
            downloadingId = ""
            var scientific = /^europepmc:PMC[0-9]+$/.test(bookId)
            if (scientific) {
                try { content = Books.scienceText(content, bookId, title, author) }
                catch (error) { status = String(error); return }
            }
            var problem = scientific ? "" : Books.validateDownload(content, bookId)
            if (problem) { status = problem; return }
            try {
                persistDownloadedBook(bookId, title, Books.authorFromText(content, author), language, content)
                loadShelf(); status = "Saved offline · " + title
            } catch (error) { status = "Could not save the book. The shelf may be full." }
        }, function(message) { downloadingId = ""; status = message })
    }
    function savedPositions() { return safeParse(prefs.progressJson, {}) }
    function readerBookmark() {
        if (!readerModel.count) return {version: 2, block: 0, offset: 0, character: 0}
        var index = readerFlick.indexAt(30, readerFlick.contentY + 2)
        if (index < 0) index = readerFlick.indexAt(30, readerFlick.contentY + 24)
        if (index < 0) index = Math.max(0, Math.min(readerModel.count - 1, visibleBlock))
        var item = readerFlick.itemAtIndex(index)
        return {version: 2, block: index, offset: item ? readerFlick.contentY - item.y : 0,
                character: readingBlocks[index].offset, scrollY: Math.round(readerFlick.contentY)}
    }
    function savePosition() {
        if (!readingId || view !== "reader" || readerLoading) return
        var positions = savedPositions(); positions[readingId] = readerBookmark(); prefs.progressJson = JSON.stringify(positions)
        // Avoid a synchronous rewrite of the entire fallback shelf (megabytes
        // on firmware without SQLite) on the last frame of every swipe.
        positionSyncTimer.restart()
    }
    function restoreBookmark(bookmark) {
        if (!readerModel.count) return
        var index = Math.max(0, Math.min(readerModel.count - 1,
            bookmark.character !== undefined ? Books.indexForOffset(readingBlocks, bookmark.character) : bookmark.block || 0))
        readerFlick.positionViewAtIndex(index, ListView.Beginning)
        visibleBlock = index
        Qt.callLater(function() {
            var item = readerFlick.itemAtIndex(index)
            if (item) readerFlick.contentY = Math.max(readerFlick.originY, item.y + (bookmark.offset || 0))
            updateVisibleBlock()
        })
    }
    function updateVisibleBlock() {
        if (!readerModel.count) { visibleBlock = 0; return }
        var index = readerFlick.indexAt(30, readerFlick.contentY + 8)
        if (index >= 0) visibleBlock = index
    }
    function openBook(bookId) {
        if(nativeBooks[bookId]) { openNativeBook(bookId);return }
        endSettleTimer.stop()
        readerFlick.cancelFlick()
        savePosition(); Qt.inputMethod.hide()
        readingId = bookId; view = "reader"; readerLoading = true; readingText = ""; readingBlocks = []; readerModel.clear(); chapters = []
        var token = ++readerGeneration
        if (bookId === "gutenberg:2199") {
            readingTitle = "The Iliad"; readingAuthor = "Homer · Samuel Butler"
            fetchText(Qt.resolvedUrl("../books/iliad-2199.txt"), "reader", function(text) {
                if (token === readerGeneration) prepareReader(text)
            }, function() { if (token === readerGeneration) { readerLoading = false; status = "The included book could not be opened." } })
        } else {
            var book = cachedBooks[bookId]
            if (!book) { readerLoading = false; status = "This book is not on the offline shelf."; view = "shelf"; return }
            readingTitle = book.title; readingAuthor = Books.authorFromText(book.content, book.author)
            prepareReader(book.content)
        }
    }
    function prepareReader(text) {
        readingText = Books.normalize(text)
        var headings = [], match
        if (readingId === "gutenberg:2199") {
            headings.push({title: "Introduction", offset: 0})
            var pattern = /^BOOK ([IVXLCDM]+)\.\s*$/gm
            while ((match = pattern.exec(readingText)) !== null) headings.push({title: "Book " + match[1], offset: match.index})
        }
        chapters = headings
        readingBlocks = Books.blocks(readingText, headings.map(function(h) { return h.offset }))
        for (var i = 0; i < readingBlocks.length; ++i) readerModel.append(readingBlocks[i])
        readerLoading = false
        var previous = savedPositions()[readingId] || {}
        // Keep older Iliad bookmarks useful after switching to continuous text.
        if (previous.version !== 2 && previous.section)
            previous = {character: chapters[previous.section] ? chapters[previous.section].offset : Books.legacyOffset(readingText, previous.section), offset: previous.scrollY || 0}
        restoreBookmark(previous)
        status = "Saved offline · " + readingAuthor
    }
    function chapterAt(block) {
        var offset = readingBlocks.length ? readingBlocks[Math.min(block, readingBlocks.length - 1)].offset : 0
        var result = 0
        for (var i = 0; i < chapters.length; ++i) if (chapters[i].offset <= offset) result = i
        return result
    }
    function changeChapter(delta) {
        endSettleTimer.stop()
        var next = currentChapter + delta
        if (next < 0 || next >= chapters.length) return
        restoreBookmark({character: chapters[next].offset, offset: 0}); savePosition()
    }
    function setReaderFont(value) {
        endSettleTimer.stop()
        readerFlick.cancelFlick()
        var size = Math.max(14, Math.min(36, Math.round(value)))
        if (size === prefs.readerFont) return
        var bookmark = readerBookmark(), ratio = size / prefs.readerFont
        bookmark.offset *= ratio; prefs.readerFont = size; pendingFont = size
        Qt.callLater(function() { restoreBookmark(bookmark); savePosition() })
    }
    function readerTop() { endSettleTimer.stop(); restoreBookmark({character: 0, offset: 0}); savePosition() }
    function readerEnd() {
        readerFlick.forceLayout()
        readerFlick.positionViewAtEnd()
        visibleBlock = Math.max(0, readerModel.count - 1)
        endSettleTimer.attempts = 0
        endSettleTimer.restart()
    }
    function logTestTargets(item) {
        if (!testSettings.booksTrace || !item.visible) return
        if (item.objectName && item.objectName.indexOf("books") === 0 && item.mapToItem && item.width > 0 && item.height > 0) {
            var point = item.mapToItem(null, item.width / 2, item.height / 2), clipped = false, parentItem = item.parent
            while (parentItem) {
                if (parentItem.clip) { var local = item.mapToItem(parentItem, item.width / 2, item.height / 2); if (local.y < 0 || local.y > parentItem.height || local.x < 0 || local.x > parentItem.width) clipped = true }
                parentItem = parentItem.parent
            }
            if (!clipped && point.x > 0 && point.x < root.width && point.y > 0 && point.y < root.height)
                console.log("PaperBooks target", item.objectName, Math.round(point.x), Math.round(point.y), item.enabled, item.checked === undefined ? "" : item.checked)
        }
        if (item.children) for (var i = 0; i < item.children.length; ++i) logTestTargets(item.children[i])
    }

    Timer { id: positionSyncTimer; interval: 1200; onTriggered: root.syncPrefs() }
    Timer { id: arxivDelay; property var resume: null; onTriggered: if (resume) resume() }
    Timer { interval: 900; repeat: true; running: root.nativeJob !== null; onTriggered: root.pollNativeDownload() }
    Connections {
        target: root.nativeBridge ? root.nativeBridge.importer : null
        ignoreUnknownSignals: true
        function onImported(document, collection, source) { root.nativeImported(document,collection,source) }
        function onFailed(source) {
            if(!root.nativeJob || !root.pendingNativePath)return
            if(!source || decodeURIComponent(String(source)) !== "file://"+root.pendingNativePath)return
            root.status="The native reader could not import this file. Nothing on your shelf was replaced."
            var token=root.nativeJob.token
            root.nativeJob=null;root.pendingNativePath="";root.downloadingId=""
            AppLoadLauncher.launchApplication("external::paperbooks-download",["--clean",token],{},false)
        }
    }
    Connections {
        target: root.nativeBridge ? root.nativeBridge.lib : null
        ignoreUnknownSignals: true
        function onEntryAdded(entryId) { root.noteNativeEntry(entryId) }
        function onEntryImported(entryId,visibleName,errorMessage) { if(!errorMessage)root.noteNativeEntry(entryId) }
    }
    Timer {
        interval: 1000; repeat: true; running: root.requests.length > 0
        onTriggered: {
            var pending = root.requests.slice()
            for (var i = 0; i < pending.length; ++i) if (Date.now() - pending[i].started > 45000) pending[i].cancel("The request timed out. Please try again.")
        }
    }
    // ListView refines its estimated heights when the final text blocks load.
    // Settle for a few frames so End reaches the actual bottom on the tablet.
    Timer {
        id: endSettleTimer
        interval: 80; repeat: true
        property int attempts: 0
        onTriggered: {
            var settled = readerFlick.atYEnd
            readerFlick.forceLayout()
            readerFlick.positionViewAtEnd()
            ++attempts
            if ((attempts >= 3 && settled && readerFlick.atYEnd) || attempts >= 8) {
                stop()
                root.visibleBlock = Math.max(0, readerModel.count - 1)
                root.savePosition()
            }
        }
    }
    Timer {
        interval: 700; repeat: true; running: testSettings.booksTrace
        onTriggered: {
            var state = JSON.stringify({view: root.view, languages: prefs.preferredLanguages, sources: prefs.preferredSources, font: prefs.readerFont,
                readerId: root.readingId, chapter: root.currentChapter,
                renderedTail: readerFlick.itemAtIndex(readerModel.count - 1) ? readerFlick.itemAtIndex(readerModel.count - 1).text.slice(-120) : "",
                resultSummary: root.searchRows.slice(0, 6).map(function(b) { return {id: b.bookId, source: b.bookSource, author: b.bookAuthor, saved: root.isSaved(b.bookId)} }),
                length: root.readingText.length, sample: root.readingText.slice(0, 90), tail: root.readingText.slice(-90),
                blocks: readerModel.count, block: root.visibleBlock, scroll: Math.round(readerFlick.contentY),
                end: readerFlick.atYEnd, readerBottom: Math.round(readerFlick.mapToItem(root, 0, readerFlick.height).y), shelf: shelfModel.count, results: searchModel.count,
                searching: root.searching, downloading: root.downloadingId, deleting: root.deleteId,
                searchScroll: Math.round(searchList.contentY), shelfScroll: Math.round(shelfList.contentY),
                searchAnchor: searchList.indexAt(20, searchList.contentY + 20),
                sort: prefs.searchSort, sortOpen: root.sortExpanded, status: root.status})
            // Hidden views are laid out on the next frame. Keep geometry fresh
            // even when logical state did not change, so physical tests never
            // tap coordinates captured before a view's first layout pass.
            console.log("PaperBooks state", state)
            root.logTestTargets(root)
        }
    }

    ColumnLayout {
        id: booksContent
        objectName: "booksContent"
        enabled: root.initialized && root.deleteId === ""
        anchors.fill: parent
        anchors.margins: 22
        anchors.bottomMargin: 22 + root.keyboardInset
        spacing: 12

        Rectangle {
            objectName: "booksHeader"
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            color: "black"
            radius: 8
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                Column {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    spacing: 2
                    Text { text: "PAPERDESK  /  OFFLINE LIBRARY"; color: "white"; font.pointSize: 10; font.bold: true; font.letterSpacing: 2 }
                    Text { text: "Books"; color: "white"; font.pointSize: 25; font.bold: true }
                }
                ActionButton {
                    objectName: "booksCloseButton"
                    label: "Close"
                    Layout.preferredWidth: 176
                    Layout.preferredHeight: 76
                    onTriggered: { root.savePosition(); root.close() }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ActionButton { objectName: "booksShelfTab"; label: "Offline shelf"; primary: root.view === "shelf"; Layout.fillWidth: true; onTriggered: root.switchView("shelf") }
            ActionButton { objectName: "booksSearchTab"; label: "Find books"; primary: root.view === "search"; Layout.fillWidth: true; onTriggered: root.switchView("search") }
            ActionButton { objectName: "booksSettingsTab"; label: "Settings"; primary: root.view === "settings"; Layout.fillWidth: true; onTriggered: root.switchView("settings") }
        }

        ColumnLayout {
            visible: root.view === "shelf"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Your books"; font.pointSize: 20; font.bold: true; Layout.fillWidth: true }
                Text { text: shelfModel.count + (shelfModel.count === 1 ? " title" : " titles"); font.pointSize: 15 }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: shelfHint.implicitHeight
                Layout.maximumHeight: shelfHint.implicitHeight
                Text { id: shelfHint; anchors.left: parent.left; anchors.right: parent.right; text: "Tap a title to read. PDF and EPUB editions open in the tablet’s built-in reader."; font.pointSize: 15; color: "black"; wrapMode: Text.WordWrap }
            }
            ListView {
                id: shelfList
                objectName: "booksOfflineShelf"
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: shelfModel
                reuseItems: true
                cacheBuffer: height
                maximumFlickVelocity: 2000
                flickDeceleration: 3000
                boundsBehavior: Flickable.StopAtBounds
                spacing: 12
                clip: true
                delegate: Rectangle {
                    width: shelfList.width
                    height: 154
                    radius: 8
                    color: "white"
                    border.color: "black"
                    border.width: 2
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16
                        Item {
                            objectName: "booksOpen_" + bookId
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Text { text: bookTitle; textFormat:Text.PlainText; width: parent.width; font.pointSize: 18; font.bold: true; elide: Text.ElideRight }
                                Text { text: bookAuthor; textFormat:Text.PlainText; width: parent.width; font.pointSize: 15; elide: Text.ElideRight }
                                Text { text: ((root.nativeBooks[bookId] || {}).pending ? "Check import in My files" : fileFormat === "text" ? "Saved offline" : fileFormat.toUpperCase()+" · My files") + "  ·  " + bookLanguage.toUpperCase() + "  ·  " + Catalogues.name(bookId); textFormat:Text.PlainText; font.pointSize: 14; color: "black" }
                            }
                            TapHandler { onTapped: root.openBook(bookId) }
                        }
                        ActionButton {
                            objectName: "booksDelete_" + bookId
                            label: fileFormat === "text" ? "Delete" : "Remove"
                            Layout.preferredWidth: 176
                            onTriggered: root.requestDelete(bookId, bookTitle)
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: shelfModel.count === 0
                    width: parent.width - 80
                    text: "Your shelf is empty.\nFind a book and tap its title to save it offline."
                    font.pointSize: 17
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            visible: root.view === "search"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                TextField {
                    id: searchInput
                    objectName: "booksSearchInput"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    font.pointSize: 17
                    placeholderText: "Title, author or research topic"
                    placeholderTextColor: "#555555"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    color: "black"
                    leftPadding: 18
                    background: Rectangle { radius: 8; color: "white"; border.width: 2; border.color: "black" }
                    onAccepted: root.searchBooks()
                    onActiveFocusChanged: if (activeFocus) { root.sortExpanded = false; Qt.inputMethod.show() }
                }
                ActionButton { objectName: "booksSearchButton"; label: root.searching ? "Stop" : "Search"; Layout.preferredWidth: 176; Layout.preferredHeight: 76; onTriggered: { if (root.searching) { ++root.searchGeneration; root.cancelRequests("search"); root.searching = false; root.status = "Search stopped." } else root.searchBooks() } }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Sort by"; font.pointSize: 15; font.bold: true; Layout.alignment: Qt.AlignTop; Layout.topMargin: 20 }
                Item {
                    id: sortPicker
                    objectName: "booksSortPicker"
                    Layout.preferredWidth: 360
                    Layout.preferredHeight: root.sortExpanded ? 332 : 76
                    ActionButton {
                        objectName: "booksSortPickerButton"
                        width: parent.width
                        height: 76
                        label: root.sortCaption
                        onTriggered: { Qt.inputMethod.hide(); root.sortExpanded = !root.sortExpanded }
                        Canvas {
                            id: sortChevron
                            property string arrowInk: Qt.colorEqual(parent.color, "black") ? "white" : "black"
                            onArrowInkChanged: requestPaint()
                            width: 20; height: 12
                            anchors.right: parent.right; anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = arrowInk; ctx.lineWidth = 3; ctx.lineJoin = "round"
                                ctx.beginPath()
                                ctx.moveTo(2, root.sortExpanded ? 10 : 2)
                                ctx.lineTo(10, root.sortExpanded ? 2 : 10)
                                ctx.lineTo(18, root.sortExpanded ? 10 : 2)
                                ctx.stroke()
                            }
                            Connections { target: root; function onSortExpandedChanged() { sortChevron.requestPaint() } }
                        }
                    }
                    // Expand in the layout rather than opening a native popup:
                    // large e-ink touch targets, no clipped or hidden overlay.
                    Rectangle {
                        visible: root.sortExpanded
                        y: 84; width: parent.width; height: 248
                        radius: 8; color: "white"; border.width: 2; border.color: "black"
                        Column {
                            anchors.fill: parent; anchors.margins: 6; spacing: 4
                            Repeater {
                                model: root.sortOptions
                                delegate: ActionButton {
                                    objectName: modelData.target
                                    width: parent.width; height: 76
                                    label: modelData.title
                                    primary: prefs.searchSort === modelData.code
                                    onTriggered: root.setSearchSort(modelData.code)
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Text { objectName: "booksSearchScope"; text: root.sourceSummary() + "  ·  " + prefs.preferredLanguages.toUpperCase(); font.pointSize: 15; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "black" }
            ListView {
                id: searchList
                objectName: "booksSearchResults"
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: searchModel
                reuseItems: true
                cacheBuffer: height
                maximumFlickVelocity: 2000
                flickDeceleration: 3000
                boundsBehavior: Flickable.StopAtBounds
                spacing: 12
                clip: true
                delegate: Rectangle {
                    objectName: "booksResult_" + bookId
                    width: searchList.width
                    height: Math.max(204, resultContents.implicitHeight + 40)
                    radius: 8
                    color: resultTap.pressed ? "#eeeeee" : "white"
                    border.width: 2
                    border.color: "black"
                    Column {
                        id: resultContents
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 20
                        spacing: 9
                        Text { objectName: "booksResultTitle_" + bookId; text: bookTitle; textFormat: Text.PlainText; width: parent.width; font.pointSize: 20; font.bold: true; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; color: "black" }
                        Text { text: bookAuthor; textFormat: Text.PlainText; width: parent.width; font.pointSize: 15; elide: Text.ElideRight; color: "black" }
                        Text { objectName: "booksResultSource_" + bookId; text: bookSource + "  ·  " + bookLanguage.toUpperCase() + (bookId.indexOf("europepmc:") === 0 ? "  ·  Open Access" : ""); width: parent.width; font.pointSize: 15; font.bold: true; elide: Text.ElideRight; color: "black" }
                        Text { text: root.downloadingId === bookId ? "Downloading…" : fileFormat !== "text" ? (savedOffline ? "Added to My files  ·  Native reader" : "Tap to add " + (fileFormat === "native" ? "PDF / EPUB" : fileFormat.toUpperCase()) + " to My files") : savedOffline ? "Saved offline  ·  Tap to read" : "Tap to save offline"; font.pointSize: 14; color: "black" }
                    }
                    TapHandler { id: resultTap; onTapped: { root.sortExpanded = false; root.selectSearchBook(bookId, bookTitle, bookAuthor, bookLanguage, downloadUrl) } }
                }
                footer: Item {
                    width: searchList.width
                    height: root.searchPages.length ? 92 : 0
                    ActionButton { objectName: "booksLoadMore"; visible: root.searchPages.length > 0; anchors.centerIn: parent; width: 320; label: "Load more"; available: !root.searching; onTriggered: root.loadMore() }
                }
                Text { anchors.centerIn: parent; width: parent.width - 80; visible: !root.searching && searchModel.count === 0; text: root.searched ? "No matching titles in the selected services and languages.\nTry another search or change Settings." : "Books and open-access research.\nSearch by title, author or topic."; font.pointSize: 18; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
            }
        }

        Flickable {
            objectName: "booksSettingsPage"
            visible: root.view === "settings"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: settingsContents.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
            id: settingsContents
            width: parent.width
            spacing: 18
            Text { text: "Search services"; font.pointSize: 22; font.bold: true; Layout.fillWidth: true }
            Text { text: "Choose where to look. All services are free; no account or subscription."; font.pointSize: 15; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Repeater {
                model: root.sourceOptions
                delegate: SelectionTile {
                    objectName: "booksSource_" + modelData.code
                    Layout.fillWidth: true
                    title: modelData.title
                    detail: modelData.detail
                    checked: root.supportedSource(modelData.code)
                    onToggled: root.setSource(modelData.code, !checked)
                }
            }
            Text { text: "PDF and EPUB editions are added to My files for the built-in reader, keeping figures, formulae and original attribution. Gutenberg and Europe PMC use the Books text reader. Maximum download: 256 MB. No DRM or restricted loans."; font.pointSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "black" }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 2; color: "black" }
            Text { text: "Preferred search languages"; font.pointSize: 21; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Text { text: "Search results can use any selected language."; font.pointSize: 15; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 16
                Repeater {
                    model: root.languageOptions
                    delegate: SelectionTile {
                        objectName: "booksLanguage_" + modelData.code
                        checked: root.supportedLang(modelData.code)
                        title: modelData.title
                        Layout.fillWidth: true
                        Layout.preferredHeight: 108
                        onToggled: root.setLanguage(modelData.code, !checked)
                    }
                }
            }
            Text { text: "Saved on this tablet. Keep at least one service and one language selected."; font.pointSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "black" }
            ActionButton { objectName: "booksRestoreIliad"; visible: prefs.iliadHidden; label: "Restore included Iliad"; Layout.preferredWidth: 420; onTriggered: { prefs.iliadHidden = false; root.syncPrefs(); root.loadShelf(); root.status = "The Iliad is back on your offline shelf." } }
            }
        }

        ColumnLayout {
            visible: root.view === "reader"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ActionButton { objectName: "booksReaderBack"; label: "← Shelf"; Layout.preferredWidth: 176; onTriggered: root.switchView("shelf") }
                Column {
                    Layout.fillWidth: true
                    spacing: 4
                    Text { width: parent.width; text: root.readingTitle; font.pointSize: 18; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.readingAuthor; font.pointSize: 11; elide: Text.ElideRight }
                }
                ActionButton { objectName: "booksFontSmaller"; label: "A−"; Layout.preferredWidth: 102; available: prefs.readerFont > 14; onTriggered: root.setReaderFont(prefs.readerFont - 2) }
                ActionButton { objectName: "booksFontLarger"; label: "A+"; Layout.preferredWidth: 102; available: prefs.readerFont < 36; onTriggered: root.setReaderFont(prefs.readerFont + 2) }
            }
            RowLayout {
                visible: root.chapters.length > 1
                Layout.fillWidth: true
                ActionButton { objectName: "booksPreviousChapter"; label: "← Previous"; available: root.currentChapter > 0; onTriggered: root.changeChapter(-1) }
                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: root.chapters.length ? root.chapters[root.currentChapter].title : ""; font.pointSize: 12; font.bold: true }
                ActionButton { objectName: "booksNextChapter"; label: "Next →"; available: root.currentChapter + 1 < root.chapters.length; onTriggered: root.changeChapter(1) }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "white"
                border.color: "#aaaaaa"
                border.width: 1
                ListView {
                    id: readerFlick
                    objectName: "booksReaderPages"
                    anchors.fill: parent
                    anchors.margins: 20
                    model: readerModel
                    clip: true
                    interactive: false
                    maximumFlickVelocity: 1800
                    flickDeceleration: 3200
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: Math.max(0, height)
                    reuseItems: true
                    onContentYChanged: root.updateVisibleBlock()
                    onMovementEnded: root.savePosition()
                    delegate: Text {
                        objectName: "booksReaderBlock_" + index
                        width: readerFlick.width
                        text: body
                        font.pointSize: prefs.readerFont
                        color: "black"
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        lineHeight: 1.24
                        topPadding: 0
                        bottomPadding: 0
                    }
                }
                Text { anchors.centerIn: parent; visible: root.readerLoading; text: "Opening book…"; font.pointSize: 18 }
                Text { anchors.centerIn: parent; width: parent.width - 60; visible: !root.readerLoading && readerModel.count === 0; text: root.status; textFormat: Text.PlainText; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; font.pointSize: 18; color: "black" }
                MultiPointTouchArea {
                    id: readerTouch
                    objectName: "booksReaderTouch"
                    anchors.fill: readerFlick
                    enabled: !root.readerLoading && readerModel.count > 0
                    z: 5
                    minimumTouchPoints: 1
                    maximumTouchPoints: 2
                    property var pointsById: ({})
                    property int activePoint: -1
                    property real pressY: 0
                    property real startContentY: 0
                    property real lastY: 0
                    property real lastTime: 0
                    property real releaseVelocity: 0
                    property bool pinchActive: false
                    property bool suppressDrag: false
                    property real startDistance: 1
                    property real startFont: 21
                    function remember(points) { for (var i = 0; i < points.length; ++i) pointsById[points[i].pointId] = {x: points[i].x, y: points[i].y} }
                    function distance() { var ids = Object.keys(pointsById); if (ids.length < 2) return 1; var a = pointsById[ids[0]], b = pointsById[ids[1]]; return Math.sqrt(Math.pow(a.x - b.x, 2) + Math.pow(a.y - b.y, 2)) }
                    function finishPinch() {
                        if (!pinchActive) return
                        pinchActive = false
                        root.setReaderFont(root.pendingFont)
                        if (testSettings.booksTrace) console.log("PaperBooks pinch", prefs.readerFont)
                    }
                    onPressed: function(points) {
                        endSettleTimer.stop()
                        readerFlick.cancelFlick()
                        remember(points)
                        if (Object.keys(pointsById).length >= 2) {
                            pinchActive = true; suppressDrag = true; activePoint = -1
                            startDistance = Math.max(1, distance()); startFont = prefs.readerFont; root.pendingFont = startFont
                        } else if (points.length) {
                            activePoint = points[0].pointId; pressY = points[0].y; startContentY = readerFlick.contentY; suppressDrag = false
                            lastY = pressY; lastTime = Date.now(); releaseVelocity = 0
                        }
                    }
                    onUpdated: function(points) {
                        remember(points)
                        if (pinchActive) { root.pendingFont = Math.max(14, Math.min(36, Math.round(startFont * distance() / startDistance))); return }
                        if (suppressDrag) return
                        for (var i = 0; i < points.length; ++i) if (points[i].pointId === activePoint) {
                            var bottom = readerFlick.originY + Math.max(0, readerFlick.contentHeight - readerFlick.height)
                            var now = Date.now(), delta = points[i].y - lastY
                            if (now > lastTime) releaseVelocity = releaseVelocity * 0.35 + delta * 650 / Math.max(8, now - lastTime)
                            readerFlick.contentY = Math.max(readerFlick.originY, Math.min(bottom, readerFlick.contentY - delta))
                            lastY = points[i].y; lastTime = now
                        }
                    }
                    onReleased: function(points) {
                        var wasPinch = pinchActive || suppressDrag
                        remember(points); finishPinch()
                        for (var i = 0; i < points.length; ++i) delete pointsById[points[i].pointId]
                        if (!Object.keys(pointsById).length) {
                            activePoint = -1; suppressDrag = false
                            if (!wasPinch && Date.now() - lastTime < 100 && Math.abs(releaseVelocity) > 100)
                                readerFlick.flick(0, Math.max(-1800, Math.min(1800, releaseVelocity)))
                            else root.savePosition()
                        }
                    }
                    onCanceled: function(points) { finishPinch(); pointsById = ({}); activePoint = -1; suppressDrag = false }
                }
            }
        }

        Rectangle {
            objectName: "booksStatusBar"
            visible: root.view !== "reader"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(76, statusContents.implicitHeight + 24)
            color: "white"
            border.color: "black"
            border.width: 1
            RowLayout {
                id: statusContents
                anchors.fill: parent;anchors.margins:12;spacing:12
                Text { Layout.fillWidth:true; text:root.status; textFormat:Text.PlainText; font.pointSize:15; wrapMode:Text.WordWrap; maximumLineCount:3; elide:Text.ElideRight; color:"black" }
                ActionButton { objectName:"booksCancelDownload"; visible:root.nativeJob!==null && !root.pendingNativePath; label:"Cancel"; onTriggered:root.cancelNativeDownload() }
                ActionButton { objectName:"booksOpenNative"; visible:!!root.lastNativeId && !root.nativeJob; label:"Close Books"; onTriggered:root.close() }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.deleteId !== ""
        z: 100
        color: "white"
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(1000, parent.width - 100)
            height: 440
            radius: 10
            color: "white"
            border.color: "black"
            border.width: 3
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 20
                Text { text: root.nativeBooks[root.deleteId] ? "Remove shortcut from Books?" : "Delete from offline shelf?"; font.pointSize: 22; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Text { visible: !!root.nativeBooks[root.deleteId]; text: "The original document and your annotations in My files will not be deleted."; font.pointSize: 17; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Text { text: root.deleteTitle; textFormat:Text.PlainText; font.pointSize: 18; Layout.fillWidth: true; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                Text { visible:!root.nativeBooks[root.deleteId]; text: root.deleteId === "gutenberg:2199" ? "You can restore the included Iliad in Settings." : "The book and its reading position will be removed from this tablet."; font.pointSize: 15; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    ActionButton { objectName: "booksDeleteCancel"; label: "Cancel"; onTriggered: root.deleteId = "" }
                    ActionButton { objectName: "booksDeleteConfirm"; label: root.nativeBooks[root.deleteId] ? "Remove" : "Delete"; primary: true; onTriggered: { try { root.deleteBook(root.deleteId) } catch (error) { root.deleteId = ""; root.status = "Could not delete this book. Please try again." } } }
                }
            }
        }
    }
    DisplayMethodArea { anchors.fill: parent; displayMethod: DisplayMethodArea.Fast; z: -1 }
    // Let Settings finish loading every property before migrations or sync.
    // Parent/child Component.onCompleted ordering is not defined by QML.
    Component.onCompleted: Qt.callLater(function() {
        if (root.disposed) return
        initialize()
        if (testSettings.booksTrace && testSettings.booksQuery) searchInput.text = testSettings.booksQuery
    })
}
