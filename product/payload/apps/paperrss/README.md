# PaperRSS for reMarkable 2

PaperRSS is a monochrome, touch-first RSS/Atom reader implemented as an AppLoad
frontend. It uses Qt networking and XML support already shipped with reMarkable
OS; no background daemon is required.

## Features

- RSS 2.0 and Atom feeds
- two verified starter feeds: BBC World and BBC Technology
- custom feed URLs through the native reMarkable keyboard
- persistent feed list, read state, favourites and an offline article cache
- one-finger scrolling and two-finger reader zoom (100-240%)
- stripped, black-on-white article summaries and full-page extraction
- no animation and no automatic background refresh

Use `ODSWIEZ` to fetch subscriptions. Tap an article to read its cached feed
content. `PELNY TEKST` downloads and simplifies the linked web page. Feed and
article content is cached in Qt Settings on the tablet.

## Installation

Copy this directory to `/home/root/xovi/exthome/appload/paperrss`, compile
`application.qrc` into `resources.rcc`, reload AppLoad, and open `PaperRSS`.
