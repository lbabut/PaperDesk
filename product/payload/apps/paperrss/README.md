# PaperRSS for reMarkable 2

PaperRSS is a monochrome, touch-first RSS/Atom reader implemented as an
AppLoad frontend. It uses the Qt networking and XML support already
shipped with reMarkable OS; no background daemon is required.

## Features

- RSS 2.0 and Atom feeds.
- One-time science starter set: Physics World, Quanta Magazine, MIT
  Technology Review, ScienceDaily, and Nature Physics.
- Custom feed URLs through the native reMarkable keyboard.
- Persistent feed list, read state, favourites, and offline article cache.
- One-finger scrolling and two-finger reader zoom (100–240%).
- Simplified black-on-white summaries and full-page extraction.
- No animation or automatic background refresh.

Use **Refresh** to fetch subscriptions. Tap an article to read its cached
feed content. **Full text** downloads and simplifies the linked web page.
Feed and article content are cached in Qt Settings on the tablet.

## Installation

Copy this directory to `/home/root/xovi/exthome/appload/paperrss`,
compile `application.qrc` into `resources.rcc`, reload AppLoad, and open
PaperRSS. For the complete suite, follow `../../../MANUAL-INSTALL.md`.
