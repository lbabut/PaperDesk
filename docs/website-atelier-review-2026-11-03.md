# PaperDesk: illustrated, tabbed redesign

This revision responds to the creator's rejection of the first pencil-themed landing page. The previous version was too long, its pencil treatment was too faint, the tablet frame was inaccurate and several screenshot assets were cropped.

## Result

Four addressable sections: Home, Apps, Install and About us. Only one section is visible at a time. Browser Back/Forward and old links such as #download, #tour and #support remain supported through fragment aliases. The footer has an explicit Home link. Without JavaScript, all sections remain available. Printing expands the sections.

Home has one concise proposition, a new original coloured-pencil still life, two useful actions and three brief notes. The previous repeated release and feature descriptions are removed. Detail belongs in the relevant tab or the existing installation guides.

Apps has eight selectors and one large screen at a time. Inspection found that terminal-shortcuts.png was 1404×720, rdp-session.png was 1404×300 and rss-reading-list.png was 288×900. They are unsuitable as full tablet screens. Every gallery source is now checked as exactly 1404×1872. New Sketch and Terminal screens come from actual 4.2.8 QML. The Sketch image contains a fresh demonstration drawing made through the app's stroke functions; it uses the host fallback renderer and is not evidence of native pigment behaviour or physical latency. RDP settings, RSS and Care use full interface renders; Books, Web and Dots use full historical tablet captures. RSS example content is labelled.

The frame follows the supplied physical tablet reference: light matte body, a darker strip down the left edge, narrow top/right bezels and a larger bottom bezel. The fabricated lower-bezel wordmark and polished metallic appearance are removed.

## Artwork and attribution

The hero is an original image-generation illustration in coloured pencil/wax crayon on textured paper. Prompt: an adult editorial still life of books, a mountain sketchbook, pencils and a coffee cup; strong paper tooth, a blank left area for text, no device UI, logos, text or watermark. Asset: website/assets/atelier/pencil-desk.webp. The built-in image-generation tool was used. The artwork also provides subtle paper texture elsewhere. Caveat is self-hosted with its SIL Open Font License.

The creator portrait is the actual public image observed on https://ko-fi.com/lbabut. Its storage.ko-fi.com image URL is retained directly; the creator's photo links to the supplied LinkedIn profile. No invented portrait or initials remain.

The OpenAI blossom uses the intact black logo path from the official brand page's Blossom_Light.svg. Construction diagrams and comparison examples are omitted, without altering the logo path or proportions. It is shown on a clear white field for the ChatGPT attribution, not as PaperDesk branding or an endorsement.

## Marketing judgement

This direction is visibly closer to the requested handmade character. The short cover introduces the product; the interactive collection shows it; installation has a dedicated space; authorship and optional support have a human context. Clear separation reduces scanning effort.

The key remaining product constraint is technical installation. Supported models, firmware, dependencies and manual SSH instructions remain explicit. Source availability, honest screenshot provenance, real authorship and a visible recovery guide are stronger credibility signals than inflated claims. No conversion uplift is claimed without measurement.

## Verification

Check local links and fragments, four section headings, eight app selectors and eight full-size images, live download count/map, keyboard tab navigation, creator-photo loading, OpenAI logo, desktop and 390px mobile layouts. Deployment is website-only: application packages, signed update feeds and statistics remain intact. Publish the reviewed website, tests and this document to GitHub and verify deployed file hashes.
