.pragma library

// Adapters return actual acquisition targets, never abstracts masquerading as books.
var sources = [
    {code: "gutenberg", title: "Project Gutenberg", detail: "Public-domain classics · text"},
    {code: "wolnelektury", title: "Wolne Lektury", detail: "Polish literature · EPUB for the tablet reader"},
    {code: "openstax", title: "OpenStax", detail: "Free textbooks · PDF with figures and formulae"},
    {code: "arxiv", title: "arXiv", detail: "Research preprints, not necessarily peer reviewed · PDF"},
    {code: "europepmc", title: "Europe PMC", detail: "Open-access research · readable text"},
    {code: "openlibrary", title: "Open Library", detail: "Unrestricted Archive editions only · PDF or EPUB"}
]
function known(code) { return sources.some(function(s) { return s.code === code }) }
function name(id) {
    var code = String(id).split(":")[0]
    for (var i = 0; i < sources.length; ++i) if (sources[i].code === code) return sources[i].title
    return "Unknown source"
}
function fold(s) {
    var accents = {ą:"a",ć:"c",ę:"e",ł:"l",ń:"n",ó:"o",ś:"s",ź:"z",ż:"z"}
    return String(s || "").toLowerCase().replace(/[ąćęłńóśźż]/g, function(c) { return accents[c] })
}
function matches(row, query) {
    var text = fold(row.bookTitle + " " + row.bookAuthor)
    return fold(query).trim().split(/\s+/).every(function(word) { return text.indexOf(word) >= 0 })
}
function languagesMatch(actual, selected) { return actual.split(",").some(function(l) { return selected.indexOf(l.trim()) >= 0 }) }
function wolneCatalogue(text) {
    var data = JSON.parse(text)
    if (!Array.isArray(data) || data.length > 20000) throw new Error("Unexpected Wolne Lektury catalogue")
    return data.filter(function(b) { return b.title && /^[a-z0-9-]+$/.test(b.slug || "") && !b.preview }).map(function(b) {
        return {bookId: "wolnelektury:" + b.slug, bookTitle: b.title, bookAuthor: b.author || "Unknown author",
            bookLanguage: "pl", bookSource: "Wolne Lektury", catalogueId: 0, published: "", format: "epub",
            downloadUrl: "https://wolnelektury.pl/api/books/" + b.slug + "/"}
    })
}
function wolneEdition(text, bookId, selected) {
    var b = JSON.parse(text), slug = bookId.slice("wolnelektury:".length)
    var language = ({pol:"pl",eng:"en",ger:"de",fre:"fr",spa:"es",ita:"it",nor:"no",por:"pt"})[b.language] || b.language
    if (b.preview || !b.title || !languagesMatch(language || "pl", selected) ||
        b.url !== "https://wolnelektury.pl/katalog/lektura/" + slug + "/" ||
        !/^https:\/\/wolnelektury\.pl\/media\/book\/epub\/[a-zA-Z0-9_.-]+\.epub$/.test(b.epub || ""))
        throw new Error("No complete EPUB in your selected languages is available.")
    return {url: b.epub, format: "epub", title: b.title, author: (b.authors || []).map(function(a) { return a.name }).join(" · "), language: language || "pl"}
}
function openstaxCatalogue(text) {
    var data = JSON.parse(text)
    if (!Array.isArray(data.items) || data.items.length > 1000) throw new Error("Unexpected OpenStax catalogue")
    return data.items.filter(function(b) {
        return b.id && b.title && b.book_state === "live" && /^https:\/\/assets\.openstax\.org\/[^\s]+\.pdf$/i.test(b.pdf_url || "") &&
               /^https:\/\/creativecommons\.org\//.test(b.license_url || "")
    }).map(function(b) {
        return {bookId:"openstax:"+b.id, bookTitle:b.title,
            bookAuthor:(b.authors || []).map(function(a) { return (a.value || {}).name || "" }).filter(function(n) { return n }).join(" · ") || "OpenStax",
            bookLanguage:(b.meta || {}).locale || "en", bookSource:"OpenStax", catalogueId:Number(b.id),
            published:(b.meta || {}).first_published_at || "", format:"pdf", downloadUrl:b.pdf_url,
            licence:b.license_name + " · " + b.license_url}
    })
}
function localPage(rows, query, languages, offset, sort) {
    var found = rows.filter(function(b) { return matches(b,query) && languagesMatch(b.bookLanguage,languages) })
    found.sort(function(a,b) {
        var key=sort === "author" ? "bookAuthor" : "bookTitle"
        if (sort === "newest" && a.published !== b.published) return a.published < b.published ? 1 : -1
        return a[key].localeCompare(b[key]) || a.bookId.localeCompare(b.bookId)
    })
    return {rows:found.slice(offset,offset+30),next:"",nextOffset:offset+30 < found.length ? offset+30 : -1}
}
function arxivQuery(query) {
    var words=String(query).replace(/["\\():]/g," ").trim().split(/\s+/).filter(function(w){return w})
    return words.length ? words.map(function(w){return 'all:"'+w+'"'}).join(" AND ") : "cat:quant-ph"
}
function arxiv(text, xml) {
    if (!/<feed\b/i.test(text)) throw new Error("Unexpected arXiv feed")
    var rows=[],entries=String(text).match(/<entry\b[\s\S]*?<\/entry>/gi)||[]
    for(var i=0;i<entries.length;++i) {
        var e=entries[i],id=/https?:\/\/arxiv\.org\/abs\/((?:[0-9]{4}\.[0-9]{4,5}|[a-z-]+\/[0-9]{7})(?:v[0-9]+)?)/.exec(xml.tagText(e,"id"))
        if(!id)continue
        var authors=e.match(/<author\b[\s\S]*?<\/author>/gi)||[]
        rows.push({bookId:"arxiv:"+id[1],bookTitle:xml.tagText(e,"title").replace(/\s+/g," "),
            bookAuthor:authors.map(function(a){return xml.tagText(a,"name")}).join(" · "),bookLanguage:"en",
            bookSource:"arXiv · preprint",catalogueId:0,published:xml.tagText(e,"published"),format:"pdf",
            downloadUrl:"https://arxiv.org/pdf/"+id[1]})
    }
    var start=Number(xml.tagText(text,"opensearch:startIndex")),total=Number(xml.tagText(text,"opensearch:totalResults"))
    return {rows:rows,next:"",nextOffset:rows.length && start+20<total ? start+20 : -1}
}
function openLibrary(text, languageCode) {
    var data=JSON.parse(text),rows=[]
    if(!Array.isArray(data.docs))throw new Error("Unexpected Open Library response")
    for(var i=0;i<data.docs.length;++i) {
        var b=data.docs[i],a=b.availability||{}
        // Work-level public access does NOT guarantee the first IA edition is free.
        if(b.ebook_access!=="public" || a.status!=="open" || a.is_restricted!==false || !a.is_readable ||
           !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,199}$/.test(a.identifier||"") || !/^\/works\/OL[0-9]+W$/.test(b.key||""))continue
        rows.push({bookId:"openlibrary:"+a.identifier,bookTitle:b.title,bookAuthor:(b.author_name||[]).join(" · ")||"Unknown author",
            bookLanguage:(b.language||[]).map(languageCode).join(","),bookSource:"Open Library / Internet Archive",catalogueId:0,
            published:String(b.first_publish_year||""),format:"native",downloadUrl:"https://archive.org/metadata/"+a.identifier})
    }
    return {rows:rows,next:"",nextOffset:Number(data.start||0)+20<Number(data.numFound||0) ? Number(data.start||0)+20 : -1}
}
function archiveEdition(text, id, selected) {
    var b=JSON.parse(text),identifier=id.slice("openlibrary:".length),meta=b.metadata||{}
    if(meta.identifier!==identifier || b.is_dark || meta.is_dark || meta.access_restricted===true || meta.access_restricted==="true" ||
       /(?:^|[, ])(?:inlibrary|printdisabled|borrowable|stream_only)(?:$|[, ])/.test(String(meta.collection||"")))
        throw new Error("This edition requires restricted access or borrowing.")
    var codes={eng:"en",english:"en",pol:"pl",polish:"pl",nor:"no",nob:"no",nno:"no",norwegian:"no",ger:"de",deu:"de",german:"de",fre:"fr",fra:"fr",french:"fr",spa:"es",spanish:"es",ita:"it",italian:"it",por:"pt",portuguese:"pt"}
    var languages=(Array.isArray(meta.language)?meta.language:[meta.language||""]).map(function(l){var v=String(l).toLowerCase();return codes[v]||v}).filter(function(l){return l})
    if(selected && !languages.some(function(l){return selected.indexOf(l)>=0}))throw new Error("This edition has no confirmed language matching your Settings.")
    var files=(b.files||[]).filter(function(f){return !f.private && !f.restricted && Number(f.size)>0 && Number(f.size)<=268435456 &&
        /\.(?:epub|pdf)$/i.test(f.name||"") && !/[\\/\x00-\x1f]/.test(f.name) && !/encrypted|lcp|drm|acs[mt]/i.test((f.format||"")+" "+f.name)})
    files.sort(function(a,b){return (/\.epub$/i.test(a.name)?0:1)-(/\.epub$/i.test(b.name)?0:1) || Number(a.size)-Number(b.size)})
    if(!files.length)throw new Error("No unrestricted PDF or EPUB download is available.")
    return {url:"https://archive.org/download/"+identifier+"/"+encodeURIComponent(files[0].name),format:/\.epub$/i.test(files[0].name)?"epub":"pdf",language:languages.join(",")}
}
