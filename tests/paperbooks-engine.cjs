const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const appPath = path.join(__dirname, '../product/payload/apps/paperbooks');
const Books = {};
vm.createContext(Books);
vm.runInContext(fs.readFileSync(path.join(appPath, 'books.js'), 'utf8').replace(/^\.pragma library\s*/, ''), Books);
const Catalogues={};vm.createContext(Catalogues);
vm.runInContext(fs.readFileSync(path.join(appPath,'catalogues.js'),'utf8').replace(/^\.pragma library\s*/,''),Catalogues);
const source = fs.readFileSync(path.join(appPath, 'ui/main.qml'), 'utf8');
const logic = source.slice(source.indexOf('    function safeParse('), source.indexOf('\n    Timer { id: positionSyncTimer'));
const feed = `<feed><link rel="next" href="/ebooks/search.opds/?start_index=26&amp;query=l.pl"/>
<entry><id>https://www.gutenberg.org/ebooks/8119.opds</id><title>Sklepy cynamonowe (Polish)</title><content type="text">Bruno Schulz</content></entry>
<entry><id>https://www.gutenberg.org/ebooks/11.opds</id><title>Alice &amp; friends</title><author><name>Carroll, Lewis</name></author></entry></feed>`;
const parsed = Books.parseOpds(feed, 'pl');
assert.equal(parsed.rows.length, 2);
assert.equal(parsed.rows[0].bookAuthor, 'Bruno Schulz');
assert.equal(parsed.rows[1].bookAuthor, 'Carroll, Lewis');
assert.equal(parsed.rows[1].bookTitle, 'Alice & friends');
assert.match(parsed.next, /start_index=26&query=l.pl/);
assert.equal(Books.sortRows(parsed.rows, 'title')[0].catalogueId, 11);
assert.equal(Books.sortRows(parsed.rows, 'author')[0].catalogueId, 8119);
assert.equal(Books.sortRows(parsed.rows, 'newest')[0].catalogueId, 8119);
const complete = 'The Project Gutenberg eBook of Test\r\nAuthor: Example Writer\r\n[eBook #777]\r\n\r\n' +
    'A whole paragraph with Polish letters: żółć, gęślą, jaźń. 😀\r\n\r\n'.repeat(4000) +
    'LAST STORY SENTENCE.\r\n*** END OF THE PROJECT GUTENBERG EBOOK TEST ***\r\nFull licence retained.\r\n';
const normalized = Books.normalize(complete);
const blocks = Books.blocks(complete);
assert.ok(blocks.length > 100);
assert.equal(blocks.map(b => b.body).join(''), normalized);
assert.ok(blocks.every(b => b.body.length <= 1800));
assert.match(blocks.at(-1).body, /LAST STORY SENTENCE/);
assert.equal(Books.indexForOffset(blocks, normalized.length - 1), blocks.length - 1);
assert.equal(Books.authorFromText(complete, 'Project Gutenberg'), 'Example Writer');
assert.equal(Books.validateDownload(complete, 'gutenberg:777'), '');
assert.match(Books.validateDownload(complete.slice(0, 10000), 'gutenberg:777'), /incomplete/);
assert.match(Books.validateDownload(complete, 'gutenberg:888'), /different book/);
assert.match(Books.validateDownload('<html>' + 'bad'.repeat(100) + '</html>', 'gutenberg:777'), /not a supported/);
function model() { return {rows: [], clear() {this.rows=[]}, append(row) {this.rows.push(row)},
    insert(i,row){this.rows.splice(i,0,row)}, remove(i,n){this.rows.splice(i,n)},
    move(from,to,n){this.rows.splice(to,0,...this.rows.splice(from,n))},
    setProperty(i,key,value){this.rows[i][key]=value},
    get count() {return this.rows.length}, get(i) {return this.rows[i]}}; }
