.pragma library

function normalize(text) { return String(text || "").replace(/\r\n?/g, "\n") }
function xmlText(text) {
    return String(text || "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
        .replace(/&#(x[0-9a-f]+|[0-9]+);/gi, function(_, code) {
            var value = code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code)
            return value > 0 && value <= 0x10ffff ? String.fromCodePoint(value) : ""
        }).replace(/&lt;/g, "<").replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&")
}
function tagText(xml, tag) {
    var match = new RegExp("<" + tag + "\\b[^>]*>([\\s\\S]*?)<\\/" + tag + ">", "i").exec(xml)
    return match ? xmlText(match[1].replace(/<[^>]+>/g, "")).trim() : ""
}
function attribute(tag, key) {
    var match = new RegExp("\\b" + key + "=[\"']([^\"']*)[\"']", "i").exec(tag)
    return match ? xmlText(match[1]) : ""
}
function httpsUrl(url) {
    if (url.indexOf("/") === 0 && url.indexOf("//") !== 0) return "https://www.gutenberg.org" + url
    return /^https:\/\//i.test(url) ? url : ""
}
function parseOpds(xml, language) {
    var entries = String(xml).match(/<entry\b[\s\S]*?<\/entry>/gi) || []
    var rows = []
    for (var i = 0; i < entries.length; ++i) {
        var entry = entries[i]
        var id = /\/ebooks\/([0-9]+)(?:\.opds|[<"'])/i.exec(entry)
        if (!id) continue
        var title = tagText(entry, "title")
        if (!title) continue
        var author = tagText(tagTextRaw(entry, "author"), "name")
        if (!author) author = tagText(entry, "content")
        rows.push({bookId: "gutenberg:" + id[1], bookTitle: title,
                   bookAuthor: author || "Unknown author", bookLanguage: language,
                   bookSource: "Project Gutenberg", catalogueId: Number(id[1]), published: tagText(entry, "published"),
                   downloadUrl: "https://www.gutenberg.org/cache/epub/" + id[1] + "/pg" + id[1] + ".txt"})
    }
    var header = String(xml).split(/<entry\b/i)[0]
    var links = header.match(/<link\b[^>]*>/gi) || []
    var next = ""
    for (var j = 0; j < links.length; ++j)
        if (attribute(links[j], "rel") === "next") next = httpsUrl(attribute(links[j], "href"))
    return {rows: rows, next: next}
}
function tagTextRaw(xml, tag) {
    var match = new RegExp("<" + tag + "\\b[^>]*>([\\s\\S]*?)<\\/" + tag + ">", "i").exec(xml)
    return match ? match[1] : ""
}
function sourceName(bookId) {
    return /^europepmc:/.test(bookId) ? "Europe PMC" : "Project Gutenberg"
}
function languageCode(code) {
    var codes = {eng: "en", pol: "pl", nor: "no", nob: "no", nno: "no", ger: "de", deu: "de",
                 fre: "fr", fra: "fr", spa: "es", ita: "it", por: "pt"}
    return codes[code] || code
}
function scienceQuery(query, languages) {
    var names = {en: "eng", pl: "pol", no: "nor", de: "ger", fr: "fre", es: "spa", it: "ita", pt: "por"}
    // Quote each word: user text must not override our open-access filters.
    var words = String(query).replace(/["\\]/g, " ").trim().split(/\s+/).filter(function(w) { return w.length > 0 })
    var terms = words.map(function(w) { return '"' + w + '"' }).join(" AND ")
    var langs = languages.filter(function(l) { return !!names[l] }).map(function(l) { return "LANG:" + names[l] })
    return (terms ? "(" + terms + ") AND " : "") + "OPEN_ACCESS:y AND IN_PMC:y" +
           (langs.length ? " AND (" + langs.join(" OR ") + ")" : "")
}
function parseScience(text) {
    var response = JSON.parse(text), rows = [], results = (response.resultList || {}).result || []
    for (var i = 0; i < results.length; ++i) {
        var b = results[i]
        if (!/^PMC[0-9]+$/.test(b.pmcid || "") || b.isOpenAccess !== "Y" || !b.title) continue
        rows.push({bookId: "europepmc:" + b.pmcid, bookTitle: xmlText(b.title.replace(/<[^>]+>/g, "")),
                   bookAuthor: b.authorString || "Authors not listed", bookLanguage: languageCode(b.language || "en"),
                   bookSource: "Europe PMC", catalogueId: Number(b.pmcid.slice(3)),
                   published: b.firstPublicationDate || b.pubYear || "",
                   downloadUrl: "https://www.ebi.ac.uk/europepmc/webservices/rest/" + b.pmcid + "/fullTextXML"})
    }
    var next = response.nextPageUrl || ""
    if (!/^https:\/\/www\.ebi\.ac\.uk\/europepmc\/webservices\/rest\/search\?/.test(next) || !rows.length) next = ""
    return {rows: rows, next: next}
}
function plainXml(xml) {
    return xmlText(String(xml).replace(/<\?(?:[\s\S]*?)\?>/g, "")
        .replace(/<!--[\s\S]*?-->/g, "")
        .replace(/<(?:script|style)\b[^>]*>[\s\S]*?<\/(?:script|style)>/gi, "")
        .replace(/<\/(?:p|title|sec|abstract|ref|list-item|tr|caption)>/gi, "\n\n")
        .replace(/<(?:break|br)\s*\/?\s*>/gi, "\n").replace(/<[^>]+>/g, " "))
        .replace(/&nbsp;/g, " ").replace(/[ \t]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim()
}
function scienceText(xml, bookId, title, author) {
    if (xml.length > 5000000 || !/<\/article>\s*$/i.test(xml) || !/<body\b/i.test(xml))
        throw new Error("The article is incomplete or its full text is unavailable.")
    var identity = /<article-id\b[^>]*pub-id-type=["']pmc["'][^>]*>(?:PMC)?([0-9]+)<\/article-id>/i.exec(xml)
    if (identity && "europepmc:PMC" + identity[1] !== bookId) throw new Error("The service returned a different article.")
    var body = plainXml(tagTextRaw(xml, "body"))
    if (body.length < 200) throw new Error("This article has no readable full text.")
    var abstract = plainXml(tagTextRaw(xml, "abstract")), permissions = plainXml(tagTextRaw(xml, "permissions"))
    return title + "\n" + author + "\n\nSource: Europe PMC · Open Access\nhttps://europepmc.org/articles/" + bookId.split(":")[1] +
        "\n" + (permissions ? permissions + "\n" : "") + "\n" + (abstract ? "Abstract\n\n" + abstract + "\n\n" : "") +
        body + "\n\n" + plainXml(tagTextRaw(xml, "back")) + "\n"
}
function authorFromText(content, fallback) {
    var match = /^Author:\s*([^\n\r]+)/mi.exec(String(content).slice(0, 12000))
    return match ? match[1].trim() : (fallback && fallback !== "Project Gutenberg" ? fallback : "Unknown author")
}
function validateDownload(content, bookId) {
    var text = String(content || "")
    if (text.length < 200 || text.length > 5000000 || /^\s*<(!doctype|html)/i.test(text))
        return "This file is not a supported plain-text book."
    if (!/\*{3}\s*END OF (?:THE|THIS) PROJECT GUTENBERG|End of (?:the )?Project Gutenberg/i.test(text))
        return "The download is incomplete. Please try again."
    var expected = /gutenberg:([0-9]+)/.exec(bookId)
    var actual = /\[(?:eBook|Etext)\s*#?\s*([0-9]+)/i.exec(text.slice(0, 12000))
    if (expected && actual && expected[1] !== actual[1]) return "The catalogue returned a different book. Please try again."
    return ""
}
function blocks(content, breaks) {
    var text = normalize(content), result = [], start = 0, breakIndex = 0
    breaks = breaks || []
    // Small, lazy text delegates keep a whole novel readable without one huge
    // Qt text layout. Every character belongs to exactly one block.
    while (start < text.length) {
        while (breakIndex < breaks.length && breaks[breakIndex] <= start) ++breakIndex
        var forced = breakIndex < breaks.length ? breaks[breakIndex] : text.length
        var end = Math.min(start + 1800, text.length, forced)
        if (end < text.length && end !== forced) {
            var boundary = text.lastIndexOf("\n\n", end)
            if (boundary < start + 600) boundary = text.lastIndexOf("\n", end)
            if (boundary < start + 600) boundary = text.lastIndexOf(" ", end)
            if (boundary >= start + 600) end = boundary + 1
            // Do not split a UTF-16 surrogate pair.
            var code = text.charCodeAt(end - 1)
            if (code >= 0xd800 && code <= 0xdbff) --end
        }
        result.push({body: text.slice(start, end), offset: start})
        start = end
    }
    return result
}
function indexForOffset(rows, offset) {
    var lo = 0, hi = rows.length - 1
    while (lo <= hi) {
        var mid = (lo + hi) >> 1
        if (rows[mid].offset <= offset) lo = mid + 1
        else hi = mid - 1
    }
    return Math.max(0, hi)
}
function sortRows(rows, order) {
    var copy = rows.slice()
    copy.sort(function(a, b) {
        if (order === "newest") {
            if (a.published && b.published && a.published !== b.published)
                return a.published < b.published ? 1 : -1
            if (a.catalogueId !== b.catalogueId) return b.catalogueId - a.catalogueId
        }
        var first = order === "author" ? a.bookAuthor : a.bookTitle
        var second = order === "author" ? b.bookAuthor : b.bookTitle
        var result = String(first).toLocaleLowerCase().localeCompare(String(second).toLocaleLowerCase())
        return result || a.bookTitle.localeCompare(b.bookTitle) || a.catalogueId - b.catalogueId
    })
    return copy
}
function checksum(text) {
    var hash = 2166136261
    for (var i = 0; i < text.length; ++i) { hash ^= text.charCodeAt(i); hash = Math.imul(hash, 16777619) }
    return (hash >>> 0).toString(16)
}

function legacyOffset(content, section) {
    var text = normalize(content), start = 0
    for (var i = 0; i < section && start < text.length; ++i) {
        var end = Math.min(start + 9000, text.length)
        if (end < text.length) { var boundary = text.lastIndexOf("\n\n", end); if (boundary > start + 4500) end = boundary + 2 }
        start = end
    }
    return start
}
