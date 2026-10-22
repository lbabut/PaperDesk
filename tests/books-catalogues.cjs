const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function load(file){const ctx={};vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/../product/payload/apps/paperbooks/'+file,'utf8').replace(/^\.pragma library\s*/,''),ctx);return ctx;}
const C=load('catalogues.js'),B=load('books.js');
assert.equal(C.sources.length,6);assert.equal(C.known('untrusted'),false);
const wolne=C.wolneCatalogue(JSON.stringify([
 {title:'Studnia i wahadło',slug:'studnia-i-wahadlo',author:'Edgar Allan Poe'},
 {title:'Bad target',slug:'../secret'},{title:'Preview',slug:'preview',preview:true}
]));assert.equal(wolne.length,1);
assert.equal(C.localPage(wolne,'wahadlo',['pl'],0,'title').rows.length,1);
assert.equal(C.localPage(wolne,'wahadlo',['en'],0,'title').rows.length,0);
let edition={title:'Studnia i wahadło',language:'pol',url:'https://wolnelektury.pl/katalog/lektura/studnia-i-wahadlo/',epub:'https://wolnelektury.pl/media/book/epub/studnia-i-wahadlo.epub'};
assert.equal(C.wolneEdition(JSON.stringify(edition),wolne[0].bookId,['pl']).format,'epub');
for(const change of [{preview:true},{language:'eng'},{url:'https://evil.example/book'},{epub:'http://wolnelektury.pl/book.epub'}])
 assert.throws(()=>C.wolneEdition(JSON.stringify({...edition,...change}),wolne[0].bookId,['pl']));
const stax=C.openstaxCatalogue(JSON.stringify({items:[{id:1,title:'Physics',book_state:'live',license_url:'https://creativecommons.org/licenses/by/4.0/',license_name:'CC BY',pdf_url:'https://assets.openstax.org/physics.pdf',meta:{locale:'en'},authors:[{value:{name:'Scientist'}}]},
 {id:2,title:'Coming soon',book_state:'coming_soon',pdf_url:'https://assets.openstax.org/x.pdf'},
 {id:3,title:'Unknown licence',book_state:'live',pdf_url:'https://assets.openstax.org/x.pdf'}]}));
assert.equal(stax.length,1);assert.equal(stax[0].bookAuthor,'Scientist');assert.equal(stax[0].format,'pdf');
const feed='<feed><opensearch:startIndex>0</opensearch:startIndex><opensearch:totalResults>21</opensearch:totalResults><entry><id>http://arxiv.org/abs/2601.12345v2</id><title>Quantum\n physics</title><author><name>A &amp; B</name></author><summary>Not the full text</summary><published>2026-01-01</published></entry></feed>';
const arxiv=C.arxiv(feed,B);assert.equal(arxiv.rows[0].bookTitle,'Quantum physics');assert.equal(arxiv.rows[0].downloadUrl,'https://arxiv.org/pdf/2601.12345v2');assert.equal(arxiv.nextOffset,20);
assert.ok(!JSON.stringify(arxiv.rows).includes('Not the full text'));
assert.equal(C.arxivQuery('foo OR all:(bar)'), 'all:"foo" AND all:"OR" AND all:"all" AND all:"bar"');
const availability={status:'open',is_restricted:false,is_readable:true,identifier:'quantumtheory00reicuoft'};
let ol={key:'/works/OL123W',title:'Quantum theory',ebook_access:'public',availability,language:['eng'],author_name:['Reiche']};
assert.equal(C.openLibrary(JSON.stringify({docs:[ol]}),B.languageCode).rows.length,1);
for(const a of [{...availability,is_restricted:true},{...availability,status:'borrow_available'},{...availability,identifier:'../x'}])
 assert.equal(C.openLibrary(JSON.stringify({docs:[{...ol,availability:a}]}),B.languageCode).rows.length,0);
const archive={metadata:{identifier:availability.identifier,collection:['americana']},files:[{name:'book.epub',size:'12345',format:'EPUB'},{name:'book.pdf',size:'45678',format:'Text PDF'}]};
assert.equal(C.archiveEdition(JSON.stringify(archive),'openlibrary:'+availability.identifier).format,'epub');
for(const changed of [{is_dark:true},{metadata:{...archive.metadata,access_restricted:true}},{metadata:{...archive.metadata,collection:['inlibrary']}},{files:[{name:'../book.pdf',size:'123'}]},{files:[{name:'book.pdf',size:'300000000'}]},{files:[{name:'book.epub',size:'123',private:true}]}])
 assert.throws(()=>C.archiveEdition(JSON.stringify({...archive,...changed}),'openlibrary:'+availability.identifier));
const many=Array.from({length:61},(_,i)=>({...wolne[0],bookId:'w:'+i,bookTitle:'Book '+i}));
assert.equal(C.localPage(many,'',['pl'],0,'title').rows.length,30);
assert.equal(C.localPage(many,'',['pl'],30,'title').nextOffset,60);
assert.equal(C.localPage(many,'',['pl'],60,'title').nextOffset,-1);
console.log('Six Books catalogues: languages, editions, native formats, paging, licences and restricted-access rejection OK');
