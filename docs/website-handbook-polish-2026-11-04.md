# Consistent notebook styling and linked prerequisites

Scope: the three PaperDesk HTML pages and shared website styling. Baseline: bce6815b1ce320ab783731d3c22597bcd2c0517e, verified against production before editing.

The Polish and English handbooks now load the same pencil/paper design system as the landing page. They share the PaperDesk wordmark, navigation, footer, colours and self-hosted handwriting font. A handbook-specific stylesheet handles the contents list, section hierarchy, code blocks, callouts, app instructions, smaller screens and printing. Existing shell command blocks are preserved byte for byte.

Both handbooks contain a three-part prerequisite checklist, linked from the Install tab:
1. XOVI: https://github.com/asivery/rm-xovi-extensions#to-install-xovi and https://github.com/asivery/rm-xovi-extensions/releases
2. qt-resource-rebuilder: https://github.com/asivery/rm-xovi-extensions/tree/master/qt-resource-rebuilder and the same extension releases page.
3. AppLoad: https://github.com/asivery/rm-appload and https://github.com/asivery/rm-appload/releases

The links were checked against the authors' public documentation on 4 November 2026. The XOVI extension repository documents installation and includes qt-resource-rebuilder by default. AppLoad's README identifies that dependency. The page keeps ARM32/ARMv7 and firmware compatibility explicit, and preserves deliberate manual XOVI startup.

The root Install tab links prerequisite names directly to their projects. Small shared refinements improve selected app buttons, navigation feedback, footer targets and image-note readability.

Validation: website/server tests and support placement regression checks; unchanged command-block comparison; local assets and guide fragments; desktop and 390px handbook rendering. Website-only publication with hashes checked against the GitHub commit. No tablet changes or application release are part of this work.
