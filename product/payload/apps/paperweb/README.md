# PaperWeb for reMarkable 2

PaperWeb is a reader-first web client for e-ink. It uses the Qt networking
and rich-text rendering available in the reMarkable/XOVI environment.
It is designed for documents and articles, not full browser applications.

## Features

- HTTP and HTTPS navigation with tappable links.
- Mobile or computer request mode, remembered between sessions.
- Optional static pictures, hidden by default and capped for the display.
- No execution of website JavaScript.
- Two-finger pinch zoom and direct one-finger scrolling without animation.
- Large touch controls for Back, address, Go/Stop, pictures, zoom, and Close.
- Last successfully opened HTTP or HTTPS address restored on relaunch.

Pictures use an external image gateway when enabled; see the product README
for the exact privacy behaviour. The keyboard opens only while the address
field is being edited.

## Limitations

Static pages, articles, documentation, and many Wikipedia pages are
useful. Complex JavaScript apps, advanced login forms, video sites,
and some anti-bot pages may not work. The reader simplifies page layout
to a single column and does not reproduce a full desktop browser.

## Installation path

Copy this directory to:

```text
/home/root/xovi/exthome/appload/paperweb
```

Compile `application.qrc` to `resources.rcc` with Qt
`rcc --binary`, then restart XOVI. The source QML remains included
for inspection and modification. For the complete suite, follow
`../../../MANUAL-INSTALL.md`.
