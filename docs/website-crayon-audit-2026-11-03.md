# PaperDesk website: content, visual and marketing review

Date: 3 November 2026. Baseline: GitHub main 3a0db31af37dc563271160d5c373ffe6b3f72e1b and the live 4.2.8 website. Scope: the landing page, its images, landing-page styling and relevant tests. Existing application payloads, signed feeds, archives, statistics and server code are unchanged.

## Direction and hierarchy

Warm textured paper, coloured-pencil lines, a quiet blue primary download action, a conspicuous raspberry Ko-fi action, and genuine application interfaces presented in dimensional tablet frames. The reading order is: download total/support; clear product proposition; eight-app collection; eight-app visual tour; current release; compatibility and installation; makers/community; detailed FAQ.

The main conversion is an informed installation, with compatibility visible before the download. Ko-fi is secondary in purpose but prominent in appearance, as requested. Support remains optional and unlocks no features.

## Content audit and changes

- The older canonical working directory still describes 3.0.3. It was preserved; development starts from the current 4.2.8 commit and verified live website in an isolated checkout.
- Eight applications are represented in both the collection and gallery. Sketch was missing from the previous visual tour.
- Removed the separate, repeated Paper Terminal launch announcement. Its unique engine and password-storage information is retained in the FAQ.
- Removed the repeated general support sales section; one makers/community section complements the top Ko-fi action.
- Corrected Sketch export descriptions to include PNG and PDF, including importing a PDF into My files for sharing.
- Replaced outdated release-specific social metadata with a new consistent sharing graphic.
- Replaced the Care link to the absent #care fragment with the existing #updates guide anchor.
- Removed the unrelated onboarding-email tracking parameter from Ko-fi URLs.
- Consolidated password-storage limitations in one clearly attributed SSH/RDP FAQ.
- Kept compatibility restrictions, manual SSH installation, deliberate XOVI startup, recovery instructions, privacy details and component licences visible.
- English and Polish guides already document 4.2.8 and PDF export. Their functional instructions remain current.
- Download total is above the hero. It remains a live aggregate package-download count with the existing country-map dialog, never an invented user count.
- Added the supplied LinkedIn destination for Łukasz and clearly labelled ChatGPT as an AI collaborator.
- Added an inline Reddit icon. No third-party widget, analytics script or remote font is added.

## Images and truthfulness

Seven new 1404×1872 UI renders are produced from current 4.2.8 QML with the existing AppLoad host test imports: Sketch, Books, Dots, Web, RSS, RDP settings and Care. They are UI renders, not newly photographed physical tablets or evidence of physical screen latency. Paper Terminal uses the existing tablet capture from 1 November. RSS uses clearly marked example articles to show a populated list without a live loading state. Each gallery caption identifies provenance. CSS adds a tablet body, subtle perspective and a shadow without changing the app pixels.

A diagnostic framebuffer read of the connected tablet was unsuitable for publication and is not included. No tablet restart, app installation, drawing deletion or XOVI autostart change was performed for this work.

The user's LinkedIn photo could not be retrieved: the public profile returned HTTP 999 and search did not expose a usable portrait. GitHub's avatar was inspected and is abstract, not a face. Therefore ŁB is an explicitly temporary visual placeholder; a real supplied portrait remains outstanding. Tiamat has an original pencil-style teal star icon and is explicitly described as ChatGPT.

## Marketing assessment

The strongest improvement is coherence: PaperDesk now reads as a friendly independent tool collection for an e-ink device. It communicates practical use cases before implementation details. Download, support and community actions have distinct roles. Source links, visible authorship, exact compatibility and honest image labels support credibility.

The technical installation requirement remains the largest conversion barrier. It is an actual product constraint and must not be hidden by stronger promises. The interface renders demonstrate available controls but are weaker proof than well-lit real-device photographs showing a meaningful drawing, a real terminal session and a readable book. A future genuine device shoot and the creator's real face would strengthen trust. These are follow-up content opportunities, not claims made by the page.

This is a qualitative design review, not a conversion uplift claim. No A/B test, user study, donation conversion data or unique-user measurement was performed.

## Verification

Run the website/server tests, design tests, content-integrity tests and support placement test. Check the desktop page, 390px iframe rendering, the download-map dialog, local asset URLs and guide fragments. Publish only the reviewed website changes and corresponding tests/documentation to GitHub. Verify deployed bytes against the source commit and preserve immutable application archives and statistics.
