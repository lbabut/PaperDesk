import QtQuick 2.15
import QtTest 1.3

Item {
    id: scene
    width: 1404
    height: 1872
    TestCase {
        id: testCase
        name: "PaperBooks"
        when: windowShown
        function makeApp() {
            var component = Qt.createComponent("../../product/payload/apps/paperbooks/ui/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            var app = createTemporaryObject(component, scene)
            verify(app !== null)
            tryVerify(function(){return app.initialized})
            var prefs = findChild(app, "booksPreferences")
            prefs.preferredLanguages = "pl,en,no"
            prefs.preferredSources = "gutenberg,europepmc"
            prefs.nativeBooksJson = "{}"
            app.nativeBooks = ({})
            prefs.offlineBooksJson = "{}"
            prefs.bookMetadataJson = "{}"
            prefs.progressJson = "{}"
            prefs.iliadHidden = false
            prefs.readerFont = 21
            prefs.searchSort = "title"
            app.loadShelf()
            waitForRendering(app)
            return app
        }
        function tap(app, name) {
            var item = null
            tryVerify(function() { item = findChild(app, name); return item !== null }, 1000, name)
            verify(item.visible && item.enabled, name + " must be usable")
            var settings=findChild(app,"booksSettingsPage")
            if(app.view === "settings") {
                var top=item.mapToItem(settings,0,0).y
                if(top<0 || top+item.height>settings.height) {
                    settings.contentY=Math.max(0,Math.min(settings.contentHeight-settings.height,settings.contentY+top-20))
                    wait(50)
                }
            }
            mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton)
            wait(40)
        }
        function sampleText() {
            var text = "Author: Example Writer\n\n"
            for (var i = 0; i < 1200; ++i) text += i % 9 === 0 ? "A longer paragraph with varied text and Polish letters: żółć. ".repeat(45) + "\n\n" : "Short paragraph " + i + ".\n\n"
            return text + "LAST STORY SENTENCE.\n*** END OF THE PROJECT GUTENBERG EBOOK TEST ***\n"
        }
        function fixtureBook(app) {
            var text = sampleText()
            app.persistDownloadedBook("fixture", "A complete test book", "Example Writer", "pl", text)
            app.loadShelf()
            return text
        }
        function test_largeLanguageTilesAndLastSelection() {
            var app = makeApp()
            app.switchView("settings")
            var codes = ["pl", "no", "de", "fr", "es", "it", "pt"]
            app.setLanguage("en", true)
            for (var i = 0; i < codes.length; ++i) app.setLanguage(codes[i], false)
            waitForRendering(app)
            var english = findChild(app, "booksLanguage_en")
            verify(english.width > 500 && english.height >= 100)
            compare(english.checked, true)
            tap(app, "booksLanguage_en")
            compare(english.checked, true)
            tap(app, "booksLanguage_de")
            verify(app.supportedLang("de"))
            tap(app, "booksLanguage_de")
            verify(!app.supportedLang("de"))
        }
        function test_sourceTilesLastSelectionAndVectorChecks() {
            var app = makeApp()
            app.switchView("settings")
            waitForRendering(app)
            tap(app, "booksSource_gutenberg")
            verify(!app.supportedSource("gutenberg"))
            tap(app, "booksSource_europepmc")
            verify(app.supportedSource("europepmc"), "Last service must stay selected")
            tap(app, "booksSource_gutenberg")
            verify(app.supportedSource("gutenberg"))
            var mark = findChild(app, "booksLanguage_enMark")
            verify(mark !== null && mark.width === 42 && mark.height === 42)
            verify(findChild(app, "booksSource_europepmcMark") !== null)
            verify(findChild(app, "booksSettingsPage").contentHeight > 800)
        }
        function test_allSixSourcesCanBeSelectedWithRealClicks() {
            var app=makeApp();app.switchView("settings");waitForRendering(app)
            var sources=["wolnelektury","openstax","arxiv","openlibrary"]
            for(var i=0;i<sources.length;++i) {
                verify(!app.supportedSource(sources[i]))
                tap(app,"booksSource_"+sources[i]);verify(app.supportedSource(sources[i]))
                verify(app.sourceSummary().length>10)
            }
            for(var j=0;j<sources.length;++j) {tap(app,"booksSource_"+sources[j]);verify(!app.supportedSource(sources[j]))}
            compare(findChild(app,"booksPreferences").preferredSources,"gutenberg,europepmc")
        }
        function test_nativeResultExplainsWhereTheBookWillGo() {
            var app=makeApp()
            app.searchRows=[{bookId:"arxiv:2601.12345",bookTitle:"Quantum physics",bookAuthor:"A Scientist",bookLanguage:"en",bookSource:"arXiv · preprint",format:"pdf",downloadUrl:"https://arxiv.org/pdf/2601.12345",catalogueId:0}]
            app.renderSearchResults();app.switchView("search");waitForRendering(app)
            var source=findChild(app,"booksResultSource_arxiv:2601.12345")
            verify(source!==null);verify(source.text.indexOf("preprint")>=0)
            app.selectSearchBook("arxiv:2601.12345","Quantum physics","A Scientist","en","https://arxiv.org/pdf/2601.12345")
            verify(app.status.indexOf("unavailable")>=0,"Unsupported host must fail gracefully, not pretend to import")
            compare(app.downloadingId,"")
        }
        function test_resultsShowSourceAndReadableLongTitles() {
            var app = makeApp()
            app.searchRows = [{bookId: "europepmc:PMC123", bookTitle: "A long research title ".repeat(9), bookAuthor: "Example Scientist", bookLanguage: "en", bookSource: "Europe PMC", downloadUrl: "https://www.ebi.ac.uk/europepmc/webservices/rest/PMC123/fullTextXML", catalogueId: 123}]
            app.renderSearchResults(); app.switchView("search")
            waitForRendering(app); wait(50)
            var source = findChild(app, "booksResultSource_europepmc:PMC123")
            verify(source !== null && source.text.indexOf("Europe PMC") >= 0)
            verify(source.font.pointSize >= 15)
            var title = findChild(app, "booksResultTitle_europepmc:PMC123")
            compare(title.maximumLineCount, 2)
            verify(title.font.pointSize >= 20)
            var row = findChild(app, "booksResult_europepmc:PMC123")
            verify(row.height >= 204)
        }
        function test_saving_offline_preserves_search_list_position_and_delegate() {
            var app = makeApp(), rows = []
            for (var i = 0; i < 35; ++i) rows.push({bookId: "fixture:" + i, bookTitle: "Book " + (100 + i),
                bookAuthor: "Author", bookLanguage: "en", bookSource: "Fixture", downloadUrl: "https://example.test/a", catalogueId: i})
            app.searchRows = rows; app.renderSearchResults(); app.switchView("search")
            var list = findChild(app, "booksSearchResults")
            list.positionViewAtIndex(18, ListView.Beginning); list.forceLayout(); wait(80)
            var before = list.contentY, delegate = list.itemAtIndex(18)
            verify(before > 1000 && delegate !== null)
            app.persistDownloadedBook("fixture:18", "Book 118", "Author", "en", "Book text. ".repeat(80))
            app.loadShelf(); wait(80)
            compare(list.itemAtIndex(18), delegate, "Save must not destroy result delegates")
            verify(Math.abs(list.contentY - before) < 2, "Save must keep the same viewport")
            app.renderSearchResults(); wait(30)
            verify(Math.abs(list.contentY - before) < 2)
        }
        function test_titleOpensContinuousBookAndReachesActualEnd() {
            var app = makeApp(), text = fixtureBook(app)
            tap(app, "booksOpen_fixture")
            compare(app.view, "reader")
            compare(app.readingText, text)
            verify(app.readingBlocks.length > 50)
            var reader = findChild(app, "booksReaderPages")
            verify(reader.count > 50)
            app.readerEnd() // Internal end-of-text regression; there is no footer button.
            tryCompare(reader, "atYEnd", true)
            var last = findChild(app, "booksReaderBlock_" + (reader.count - 1))
            verify(last !== null)
            verify(last.text.indexOf("LAST STORY SENTENCE") >= 0)
            app.savePosition()
            tap(app, "booksReaderBack")
            tap(app, "booksOpen_fixture")
            tryVerify(function() { return app.visibleBlock > app.readingBlocks.length - 5 })
        }
        function test_deleteCancelConfirmAndBundledRestore() {
            var app = makeApp()
            fixtureBook(app)
            compare(findChild(app, "booksOfflineShelf").count, 2)
            tap(app, "booksDelete_fixture")
            tap(app, "booksDeleteCancel")
            verify(app.isSaved("fixture"))
            tap(app, "booksDelete_fixture")
            tap(app, "booksDeleteConfirm")
            verify(!app.isSaved("fixture"))
            compare(findChild(app, "booksOfflineShelf").count, 1)
            tap(app, "booksDelete_gutenberg:2199")
            tap(app, "booksDeleteConfirm")
            compare(findChild(app, "booksOfflineShelf").count, 0)
            app.switchView("settings")
            wait(40)
            tap(app, "booksRestoreIliad")
            verify(app.isSaved("gutenberg:2199"))
        }
        function test_readerHasNoFooterAndTextUsesBottomSpace() {
            var app = makeApp()
            fixtureBook(app)
            verify(findChild(app, "booksStatusBar").visible)
            tap(app, "booksOpen_fixture")
            waitForRendering(app)
            wait(60)
            verify(findChild(app, "booksReaderTop") === null)
            verify(findChild(app, "booksReaderEnd") === null)
            verify(!findChild(app, "booksStatusBar").visible)
            var reader = findChild(app, "booksReaderPages")
            verify(reader.mapToItem(app, 0, reader.height).y >= app.height - 44,
                   "Book text should use the space freed by both bottom bars")
            tap(app, "booksReaderBack")
            verify(findChild(app, "booksStatusBar").visible)
        }
        function test_modalCancelDoesNotOpenUnderlyingBook() {
            var app = makeApp()
            for (var i = 0; i < 4; ++i)
                app.persistDownloadedBook("modal-" + i, "Modal book " + i, "Writer", "en", "Example text. ".repeat(80))
            app.loadShelf()
            waitForRendering(app)
            app.requestDelete("modal-0", "Modal book 0")
            verify(!findChild(app, "booksContent").enabled)
            wait(40)
            tap(app, "booksDeleteCancel")
            compare(app.view, "shelf")
            compare(app.readingId, "")
            verify(findChild(app, "booksContent").enabled)
        }
        function test_searchRowsShowAuthorSavedStateAndSort() {
            var app = makeApp()
            fixtureBook(app)
            app.searchRows = [
                {bookId: "gutenberg:8119", bookTitle: "Sklepy cynamonowe", bookAuthor: "Bruno Schulz", bookLanguage: "pl", catalogueId: 8119, published: "", downloadUrl: "https://example.test/book"},
                {bookId: "fixture", bookTitle: "A complete test book", bookAuthor: "Example Writer", bookLanguage: "pl", catalogueId: 1, published: "", downloadUrl: "https://example.test/test"}
            ]
            app.renderSearchResults()
            app.switchView("search")
            wait(40)
            tap(app, "booksSortPickerButton")
            tap(app, "booksSortAuthor")
            var list = findChild(app, "booksSearchResults")
            compare(list.model.get(0).bookAuthor, "Bruno Schulz")
            tap(app, "booksSortPickerButton")
            tap(app, "booksSortTitle")
            compare(list.model.get(0).bookTitle, "A complete test book")
            verify(list.model.get(0).savedOffline)
            tap(app, "booksResult_fixture")
            compare(app.view, "reader")
        }
        function test_sortPicklistAllChoicesCollapseAndRestore() {
            var app = makeApp()
            app.switchView("search")
            waitForRendering(app)
            wait(50)
            var picker = findChild(app, "booksSortPicker")
            compare(app.sortCaption, "Title")
            compare(app.sortExpanded, false)
            compare(picker.height, 76)
            var options = ["booksSortAuthor", "booksSortNewest", "booksSortTitle"]
            var captions = ["Author", "Newest added", "Title"]
            var codes = ["author", "newest", "title"]
            for (var i = 0; i < options.length; ++i) {
                tap(app, "booksSortPickerButton")
                compare(app.sortExpanded, true, "Open choice " + i)
                tryCompare(picker, "height", 332)
                tap(app, options[i])
                compare(app.sortExpanded, false)
                compare(app.sortCaption, captions[i])
                compare(findChild(app, "booksPreferences").searchSort, codes[i])
                tryCompare(picker, "height", 76)
            }
            tap(app, "booksSortPickerButton")
            tap(app, "booksSortPickerButton")
            compare(app.sortExpanded, false)
            tap(app, "booksSortPickerButton")
            tap(app, "booksSortTitle") // Same selection also closes without a request.
            compare(app.sortExpanded, false)
            tap(app, "booksSortPickerButton")
            app.switchView("settings")
            compare(app.sortExpanded, false)
            findChild(app, "booksPreferences").searchSort = "newest"
            app.switchView("search")
            compare(app.sortCaption, "Newest added")
        }
        function test_realTouchScrollAndPinch() {
            var app = makeApp()
            fixtureBook(app)
            app.openBook("fixture")
            waitForRendering(app)
            var area = findChild(app, "booksReaderTouch"), reader = findChild(app, "booksReaderPages")
            var touch = touchEvent(area), x = area.width / 2, y = area.height / 2
            touch.press(0, area, x, y + 200).commit()
            wait(20)
            touch.move(0, area, x, y).commit()
            wait(20)
            touch.move(0, area, x, y - 200).commit()
            touch.release(0, area, x, y - 200).commit()
            verify(reader.contentY > 100)
            verify(reader.flicking, "A quick swipe should continue briefly after release")
            var prefs = findChild(app, "booksPreferences"), original = prefs.readerFont
            var pinch = touchEvent(area)
            pinch.press(0, area, x - 100, y).press(1, area, x + 100, y).commit()
            pinch.move(0, area, x - 160, y).move(1, area, x + 160, y).commit()
            pinch.release(0, area, x - 160, y).release(1, area, x + 160, y).commit()
            tryVerify(function() { return prefs.readerFont > original })
        }
        function test_bundledIliadIsWholeAndChaptersNavigate() {
            var app = makeApp()
            app.openBook("gutenberg:2199")
            tryCompare(app, "readerLoading", false, 10000)
            verify(app.readingText.indexOf("Samuel Butler") >= 0)
            verify(app.readingText.indexOf("BOOK XXIV.") >= 0)
            verify(app.readingText.indexOf("END OF THE PROJECT GUTENBERG EBOOK") >= 0)
            compare(app.chapters.length, 25)
            waitForRendering(app)
            tap(app, "booksNextChapter")
            tryCompare(app, "currentChapter", 1)
            tap(app, "booksNextChapter")
            tryCompare(app, "currentChapter", 2)
        }
    }
}
