# PaperWeb for reMarkable 2

PaperWeb is a deliberately static web reader for e-ink. It uses the open-source
Qt 6 `XMLHttpRequest` network stack and Qt Rich Text renderer already present
in reMarkable OS.

## Design

- HTTP and HTTPS navigation with clickable links
- inline and external CSS are preserved where supported by Qt Rich Text
- JavaScript from websites is never executed (the tablet image has no WebEngine/WebKit runtime)
- scripts, forms, frames, video, audio, SVG and images are removed
- no animations or automatic refreshes
- two-finger pinch zoom from 100% to 250%, committed when fingers are released
- direct one-finger vertical scrolling with short, e-ink-friendly momentum
- 18 pt page text and large touch controls
- back, start, stop/open and close controls

The default start page is `https://lite.cnn.com/`. Enter another URL in the
address field; `https://` is added automatically when omitted.

## Limitations

This is a document browser, not Chromium. Static pages, articles, documentation
and many Wikipedia pages are useful. The renderer supports only a subset of
HTML/CSS; JavaScript applications, logins requiring complex forms, video sites
and anti-bot pages will not work.

## Installation path

Copy this directory to:

```text
/home/root/xovi/exthome/appload/paperweb
```

Compile `application.qrc` to `resources.rcc` with Qt `rcc --binary`, then restart
XOVI. The source QML remains included for inspection and modification.