let body = complete, status = 200, hung = false;
const network = [];
class XHR {
    static DONE = 4;
    open(method, url) {this.url=url; network.push(url)}
    send() {if (hung) return; this.readyState=4; this.status=status; this.responseText=this.url.includes('search.opds') ? feed : body; this.onreadystatechange?.();}
    abort() {this.aborted=true; this.readyState=4; this.status=0; this.onreadystatechange?.();}
}
function runtime(prefs) {
    const r = {
        Books, prefs: prefs || {preferredLanguages:'pl,en,no',preferredSources:'gutenberg',progressJson:'{}',offlineBooksJson:'{}',bookMetadataJson:'{}',iliadHidden:false,typographyV2:true,readerFont:21,searchSort:'title'},
        Catalogues,nativeBooks:{},catalogueCache:{},arxivLastRequest:0,nativeJob:null,nativeBridge:null,pendingNativePath:'',lastNativeId:'',pollingNative:false,
        testSettings:{booksTrace:false},AppLoadLauncher:{launchApplication(){}},
        database:null,cachedBooks:{},searchRows:[],searchPages:[],searchGeneration:0,searching:false,searched:false,
        requests:[],disposed:false,downloadingId:'',deleteId:'',deleteTitle:'',readingId:'',readingTitle:'',readingAuthor:'',readingText:'',readingBlocks:[],chapters:[],readerGeneration:0,readerLoading:false,visibleBlock:0,
        status:'',view:'shelf',shelfModel:model(),searchModel:model(),readerModel:model(),
        searchInput:{text:'sklepy'},readerFlick:{contentY:0,originY:0,cancelFlick(){},indexAt(){return 0},itemAtIndex(i){return {y:i*100}},positionViewAtIndex(i){this.contentY=i*100},positionViewAtEnd(){this.contentY=100000}},
        XMLHttpRequest:XHR,Qt:{inputMethod:{hide(){}},resolvedUrl:v=>v,callLater:f=>f(),createQmlObject(){throw new Error('No QSQLITE')}},
        endSettleTimer:{stop(){},restart(){},attempts:0},positionSyncTimer:{stop(){},restart(){}}, ListView:{Beginning:0},JSON,Date,Math,Object,Array,encodeURIComponent
    };
    r.root=r; vm.createContext(r); vm.runInContext(logic,r);r.initialize();return r;
}
const r=runtime();
assert.equal(r.shelfModel.count,1);
r.searchBooks();
assert.equal(r.searchModel.count,2);
assert.equal(r.searchModel.get(1).bookAuthor,'Bruno Schulz');
assert.ok(network.some(url=>url.includes('l.pl')));
assert.ok(network.some(url=>url.includes('l.en')));
assert.ok(network.some(url=>url.includes('l.no')));
assert.equal(r.searching,false);
r.downloadBook('gutenberg:777','Test','Project Gutenberg','pl','https://example.test/book.txt');
assert.match(r.status,/Saved offline/);
assert.equal(r.cachedBooks['gutenberg:777'].content,complete);
assert.equal(r.cachedBooks['gutenberg:777'].author,'Example Writer');
const saved=r.prefs.offlineBooksJson;
body=complete.slice(0,9000);
r.downloadBook('gutenberg:777','Test','Someone','pl','https://example.test/book.txt');
assert.match(r.status,/incomplete/);
assert.equal(r.prefs.offlineBooksJson,saved,'An incomplete retry must not overwrite a complete saved book');
status=206;body=complete;
r.downloadBook('gutenberg:777','Test','Someone','pl','https://example.test/book.txt');
assert.equal(r.prefs.offlineBooksJson,saved);
status=200;
const reopened=runtime(r.prefs);
reopened.openBook('gutenberg:777');
assert.equal(reopened.readingText,normalized);
assert.equal(reopened.readerModel.count,blocks.length);
assert.equal(reopened.readerModel.rows.map(b=>b.body).join(''),normalized);
reopened.deleteBook('gutenberg:777');
assert.equal(reopened.shelfModel.count,1);
assert.equal(reopened.isSaved('gutenberg:777'),false);
const afterDelete=runtime(r.prefs);
assert.equal(afterDelete.isSaved('gutenberg:777'),false);
afterDelete.deleteBook('gutenberg:2199');
assert.equal(afterDelete.shelfModel.count,0);
assert.equal(runtime(r.prefs).shelfModel.count,0,'A deleted bundled title must stay hidden after restart');
afterDelete.prefs.preferredLanguages='en';afterDelete.setLanguage('en',false);assert.equal(afterDelete.prefs.preferredLanguages,'en');
afterDelete.setSource('gutenberg',false);assert.equal(afterDelete.prefs.preferredSources,'gutenberg');
afterDelete.setSource('europepmc',true);afterDelete.setSource('gutenberg',false);
assert.equal(afterDelete.prefs.preferredSources,'europepmc');
afterDelete.setSource('untrusted-service',true);assert.equal(afterDelete.prefs.preferredSources,'europepmc');
assert.match(Books.scienceQuery('quantum OR OPEN_ACCESS:n', ['pl','en']), /OPEN_ACCESS:y AND IN_PMC:y/);
assert.match(Books.scienceQuery('quantum', ['pl','en']), /LANG:pol OR LANG:eng/);
const scienceResponse = JSON.stringify({resultList:{result:[
    {pmcid:'PMC123',title:'Quantum &amp; science',authorString:'Example Scientist',language:'eng',isOpenAccess:'Y',firstPublicationDate:'2026-10-17'},
    {pmcid:'PMC999',title:'Paywalled item',isOpenAccess:'N'}, {pmcid:'bad-id',title:'Bad item',isOpenAccess:'Y'}
]},nextPageUrl:'https://untrusted.example/next'});
const scienceRows = Books.parseScience(scienceResponse);
assert.equal(scienceRows.rows.length,1);assert.equal(scienceRows.next,'');
assert.equal(scienceRows.rows[0].bookSource,'Europe PMC');assert.equal(scienceRows.rows[0].bookLanguage,'en');
const article = '<article><front><article-id pub-id-type="pmc">123</article-id><permissions><license>CC BY 4.0</license></permissions><abstract><p>Abstract here.</p></abstract></front><body><sec><title>Results</title><p>' + 'Evidence &amp; experiments. '.repeat(50) + '</p></sec></body><back><ref>Reference retained.</ref></back></article>';
const scientific = Books.scienceText(article,'europepmc:PMC123','Quantum & science','Example Scientist');
assert.match(scientific,/CC BY 4.0/);assert.match(scientific,/Source: Europe PMC/);
assert.match(scientific,/Evidence & experiments/);assert.match(scientific,/Reference retained/);assert.ok(!scientific.includes('<p>'));
assert.throws(()=>Books.scienceText(article.slice(0,-10),'europepmc:PMC123','x','y'),/incomplete/);
assert.throws(()=>Books.scienceText(article,'europepmc:PMC124','x','y'),/different article/);
const science = runtime();science.prefs.preferredSources='europepmc';
body=scienceResponse;network.length=0;science.searchBooks();
assert.equal(science.searchModel.count,1);assert.ok(network.every(url=>url.includes('europepmc')));
body=article;science.downloadBook('europepmc:PMC123','Quantum & science','Example Scientist','en',scienceRows.rows[0].downloadUrl);
assert.match(science.cachedBooks['europepmc:PMC123'].content,/CC BY 4.0/);
assert.match(runtime(science.prefs).cachedBooks['europepmc:PMC123'].content,/Evidence & experiments/);
const scienceSaved=science.prefs.offlineBooksJson;body=article.slice(0,-10);
science.downloadBook('europepmc:PMC123','Quantum','Scientist','en',scienceRows.rows[0].downloadUrl);
assert.equal(science.prefs.offlineBooksJson,scienceSaved);
body='not JSON';science.searchBooks();assert.equal(science.searching,false);assert.match(science.status,/unavailable/);
hung=true;
const pending=runtime();pending.downloadBook('gutenberg:777','Test','Writer','en','https://example.test/hang');
assert.equal(pending.downloadingId,'gutenberg:777');pending.unloading();assert.equal(pending.requests.length,0);
const native=runtime();
native.nativeJob={token:'unit-test-123',started:Date.now(),book:{id:'arxiv:2601.12345',title:'Quantum physics',author:'Researcher',language:'en',format:'pdf'}};
native.pendingNativePath='/home/root/.local/share/paperdesk/books-inbox/unit-test-123/Quantum physics.pdf';
native.nativeImported({id:'11111111-2222-3333-4444-555555555555'},null,'file:///other.pdf');
assert.ok(native.nativeJob,'Unrelated concurrent native imports must not be attributed to our download');
native.nativeImported({id:'11111111-2222-3333-4444-555555555555'},null,'file:///home/root/.local/share/paperdesk/books-inbox/unit-test-123/Quantum%20physics.pdf');
assert.equal(native.nativeJob,null);assert.equal(native.nativeBooks['arxiv:2601.12345'].format,'pdf');
assert.equal(native.isSaved('arxiv:2601.12345'),true);
assert.equal(runtime(native.prefs).nativeBooks['arxiv:2601.12345'].documentId,'11111111-2222-3333-4444-555555555555');
native.deleteBook('arxiv:2601.12345');assert.equal(native.isSaved('arxiv:2601.12345'),false);
assert.match(native.status,/document in My files has not been deleted/);
const wrapped=runtime();
wrapped.nativeBridge={lib:{entryForId(id){return {id,visibleName:'Paper book'}}}};
wrapped.nativeJob={token:'unit-wrapper-123',started:Date.now(),book:{id:'arxiv:2601.99999',title:'Paper book',author:'Researcher',language:'en',format:'pdf'}};
wrapped.pendingNativePath='/home/root/.local/share/paperdesk/books-inbox/unit-wrapper-123/Paper book.pdf';
wrapped.noteNativeEntry('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
assert.ok(wrapped.nativeJob,'A Library entry without source completion is not enough');
wrapped.nativeImported({},null,'file:///home/root/.local/share/paperdesk/books-inbox/unit-wrapper-123/Paper%20book.pdf');
assert.equal(wrapped.nativeBooks['arxiv:2601.99999'].documentId,'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
assert.equal(wrapped.nativeJob,null);
console.log('PaperDesk Books: catalogue authors/sorting, complete downloads, continuous full text, persistence, deletion and request cancellation OK');
